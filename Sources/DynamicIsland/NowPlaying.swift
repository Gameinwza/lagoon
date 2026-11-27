import AppKit

struct Track: Equatable {
    var app: String      // "Spotify" or "Music"
    var title: String
    var artist: String
    var playing: Bool
    var position: Double
    var duration: Double
    var fetchedAt = Date()

    /// Position extrapolated to `now`, so the progress bar moves smoothly between polls.
    func position(at now: Date) -> Double {
        min(duration, position + (playing ? now.timeIntervalSince(fetchedAt) : 0))
    }
}

/// Reads the current track from Spotify or Apple Music via AppleScript.
/// shortcut: only Spotify + Music; browser video (YouTube) needs MediaRemote, which Apple blocks for third-party apps.
@MainActor
final class NowPlaying: ObservableObject {
    @Published var track: Track?
    private var timer: Timer?
    // AppleScript is synchronous (tens of ms per call); keep it off the main thread so animations don't stutter.
    private let queue = DispatchQueue(label: "nowplaying.applescript")
    private var busy = false

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in self.poll() }
        }
    }

    private static let bundles = ["Spotify": "com.spotify.client", "Music": "com.apple.Music"]

    private func poll() {
        guard !busy else { return }
        // Never send AppleScript to a closed app: `tell` would launch it.
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let apps = ["Spotify", "Music"].filter { running.contains(Self.bundles[$0]!) }
        busy = true
        queue.async {
            var found: Track?
            for app in apps {
                if let t = Self.query(app), t.playing || found == nil { found = t }
                if found?.playing == true { break }
            }
            DispatchQueue.main.async {
                self.busy = false
                if !Self.same(found, self.track) { self.track = found }
            }
        }
    }

    /// Ignore the small drift between our extrapolated position and the polled one.
    private static func same(_ a: Track?, _ b: Track?) -> Bool {
        guard var a, let b else { return a == nil && b == nil }
        if abs(a.position - b.position(at: a.fetchedAt)) < 1.5 { a.position = b.position; a.fetchedAt = b.fetchedAt }
        return a == b
    }

    nonisolated private static func query(_ app: String) -> Track? {
        // Spotify reports duration in ms, Music in seconds.
        let dur = app == "Spotify" ? "(duration of current track) / 1000" : "duration of current track"
        let src = """
        tell application "\(app)"
          if player state is stopped then return ""
          return (name of current track) & "\\n" & (artist of current track) & "\\n" & ¬
            (player state is playing) & "\\n" & (player position) & "\\n" & (\(dur))
        end tell
        """
        var err: NSDictionary?
        guard let out = NSAppleScript(source: src)?.executeAndReturnError(&err).stringValue,
              !out.isEmpty else { return nil }
        let p = out.components(separatedBy: "\n")
        guard p.count == 5 else { return nil }
        let num = { (s: String) in Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        return Track(app: app, title: p[0], artist: p[1], playing: p[2] == "true",
                     position: num(p[3]), duration: num(p[4]))
    }

    func send(_ command: String) {
        guard let app = track?.app else { return }
        queue.async {
            var err: NSDictionary?
            NSAppleScript(source: "tell application \"\(app)\" to \(command)")?.executeAndReturnError(&err)
            DispatchQueue.main.async { self.poll() }
        }
    }
}
