import SwiftUI
import ServiceManagement

/// User preferences. Every key has a default, so the app works with zero setup.
enum Pref {
    static let waveColor = "waveColor", youtube = "youtube", btBanner = "btBanner",
               deviceIcons = "deviceIcons", hideAfter = "hideAfter", launchAtLogin = "launchAtLogin"

    static let defaults: [String: Any] = [
        waveColor: "blue", youtube: true, btBanner: true, deviceIcons: true, hideAfter: 3.0, launchAtLogin: true,
    ]
    static func register() {
        UserDefaults.standard.register(defaults: defaults)
        // Carry settings over from before the rename (bundle id was local.dynamicisland).
        let d = UserDefaults.standard
        if d.object(forKey: "migrated") == nil, let old = UserDefaults(suiteName: "local.dynamicisland") {
            for k in defaults.keys { if let v = old.object(forKey: k) { d.set(v, forKey: k) } }
            d.set(true, forKey: "migrated")
        }
    }
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

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                Section("หน้าตา") {
                    LabeledContent { swatches } label: { row("waveform", .blue, "สีคลื่นเสียง") }
                    Picker(selection: $hideAfter) {
                        Text("3 วิ").tag(3.0); Text("10 วิ").tag(10.0); Text("1 นาที").tag(60.0)
                        Text("5 นาที").tag(300.0); Text("ไม่ซ่อน").tag(0.0)  // 0 = never
                    } label: { row("eye.slash.fill", .gray, "ซ่อนหลังหยุดเพลง") }
                }
                Section("ฟีเจอร์") {
                    Toggle(isOn: $youtube) { row("play.rectangle.fill", .red, "YouTube จากเบราว์เซอร์") }
                    Toggle(isOn: $btBanner) { row("bell.badge.fill", .orange, "แจ้งเตือนเมื่อ Bluetooth หลุด") }
                    Toggle(isOn: $deviceIcons) { row("airpods", .indigo, "ไอคอนอุปกรณ์ในการ์ด") }
                }
                Section("ระบบ") {
                    Toggle(isOn: $launchAtLogin) { row("power", .green, "เปิดเองตอนเข้าเครื่อง") }
                        .onChange(of: launchAtLogin) { Pref.applyLaunchAtLogin() }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            HStack {
                Button("คืนค่าเริ่มต้น") { withAnimation { Pref.reset() }; Pref.applyLaunchAtLogin() }
                Spacer()
                Button("ปิด Lagoon", role: .destructive) { NSApp.terminate(nil) }
            }
            .controlSize(.large)
            .padding(.horizontal, 20).padding(.bottom, 18)
        }
        .frame(width: 440)
        .fixedSize()
    }

    /// Live preview of the compact island with the chosen wave color.
    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                RoundedRectangle(cornerRadius: 5).fill(.linearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 22, height: 22)
                    .overlay(Image(systemName: "music.note").font(.system(size: 11, weight: .bold)).foregroundStyle(.white))
                Spacer()
                Bars(playing: true, color: Pref.color(waveColor))
            }
            .padding(.horizontal, 12)
            .frame(width: 280, height: 38)
            .background(.black, in: Capsule())
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            .animation(.easeInOut(duration: 0.25), value: waveColor)
            Text("Lagoon").font(.title3.weight(.semibold))
            Text("เวอร์ชัน \(version)").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 26).padding(.bottom, 6)
        .background(LinearGradient(colors: [Pref.color(waveColor).opacity(0.18), .clear], startPoint: .top, endPoint: .bottom))
    }

    private var swatches: some View {
        HStack(spacing: 8) {
            ForEach(Pref.colors, id: \.id) { c in
                Button { withAnimation(.spring(duration: 0.25)) { waveColor = c.id } } label: {
                    Circle().fill(c.color).frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.black.opacity(0.15)))
                        .padding(3)
                        .overlay(Circle().strokeBorder(waveColor == c.id ? Color.primary : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .help(c.name)
                .accessibilityLabel(c.name)
                .accessibilityAddTraits(waveColor == c.id ? .isSelected : [])
            }
        }
    }

    /// System-Settings-style row: white symbol on a colored rounded square.
    private func row(_ icon: String, _ tint: Color, _ title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(tint.gradient, in: RoundedRectangle(cornerRadius: 6))
            Text(title)
        }
    }
}

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?
    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "ตั้งค่า Lagoon"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)  // only when the user asked for settings
        window?.makeKeyAndOrderFront(nil)
    }
}
