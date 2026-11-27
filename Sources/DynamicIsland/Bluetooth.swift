import AppKit
import IOBluetooth
import CoreAudio
import os

private let log = Logger(subsystem: "local.dynamicisland", category: "bt")

struct BTEvent: Equatable {
    var name: String
    var icon: String
    var connected: Bool
    var id = UUID()
}

/// Publishes a short-lived event whenever a Bluetooth device connects or disconnects.
/// Headphones/AirPods are detected as Bluetooth audio devices appearing in CoreAudio (IOBluetooth
/// never reported AirPods changing state). Mice/keyboards come from polling IOBluetooth paired devices.
struct BTDevice: Hashable {
    var name: String
    var icon: String
}

@MainActor
final class BluetoothWatcher: ObservableObject {
    @Published var event: BTEvent?
    @Published var devices: [BTDevice] = []   // everything connected right now, for the status icons
    private var others: [BTDevice] = []
    private var headphones: [BTDevice] = []
    private var connected: Set<String>?   // addresses; nil until the first scan
    private var hideWork: DispatchWorkItem?
    private var audio: [AudioDeviceID: String]?

    func start() {
        scan()
        scanAudio()
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.scanAudio() }  // delivered on .main, as requested above
        }
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    private func scan() {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let on = devices.filter { $0.isConnected() }
        let now = Set(on.compactMap(\.addressString))
        others = on.filter { !Self.isAudio($0) }.map { BTDevice(name: $0.name ?? "Bluetooth", icon: Self.icon($0)) }
        publishList()
        defer { connected = now }
        guard let before = connected else { return }   // first scan: just remember what's already on
        for d in devices where !Self.isAudio(d) {  // audio devices are reported by scanAudio
            guard let a = d.addressString else { continue }
            if now.contains(a) && !before.contains(a) { show(d, connected: true) }
            if !now.contains(a) && before.contains(a) { show(d, connected: false) }
        }
    }

    private func publishList() {
        // AirPods show up twice in CoreAudio (mic + speaker); dedupe by name.
        var seen = Set<String>()
        let list = (headphones + others).filter { seen.insert($0.name).inserted }.sorted { $0.name < $1.name }
        if list != devices { devices = list }
    }

    private static func isAudio(_ d: IOBluetoothDevice) -> Bool {
        d.deviceClassMajor == 0x04 || (d.name ?? "").lowercased().contains("airpod")
    }

    private func scanAudio() {
        let now = Self.bluetoothAudioDevices()
        headphones = Set(now.values).map { BTDevice(name: $0, icon: Self.audioIcon($0)) }
        publishList()
        defer { audio = now }
        guard let before = audio else { return }
        let added = Set(now.values).subtracting(before.values), removed = Set(before.values).subtracting(now.values)
        for name in added { post(name, icon: Self.audioIcon(name), connected: true) }
        for name in removed { post(name, icon: Self.audioIcon(name), connected: false) }
    }

    private static func audioIcon(_ name: String) -> String {
        name.lowercased().contains("airpod") ? "airpods" : "headphones"
    }

    /// Bluetooth audio devices CoreAudio currently knows about. An AirPods pair shows up as one
    /// device with both input and output, so key by device ID and keep the first name per ID.
    private static func bluetoothAudioDevices() -> [AudioDeviceID: String] {
        let sys = AudioObjectID(kAudioObjectSystemObject)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr else { return [:] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids) == noErr else { return [:] }
        var out: [AudioDeviceID: String] = [:]
        for id in ids {
            var transport: UInt32 = 0, tsize = UInt32(MemoryLayout<UInt32>.size)
            var taddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                   mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(id, &taddr, 0, nil, &tsize, &transport) == noErr,
                  transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
            else { continue }
            var name: Unmanaged<CFString>?
            var nsize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var naddr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                   mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectGetPropertyData(id, &naddr, 0, nil, &nsize, &name)
            out[id] = (name?.takeRetainedValue() as String?) ?? "Bluetooth"
        }
        return out
    }

    private func show(_ d: IOBluetoothDevice, connected: Bool) {
        post(d.name ?? "Bluetooth", icon: Self.icon(d), connected: connected)
    }

    private func post(_ name: String, icon: String, connected: Bool) {
        log.notice("post \(name, privacy: .public) connected=\(connected, privacy: .public)")
        event = BTEvent(name: name, icon: icon, connected: connected)
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.event = nil }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private static func icon(_ d: IOBluetoothDevice) -> String {
        let name = (d.name ?? "").lowercased()
        if name.contains("airpod") { return "airpods" }
        switch d.deviceClassMajor {
        case 0x04: return "headphones"                      // audio/video
        case 0x05: return d.deviceClassMinor & 0x10 != 0 ? "keyboard" : "computermouse" // peripheral
        case 0x02: return "iphone"                          // phone
        default: return "dot.radiowaves.left.and.right"
        }
    }
}
