import AppKit
import SwiftUI

/// Borderless panel pinned to the top-center of the built-in screen, above the menu bar.
final class IslandPanel: NSPanel {
    init(view: NSView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar + 1
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = view
    }

    private var size = CGSize(width: 200, height: 32)

    /// Keep the window as small as the island so it never blocks menu-bar clicks.
    func resize(to s: CGSize) {
        let grow = s.height > size.height || s.width > size.width
        size = s
        // Grow now; shrink after the spring finishes so the animation isn't clipped.
        DispatchQueue.main.asyncAfter(deadline: .now() + (grow ? 0 : 0.45)) { [weak self] in
            guard let self, self.size == s else { return }
            self.place()
        }
    }

    func place() {
        // Prefer the screen with a notch; fall back to the main screen.
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main!
        let w = size.width + 20, h = size.height + 10
        setFrame(NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h), display: true)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let np = NowPlaying()
    var panel: IslandPanel!

    func applicationDidFinishLaunching(_ n: Notification) {
        let host = NSHostingView(rootView: IslandView(np: np) { [weak self] s in self?.panel?.resize(to: s) })
        panel = IslandPanel(view: host)
        panel.place()
        panel.orderFrontRegardless()
        np.start()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.panel.place() }
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // no Dock icon
    app.run()
}
