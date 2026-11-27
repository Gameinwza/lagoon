import AppKit
import IOBluetooth

struct BTEvent: Equatable {
    var name: String
    var icon: String
    var connected: Bool
    var id = UUID()
}

/// Publishes a short-lived event whenever a Bluetooth device connects or disconnects.
@MainActor
final class BluetoothWatcher: NSObject, ObservableObject {
    @Published var event: BTEvent?
    private var started = Date()
    private var connectNote: IOBluetoothUserNotification?
    private var hideWork: DispatchWorkItem?

    func start() {
        started = Date()
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
    }

    @objc nonisolated private func connected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        MainActor.assumeIsolated {
            device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))
            // Registering fires once for every device already connected at launch; skip those.
            if Date().timeIntervalSince(started) > 2 { show(device, connected: true) }
        }
    }

    @objc nonisolated private func disconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        note.unregister()
        MainActor.assumeIsolated { show(device, connected: false) }
    }

    private func show(_ d: IOBluetoothDevice, connected: Bool) {
        event = BTEvent(name: d.name ?? "Bluetooth", icon: Self.icon(d), connected: connected)
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.event = nil }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private static func icon(_ d: IOBluetoothDevice) -> String {
        let name = (d.name ?? "").lowercased()
        if name.contains("airpods") { return "airpods" }
        switch d.deviceClassMajor {
        case 0x04: return "headphones"                      // audio/video
        case 0x05: return d.deviceClassMinor & 0x10 != 0 ? "keyboard" : "computermouse" // peripheral
        case 0x02: return "iphone"                          // phone
        default: return "dot.radiowaves.left.and.right"
        }
    }
}
