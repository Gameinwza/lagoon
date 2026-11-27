import SwiftUI
import ServiceManagement

/// User preferences. Every key has a default, so the app works with zero setup.
enum Pref {
    static let waveColor = "waveColor", youtube = "youtube", btBanner = "btBanner",
               deviceIcons = "deviceIcons", hideAfter = "hideAfter", launchAtLogin = "launchAtLogin",
               autoUpdate = "autoUpdate"

    static let defaults: [String: Any] = [
        waveColor: "blue", youtube: true, btBanner: true, deviceIcons: true, hideAfter: 3.0, launchAtLogin: true, autoUpdate: true,
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
    @AppStorage(Pref.autoUpdate) private var autoUpdate = true
    @ObservedObject private var updater = Updater.shared

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
                    Toggle(isOn: $autoUpdate) { row("arrow.triangle.2.circlepath", .teal, "ตรวจหาอัปเดตอัตโนมัติ") }
                        .onChange(of: autoUpdate) { updater.applyAutoCheck() }
                    LabeledContent { updateControl } label: { row("arrow.down.circle.fill", .blue, "อัปเดต") }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            HStack {
                Button("คืนค่าเริ่มต้น") { withAnimation { Pref.reset() }; Pref.applyLaunchAtLogin(); updater.applyAutoCheck() }
                Spacer()
                Button("ปิด Lagoon", role: .destructive) { NSApp.terminate(nil) }
            }
            .controlSize(.large)
            .padding(.horizontal, 20).padding(.bottom, 18)
        }
        .frame(width: 440)
        .fixedSize()
    }

    @State private var previewExpanded = true

    /// Title row plus a live sample: a miniature Mac screen with the island at its notch.
    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Lagoon").font(.headline)
                    if let v = updater.available {
                        Text("เวอร์ชัน \(version) · มีเวอร์ชันใหม่ \(v)").font(.caption).foregroundStyle(.blue)
                    } else {
                        Text("เวอร์ชัน \(version)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Picker("ตัวอย่าง", selection: $previewExpanded.animation(.spring(response: 0.42, dampingFraction: 0.78))) {
                    Text("ย่อ").tag(false); Text("ขยาย").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            PreviewScreen(expanded: previewExpanded, wave: Pref.color(waveColor), showDevices: deviceIcons)
        }
        .padding(.horizontal, 20).padding(.top, 34)
    }

    /// One control that walks through check → available → installing, with error and up-to-date states.
    @ViewBuilder private var updateControl: some View {
        switch updater.phase {
        case .idle:
            Button("ตรวจหาเลย") { updater.check() }
        case .checking:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("กำลังตรวจ…").foregroundStyle(.secondary) }
        case .upToDate:
            HStack(spacing: 8) {
                Text("ล่าสุดแล้ว").foregroundStyle(.secondary)
                Button("ตรวจอีกครั้ง") { updater.check() }
            }
        case .available(let v, _):
            Button("อัปเดตเป็น \(v)") { updater.install() }.buttonStyle(.borderedProminent)
        case .installing:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("กำลังติดตั้ง…").foregroundStyle(.secondary) }
        case .failed(let msg):
            HStack(spacing: 8) {
                Text(msg).foregroundStyle(.red).lineLimit(2).multilineTextAlignment(.trailing).frame(maxWidth: 200, alignment: .trailing)
                Button("ลองใหม่") { updater.check() }
            }
        }
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
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
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

/// Sample of the island on a tiny Mac screen, so settings changes are visible before music plays.
private struct PreviewScreen: View {
    var expanded: Bool
    var wave: Color
    var showDevices: Bool

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.05, green: 0.2, blue: 0.4), Color(red: 0.1, green: 0.55, blue: 0.7),
                                    Color(red: 0.45, green: 0.85, blue: 0.8)], startPoint: .top, endPoint: .bottom)
            // Menu bar with a few placeholder items either side of the notch.
            HStack(spacing: 8) {
                Image(systemName: "apple.logo").font(.system(size: 9))
                ForEach([22, 30, 18], id: \.self) { w in Capsule().frame(width: CGFloat(w), height: 4) }
                Spacer()
                ForEach([14, 14, 34], id: \.self) { w in Capsule().frame(width: CGFloat(w), height: 4) }
            }
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 12).frame(height: 18)
            .background(.black.opacity(0.25))
            island
        }
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ตัวอย่างเกาะ")
    }

    private var island: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: expanded ? 22 : 10, bottomTrailingRadius: expanded ? 22 : 10).fill(.black)
            if expanded { card.transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top))) }
            else { compact.transition(.opacity) }
        }
        .frame(width: expanded ? 250 : 170, height: expanded ? 112 : 22)
    }

    private var art: some View {
        RoundedRectangle(cornerRadius: 4).fill(.linearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Image(systemName: "music.note").font(.system(size: 7, weight: .bold)).foregroundStyle(.white))
    }

    private var compact: some View {
        HStack { art.frame(width: 14, height: 14); Spacer(); Bars(playing: true, color: wave).scaleEffect(0.75) }
            .padding(.horizontal, 9).frame(height: 22)
    }

    private var card: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                art.frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ocean Drive").font(.system(size: 11, weight: .semibold))
                    Text("Sample Artist").font(.system(size: 9)).foregroundStyle(.gray)
                }
                Spacer()
                Bars(playing: true, color: wave).scaleEffect(0.8)
            }
            HStack(spacing: 0) {
                Capsule().fill(.white.opacity(0.9)).frame(width: 80, height: 3)
                Capsule().fill(.white.opacity(0.25)).frame(height: 3)
            }
            HStack {
                Image(systemName: "gearshape.fill").foregroundStyle(.gray)
                Spacer()
                HStack(spacing: 22) { Image(systemName: "backward.fill"); Image(systemName: "pause.fill"); Image(systemName: "forward.fill") }
                Spacer()
                Image(systemName: showDevices ? "airpods" : "speaker.wave.2.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            .font(.system(size: 11))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
    }
}
