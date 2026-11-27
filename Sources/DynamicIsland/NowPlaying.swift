import AppKit
import os

private let npLog = Logger(subsystem: "com.gameinwza.lagoon", category: "np")

struct Track: Equatable {
    var app: String      // "Spotify", "Music", "Google Chrome", "Brave Browser" or "Safari"
    var title: String
    var artist: String
    var playing: Bool
    var position: Double
    var duration: Double
    var fetchedAt = Date()
    // YouTube only: which tab, and the thumbnail.
    var tab: (window: Int, index: Int)? = nil
    var artURL: URL? = nil

    var isVideo: Bool { tab != nil }

    /// Position extrapolated to `now`, so the progress bar moves smoothly between polls.
    func position(at now: Date) -> Double {
        min(duration, position + (playing ? now.timeIntervalSince(fetchedAt) : 0))
    }

    static func == (a: Track, b: Track) -> Bool {
        a.app == b.app && a.title == b.title && a.artist == b.artist && a.playing == b.playing
            && a.position == b.position && a.duration == b.duration && a.fetchedAt == b.fetchedAt
            && a.tab?.window == b.tab?.window && a.tab?.index == b.tab?.index && a.artURL == b.artURL
    }
}

/// Reads what's playing from Spotify, Apple Music, or a YouTube tab via AppleScript.
@MainActor
final class NowPlaying: ObservableObject {
    @Published var track: Track?
    @Published var art: NSImage?
    private var artKey = ""
    private var timer: Timer?
    // AppleScript is synchronous (tens of ms per call); keep it off the main thread so animations don't stutter.
    private let queue = DispatchQueue(label: "nowplaying.applescript")
    private var busy = false
    // Paused for more than this long → report nothing, so the island fades away (short, so a pause
    // reads as "stopped", but long enough to see the pause register).
    private var pausedKey: String?
    private var pausedAt = Date()
    private var generation = 0  // bumped on every command so polls started earlier can't undo it

