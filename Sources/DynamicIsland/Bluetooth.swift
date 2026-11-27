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
    var battery: Battery? = nil
}

/// Percentages; AirPods report left/right/case, other headphones often a single "main" level.
struct Battery: Hashable {
    var left: Int?, right: Int?, case_: Int?, main: Int?
    /// The number to show next to the icon: the emptier earbud, else the main level.
    var headline: Int? { [left, right].compactMap { $0 }.min() ?? main }
    var detail: String {
        [left.map { "ซ้าย \($0)%" }, right.map { "ขวา \($0)%" }, case_.map { "กล่อง \($0)%" }, main.map { "\($0)%" }]
            .compactMap { $0 }.joined(separator: " · ")
    }
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
    private var batteries: [String: Battery] = [:]
    private var batteryBusy = false
    private var ears: (left: Bool, right: Bool)?   // which AirPods are in an ear, from bluetoothd's log
    private var earLog: Process?

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
        refreshBattery()
        watchEars()
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshBattery() }
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
            .map { d in var d = d; d.battery = batteries[d.name]; d.icon = earIcon(d.icon); return d }
        if list != devices { devices = list }
    }

    /// Battery levels come from system_profiler (≈50 ms); there is no public API for AirPods battery.
    private func refreshBattery() {
        guard !batteryBusy else { return }
        batteryBusy = true
        DispatchQueue.global(qos: .utility).async {
            let b = Self.readBatteries()
            DispatchQueue.main.async {
                self.batteryBusy = false
                self.batteries = b
                self.publishList()
            }
        }
    }

    nonisolated private static func readBatteries() -> [String: Battery] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bt = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let devs = bt["device_connected"] as? [[String: [String: Any]]] else { return [:] }
        let pct = { (v: Any?) -> Int? in (v as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) } }
        var out: [String: Battery] = [:]
        for entry in devs {
            for (name, info) in entry {
                let b = Battery(left: pct(info["device_batteryLevelLeft"]), right: pct(info["device_batteryLevelRight"]),
                                case_: pct(info["device_batteryLevelCase"]), main: pct(info["device_batteryLevelMain"]))
                // The same AirPods can be listed twice (one entry missing the right bud); keep the fuller one.
                if b.headline != nil, out[name] == nil || (out[name]!.right == nil && b.right != nil) { out[name] = b }
            }
        }
        return out
    }

    /// There is no API for AirPods in-ear state, but bluetoothd logs it, e.g.
    /// "Plcm P InEar S InCase M Enabled, Prim Right" (P = primary bud, S = the other; S omitted = same as P).
    /// shortcut: parses a private log line, so a macOS update can break it; the icon then just stays "both".
    private func watchEars() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        p.arguments = ["stream", "--style", "compact", "--predicate",
                       #"process == "bluetoothd" AND eventMessage CONTAINS "Plcm P ""#]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            guard let text = String(data: h.availableData, encoding: .utf8) else { return }
            for line in text.split(separator: "\n") {
                guard let e = Self.parseEars(String(line)) else { continue }
                DispatchQueue.main.async {
                    guard let self, self.ears?.left != e.left || self.ears?.right != e.right else { return }
                    self.ears = e
                    self.publishList()
                }
            }
        }
        try? p.run()
        earLog = p
    }

    nonisolated static func parseEars(_ line: String) -> (left: Bool, right: Bool)? {
        func grab(_ pattern: String) -> String? {
            guard let r = line.range(of: pattern, options: .regularExpression) else { return nil }
            return String(line[r]).components(separatedBy: " ").last
        }
        guard let prim = grab(#"Prim (Left|Right)"#), let pState = grab(#"Plcm P [A-Za-z]+"#) else { return nil }
        let sState = grab(#" S [A-Za-z]+"#) ?? pState
        let primIn = pState == "InEar", secIn = sState == "InEar"
        return prim == "Left" ? (primIn, secIn) : (secIn, primIn)
    }

    private func earIcon(_ base: String) -> String {
        guard base == "airpods", let e = ears else { return base }
        switch (e.left, e.right) {
        case (true, false): return "airpod.left"
        case (false, true): return "airpod.right"
        case (false, false): return "airpods.chargingcase"
        default: return "airpods"
        }
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
        if connected { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.refreshBattery() } }
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
