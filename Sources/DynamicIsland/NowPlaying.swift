import AppKit

struct Track: Equatable {
    var app: String      // "Spotify" or "Music"
    var title: String
    var artist: String
    var playing: Bool
    var position: Double
    var duration: Double
}

/// Reads the current track from Spotify or Apple Music via AppleScript.
/// shortcut: only Spotify + Music; browser video (YouTube) needs MediaRemote, which Apple blocks for third-party apps.
@MainActor
final class NowPlaying: ObservableObject {
    @Published var track: Track?
    private var timer: Timer?

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in self.poll() }
        }
    }

    private static let bundles = ["Spotify": "com.spotify.client", "Music": "com.apple.Music"]

    private func isRunning(_ app: String) -> Bool {
        // Never send AppleScript to a closed app: `tell` would launch it.
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == Self.bundles[app] }
    }

    private func poll() {
        var found: Track?
        for app in ["Spotify", "Music"] where isRunning(app) {
            if let t = query(app), t.playing || found == nil { found = t }
            if found?.playing == true { break }
        }
        if found != track { track = found }
    }

    private func query(_ app: String) -> Track? {
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
        var err: NSDictionary?
        NSAppleScript(source: "tell application \"\(app)\" to \(command)")?.executeAndReturnError(&err)
        poll()
    }
}