    func start() {
        poll()
        // Spotify and Music announce every play/pause/skip (media keys included); refresh at once
        // instead of waiting for the next 1 s poll.
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshNow() }  // queue: .main, so this is the main thread
            }
        }
        // Spotify/Music push changes (above), so they're only re-checked every 10 s as a fallback.
        // Browsers don't, so YouTube is checked every 0.3 s while a video is playing, 2 s while one is paused, else every 8 s.
        // Switching to a browser re-plans the timer at once instead of waiting out the 8 s idle gap.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    private var lastPlayers = Date(), lastBrowsers = Date()

    /// One-shot timer that sleeps until the next check is due, so idle means ~1 wakeup every few seconds.
    private func tick() {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let browserFront = Pref.bool(Pref.youtube) && Self.bundles.dropFirst(2).contains { $0.1 == front }
        // Playing video 0.3 s; paused video 2 s; browser in front (user may be opening one) 1 s; else 8 s.
        let browserGap: Double = track?.isVideo == true ? (track?.playing == true ? 0.3 : 2) : (browserFront ? 1 : 8)
        let now = Date()
        let players = now.timeIntervalSince(lastPlayers) >= 10
        let browsers = now.timeIntervalSince(lastBrowsers) >= browserGap
        if players || browsers {
            if players { lastPlayers = now }
            lastBrowsers = now
            if browserFront && !players && track?.isVideo != true, let app = Self.bundles.first(where: { $0.1 == front })?.0 {
                // Cheap: only ask the front tab's URL; scan all tabs once it's a YouTube video.
                queue.async {
                    let tab = app == "Safari" ? "current tab" : "active tab"
                    let url = Self.run("tell application \"\(app)\" to get URL of \(tab) of front window")?.stringValue ?? ""
                    if url.contains("youtube.com/watch") { DispatchQueue.main.async { self.poll(players: false) } }
                }
            } else {
                poll(players: players)
            }
        }
        let wait = min(10 - now.timeIntervalSince(lastPlayers), browserGap - now.timeIntervalSince(lastBrowsers))
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(wait, 0.3), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }  // scheduled on the main run loop
        }
        timer?.tolerance = 0.1
    }

    // Checked in this order; the first one that is actually playing wins.
    private static let bundles: [(String, String)] = [
        ("Spotify", "com.spotify.client"), ("Music", "com.apple.Music"),
        ("Google Chrome", "com.google.Chrome"), ("Brave Browser", "com.brave.Browser"), ("Safari", "com.apple.Safari"),
    ]

    /// Last Spotify/Music result, reused by polls that only check browsers. Only touched on `queue`.
    nonisolated(unsafe) private static var playerCache: [Track] = []

    private func poll(players: Bool = true) {
        guard !busy else { return }
        // Never send AppleScript to a closed app: `tell` would launch it.
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let youtube = Pref.bool(Pref.youtube)
        let apps = Self.bundles.enumerated().filter { running.contains($0.element.1) && (youtube || $0.offset < 2) }.map(\.element.0)
        busy = true
        let gen = generation
        queue.async {
            let isPlayer = { ["Spotify", "Music"].contains($0) }
            if players {
                Self.playerCache = apps.filter(isPlayer).compactMap(Self.queryPlayer)
            }
            // Cached player tracks may be stale on position; the view extrapolates it anyway.
            var found: Track?
            for t in Self.playerCache where apps.contains(t.app) {
                if t.playing || found == nil { found = t }
            }
            if found?.playing != true {
                for app in apps where !isPlayer(app) {
                    if let t = Self.queryYouTube(app), t.playing || found == nil { found = t }
                    if found?.playing == true { break }
                }
            }
            DispatchQueue.main.async {
                self.busy = false
                guard gen == self.generation else { return }  // stale: a command ran meanwhile
                let found = self.hideIfPausedTooLong(found)
                if !Self.same(found, self.track) { self.track = found }
                self.loadArtIfNeeded()
            }
        }
    }

    /// Ignore the small drift between our extrapolated position and the polled one.
    private static func same(_ a: Track?, _ b: Track?) -> Bool {
        guard var a, let b else { return a == nil && b == nil }
        if abs(a.position - b.position(at: a.fetchedAt)) < 1.5 { a.position = b.position; a.fetchedAt = b.fetchedAt }
        return a == b
    }

    /// Compiled scripts, reused across polls. Compiling every second was the main idle-CPU cost:
    /// macOS scans each newly compiled script with XProtect. Only touched from `queue` (serial).
    nonisolated(unsafe) private static var compiled: [String: NSAppleScript] = [:]

    nonisolated private static func run(_ src: String) -> NSAppleEventDescriptor? {
        var err: NSDictionary?
        let s: NSAppleScript
        if let c = compiled[src] { s = c } else {
            guard let n = NSAppleScript(source: src) else { return nil }
            // One-off commands (seek positions, tab refs) vary; don't let them grow the cache forever.
            if compiled.count < 32, n.compileAndReturnError(&err) { compiled[src] = n }
            s = n
        }
        let r = s.executeAndReturnError(&err)
        if let err { npLog.error("AppleScript \(err[NSAppleScript.errorNumber] as? Int ?? 0, privacy: .public): \(err[NSAppleScript.errorMessage] as? String ?? "", privacy: .public)") }
        return r
    }

    nonisolated private static func num(_ s: String) -> Double {
        Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    // MARK: Spotify / Music

    nonisolated private static func queryPlayer(_ app: String) -> Track? {
        // Spotify reports duration in ms, Music in seconds.
        let dur = app == "Spotify" ? "(duration of current track) / 1000" : "duration of current track"
        let src = """
        tell application "\(app)"
          if player state is stopped then return ""
          return (name of current track) & "\\n" & (artist of current track) & "\\n" & ¬
            (player state is playing) & "\\n" & (player position) & "\\n" & (\(dur))
        end tell
        """
        guard let out = run(src)?.stringValue, !out.isEmpty else { return nil }
        let p = out.components(separatedBy: "\n")
        guard p.count == 5 else { return nil }
        return Track(app: app, title: p[0], artist: p[1], playing: p[2] == "true",
                     position: num(p[3]), duration: num(p[4]))
    }

    // MARK: YouTube in a browser

    /// Reads the <video> element. Needs "Allow JavaScript from Apple Events" in the browser;
    /// without it we still show the tab title, just no progress or play state.
    nonisolated private static let readJS =
        "(()=>{const v=document.querySelector('video');if(!v)return '';" +
        "const c=document.querySelector('ytd-watch-metadata ytd-channel-name a, #owner #channel-name a');" +
        "return [v.paused?0:1,v.currentTime,v.duration||0,c?c.textContent.trim():''].join('|')})()"

    nonisolated private static func jsCall(_ app: String, _ js: String, tab: String) -> String {
        app == "Safari" ? "do JavaScript \"\(js)\" in \(tab)" : "execute \(tab) javascript \"\(js)\""
    }

    nonisolated private static func queryYouTube(_ app: String) -> Track? {
        let titleProp = app == "Safari" ? "name" : "title"
        // Returns the first playing YouTube tab, else the first YouTube tab.
        let src = """
        tell application "\(app)"
          set firstHit to ""
          repeat with w in windows
            set urls to URL of every tab of w
            repeat with i from 1 to count of urls
              if item i of urls contains "youtube.com/watch" then
                set t to tab i of w
                set r to ""
                try
                  set r to \(jsCall(app, readJS, tab: "t"))
                on error
                  set r to "JSOFF"
                end try
                set hit to (id of w as text) & "\\n" & i & "\\n" & (item i of urls) & "\\n" & (\(titleProp) of t) & "\\n" & r
                if r starts with "1|" then return hit
                if firstHit is "" then set firstHit to hit
              end if
            end repeat
          end repeat
          return firstHit
        end tell
        """
        guard let out = run(src)?.stringValue, !out.isEmpty else { return nil }
        let p = out.components(separatedBy: "\n")
        guard p.count >= 4, let win = Int(p[0]), let idx = Int(p[1]) else { return nil }
        // "(3) Video name - YouTube" -> "Video name"
        let title = p[3].replacingOccurrences(of: #"^\(\d+\)\s*|\s*-\s*YouTube$"#, with: "", options: .regularExpression)
        let vid = URLComponents(string: p[2])?.queryItems?.first { $0.name == "v" }?.value
        let js = p.count > 4 ? p[4].components(separatedBy: "|") : []
        var t = Track(app: app, title: title, artist: "YouTube", playing: false, position: 0, duration: 0,
                      tab: (win, idx), artURL: vid.flatMap { URL(string: "https://i.ytimg.com/vi/\($0)/hqdefault.jpg") })
        if p.count > 4, p[4] == "JSOFF" {
            // The browser blocks JavaScript from Apple Events, so play state is unknown: stay visible with a fix-it hint.
            t.playing = true
            t.artist = "เปิด View › Developer › Allow JavaScript…"
        } else if js.count == 4 {
            t.playing = js[0] == "1"
            t.position = num(js[1])
            t.duration = num(js[2])
            if !js[3].isEmpty { t.artist = js[3] }
        }
        return t
    }

    nonisolated private static func tabRef(_ t: Track) -> String {
        "tab \(t.tab!.index) of window id \(t.tab!.window)"
    }

    // MARK: Art, open, controls

    /// Fetch cover art only when the song changes, never on every poll.
    private func loadArtIfNeeded() {
        guard let t = track else { artKey = ""; return }  // keep the cover while the island fades out
        let key = t.app + t.title + t.artist
        guard key != artKey else { return }
        artKey = key
        art = nil
        queue.async {
            let img = Self.fetchArt(t)
            DispatchQueue.main.async { if self.artKey == key { self.art = img } }
        }
    }

    nonisolated private static func fetchArt(_ t: Track) -> NSImage? {
        var url = t.artURL
        if t.app == "Spotify", let s = run("tell application \"Spotify\" to artwork url of current track")?.stringValue {
            url = URL(string: s)
        }
        if let url, url.scheme == "https", let data = try? Data(contentsOf: url) { return NSImage(data: data) }
        if t.app == "Music" {
            // Music returns the image bytes directly.
            guard let d = run("tell application \"Music\" to get raw data of artwork 1 of current track")?.data
            else { return nil }
            return NSImage(data: d)
        }
        return nil
    }

    /// Show the current song/video in its app.
    func openInApp() {
        guard let t = track else { return }
        queue.async {
            switch t.app {
            case "Spotify":
                // spotify:track:... opens that song's page in Spotify.
                if let s = Self.run("tell application \"Spotify\" to spotify url of current track")?.stringValue,
                   let url = URL(string: s), url.scheme == "spotify" {
                    DispatchQueue.main.async { NSWorkspace.shared.open(url) }
                }
            case "Music":
                _ = Self.run("tell application \"Music\"\nactivate\nreveal current track\nend tell")
            case "Safari":
                let w = "window id \(t.tab!.window)"
                _ = Self.run("tell application \"Safari\"\nset current tab of \(w) to \(Self.tabRef(t))\nset index of \(w) to 1\nactivate\nend tell")
            default:
                let w = "window id \(t.tab!.window)"
                _ = Self.run("tell application \"\(t.app)\"\nset active tab index of \(w) to \(t.tab!.index)\nset index of \(w) to 1\nactivate\nend tell")
            }
        }
    }

    private func hideIfPausedTooLong(_ t: Track?) -> Track? {
        guard let t, !t.playing else { pausedKey = nil; return t }
        let key = t.app + t.title
        if pausedKey != key { pausedKey = key; pausedAt = Date() }
        let after = UserDefaults.standard.double(forKey: Pref.hideAfter)  // 0 = never hide
        return after > 0 && Date().timeIntervalSince(pausedAt) > after ? nil : t
    }

    /// Poll right away, discarding any poll already in flight (it may carry the old state).
    private func refreshNow() {
        generation += 1
        busy = false
        poll()
    }

    enum Command: Equatable { case playPause, next, previous, seek(Double) }

    func send(_ c: Command) {
        guard var t = track else { return }
        generation += 1
        if c == .playPause {
            // Flip the button now; the next poll confirms it.
            t.position = t.position(at: Date())
            t.fetchedAt = Date()
            t.playing.toggle()
            track = t
        }
        if case .seek(let to) = c {
            // Jump the bar now; the next poll confirms it.
            t.position = to
            t.fetchedAt = Date()
            track = t
        }
        queue.async {
            if t.isVideo {
                let js = switch c {
                case .playPause: "(()=>{const v=document.querySelector('video');v.paused?v.play():v.pause()})()"
                case .next: "document.querySelector('.ytp-next-button').click()"
                case .previous: "document.querySelector('video').currentTime=0"
                case .seek(let to): "document.querySelector('video').currentTime=\(to)"
                }
                _ = Self.run("tell application \"\(t.app)\" to \(Self.jsCall(t.app, js, tab: Self.tabRef(t)))")
            } else {
                let cmd = switch c {
                case .playPause: "playpause"
                case .next: "next track"
                case .previous: "previous track"
                case .seek(let to): "set player position to \(to)"
                }
                _ = Self.run("tell application \"\(t.app)\" to \(cmd)")
            }
            // The player needs a moment to apply the command before it reports the new state.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.busy = false; self.poll() }
        }
    }
}
