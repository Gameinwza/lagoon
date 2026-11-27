import AppKit
import SwiftUI
import ServiceManagement

/// Shared hover state: driven by the mouse position, not SwiftUI's onHover,
/// because the window ignores mouse events whenever the cursor is outside the island.
@MainActor
final class IslandState: ObservableObject {
    @Published var hover = false
    var size = CGSize(width: 200, height: 32)
}

/// Borderless panel pinned to the top-center of the notched screen, above the menu bar.
/// It stays a fixed size (resizing a window mid-animation is what made it stutter) and
/// becomes click-through outside the island so it never blocks the menu bar.
final class IslandPanel: NSPanel {
    static let maxSize = CGSize(width: 420, height: 180)

    init(view: NSView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar + 1
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = view
    }

    var screenForIsland: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main!
    }

    func place() {
        let f = screenForIsland.frame, s = Self.maxSize
        setFrame(NSRect(x: f.midX - s.width / 2, y: f.maxY - s.height, width: s.width, height: s.height), display: true)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let np = NowPlaying()
    let state = IslandState()
    var panel: IslandPanel!

    func applicationDidFinishLaunching(_ n: Notification) {
        panel = IslandPanel(view: NSHostingView(rootView: IslandView(np: np, state: state)))
        panel.place()
        panel.orderFrontRegardless()
        np.start()
        // Start automatically at login (shows under System Settings → General → Login Items).
        if SMAppService.mainApp.status != .enabled { try? SMAppService.mainApp.register() }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.panel.place() }
        }
        // Cheap 60 Hz check of the cursor; needs no Accessibility permission.
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.trackMouse() }
        }
    }

    private func trackMouse() {
        let f = panel.screenForIsland.frame, s = state.size
        let hot = NSRect(x: f.midX - s.width / 2, y: f.maxY - s.height, width: s.width, height: s.height)
            .insetBy(dx: -6, dy: -6)
        let inside = hot.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        let hover = inside && np.track != nil
        if hover != state.hover {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { state.hover = hover }
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
