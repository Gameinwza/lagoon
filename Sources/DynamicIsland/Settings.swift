import SwiftUI
import ServiceManagement

/// User preferences. Every key has a default, so the app works with zero setup.
enum Pref {
    static let waveColor = "waveColor", youtube = "youtube", btBanner = "btBanner",
               deviceIcons = "deviceIcons", hideAfter = "hideAfter", launchAtLogin = "launchAtLogin"

    static let defaults: [String: Any] = [
        waveColor: "blue", youtube: true, btBanner: true, deviceIcons: true, hideAfter: 3.0, launchAtLogin: true,
    ]
    static func register() { UserDefaults.standard.register(defaults: defaults) }
    static func reset() { defaults.keys.forEach(UserDefaults.standard.removeObject(forKey:)) }

    static func bool(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }

    static let colors: [(id: String, name: String, color: Color)] = [
        ("blue", "ฟ้า", .blue), ("green", "เขียว", .green), ("pink", "ชมพู", .pink),
        ("orange", "ส้ม", .orange), ("purple", "ม่วง", .purple), ("white", "ขาว", .white),
    ]
    static func color(_ id: String) -> Color { colors.first { $0.id == id }?.color ?? .blue }

    static func applyLaunchAtLogin() {
        let on = bool(launchAtLogin), s = SMAppService.mainApp
        if on, s.status != .enabled { try? s.register() }
        if !on, s.status == .enabled { try? s.unregister() }
    }
}

struct SettingsView: View {
    @AppStorage(Pref.waveColor) private var waveColor = "blue"
    @AppStorage(Pref.youtube) private var youtube = true
    @AppStorage(Pref.btBanner) private var btBanner = true
    @AppStorage(Pref.deviceIcons) private var deviceIcons = true
    @AppStorage(Pref.hideAfter) private var hideAfter = 3.0
    @AppStorage(Pref.launchAtLogin) private var launchAtLogin = true

    var body: some View {
        Form {
            Section("หน้าตา") {
                Picker("สีคลื่นเสียง", selection: $waveColor) {
                    ForEach(Pref.colors, id: \.id) { c in
                        Label { Text(c.name) } icon: { Image(systemName: "circle.fill").foregroundStyle(c.color) }.tag(c.id)
                    }
                }
                Picker("ซ่อนหลังหยุดเพลง", selection: $hideAfter) {
                    Text("3 วินาที").tag(3.0); Text("10 วินาที").tag(10.0)
                    Text("1 นาที").tag(60.0); Text("5 นาที").tag(300.0); Text("ไม่ซ่อน").tag(0.0)  // 0 = never
                }
            }
            Section("ฟีเจอร์") {
                Toggle("แสดง YouTube จากเบราว์เซอร์", isOn: $youtube)
                Toggle("แจ้งเตือนเมื่อ Bluetooth หลุด", isOn: $btBanner)
                Toggle("ไอคอนอุปกรณ์ในการ์ด", isOn: $deviceIcons)
            }
            Section("ระบบ") {
                Toggle("เปิดเองตอนเข้าเครื่อง", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { Pref.applyLaunchAtLogin() }
            }
            HStack {
                Button("คืนค่าเริ่มต้น") { Pref.reset(); Pref.applyLaunchAtLogin() }
                Spacer()
                Button("ปิดแอป") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize()
    }
}

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?
    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "ตั้งค่า Dynamic Island"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)  // only when the user asked for settings
        window?.makeKeyAndOrderFront(nil)
    }
}
