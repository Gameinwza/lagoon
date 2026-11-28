import AppKit
import SwiftUI
import ServiceManagement

/// Shared hover state: driven by the mouse position, not SwiftUI's onHover,
/// because the window ignores mouse events whenever the cursor is outside the island.
@MainActor
final class IslandState: ObservableObject {
    @Published var hover = false
    var size = CGSize(width: 200, height: 32)
    var shiftX: CGFloat = 0  // island center offset from the screen center (timer grows it rightward)
    @Published var screenChanges = 0
}

/// Borderless panel pinned to the top-center of the notched screen, above the menu bar.
/// It stays a fixed size (resizing a window mid-animation is what made it stutter) and
/// becomes click-through outside the island so it never blocks the menu bar.
final class IslandPanel: NSPanel {
    static let maxSize = CGSize(width: 520, height: 320)  // room for the Bluetooth list and a right-shifted timer

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

    var screenForIsland: NSScreen { Notch.screen }

    func place() {
        let f = screenForIsland.frame, s = Self.maxSize
        setFrame(NSRect(x: f.midX - s.width / 2, y: f.maxY - s.height, width: s.width, height: s.height), display: true)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let np = NowPlaying()
    let state = IslandState()
    let bt = BluetoothWatcher()
    let audio = OutputAudio()
    var panel: IslandPanel!

    func applicationDidFinishLaunching(_ n: Notification) {
        // The island is a panel, not a window, so macOS would otherwise see an idle app and quit it.
        ProcessInfo.processInfo.disableAutomaticTermination("island is always on screen")
        ProcessInfo.processInfo.disableSuddenTermination()
        Pref.register()
        Updater.shared.applyAutoCheck()
        panel = IslandPanel(view: NSHostingView(rootView: IslandView(np: np, state: state, bt: bt, audio: audio)))
        panel.place()
        panel.orderFrontRegardless()
        TopSpace.add(panel)
        np.start()
        bt.start()
        audio.start()
        // Start automatically at login (shows under System Settings → General → Login Items).
        Pref.applyLaunchAtLogin()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.panel.place(); self?.state.screenChanges += 1 }
        }
        // React to mouse movement events instead of polling (a 60 Hz timer cost ~several % CPU idle).
        // Global monitors for mouse moves need no Accessibility permission.
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackMouse() }  // delivered on the main thread
        }
        NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in
            MainActor.assumeIsolated { self?.trackMouse() }
            return e
        }
        panel.acceptsMouseMovedEvents = true
    }

    /// Opening the app again (Finder, Spotlight, `open`) shows settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.show(); return false
    }

    private func trackMouse() {
        let f = panel.screenForIsland.frame, s = state.size
        let hot = NSRect(x: f.midX - s.width / 2 + state.shiftX, y: f.maxY - s.height, width: s.width, height: s.height)
            .insetBy(dx: -6, dy: -6)
        let inside = hot.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        let hover = inside && (np.track != nil || !Reminders.shared.items.isEmpty)  // timers get a card too
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
