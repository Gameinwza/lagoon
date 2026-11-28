import SwiftUI
import ServiceManagement

/// User preferences. Every key has a default, so the app works with zero setup.
enum Pref {
    static let waveColor = "waveColor", youtube = "youtube", btBanner = "btBanner",
               deviceIcons = "deviceIcons", hideAfter = "hideAfter", launchAtLogin = "launchAtLogin",
               autoUpdate = "autoUpdate", timers = "timers"

    static let defaults: [String: Any] = [
        waveColor: "blue", youtube: true, btBanner: true, deviceIcons: true, hideAfter: 3.0, launchAtLogin: true, autoUpdate: true, timers: true,
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
    @AppStorage(Pref.timers) private var timers = true
    @ObservedObject private var updater = Updater.shared
    @ObservedObject private var reminders = Reminders.shared
    @State private var note = ""
    @State private var remindAt = Date.now.addingTimeInterval(3600)

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    var body: some View {
        GeometryReader { geo in
            // Wide (big window / full screen): stage on the left, settings on the right.
            if geo.size.width >= 760 {
                HStack(spacing: 0) {
                    hero.frame(width: min(max(geo.size.width * 0.46, 380), 720))
                    form.frame(maxWidth: 620).frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    hero.frame(height: 300)
                    form
                }
            }
        }
        .frame(minWidth: 440, minHeight: 480)
    }

    /// Stage: a small Mac screen floating in a glow of the wave color, with the title underneath.
    private var hero: some View {
        GeometryReader { g in
            // Screen keeps a 16:10 shape and leaves room for the window buttons above and the title below.
            let w = min(g.size.width - 64, (g.size.height - 190) * 1.6)
            VStack(spacing: 18) {
                PreviewScreen(mode: preview, timerEnd: reminders.next?.fireAt, wave: Pref.color(waveColor), showDevices: deviceIcons, scale: w / 420)
                    .frame(width: w, height: w / 1.6)
                Picker("ตัวอย่าง", selection: $preview.animation(.spring(response: 0.42, dampingFraction: 0.78))) {
                    Text("ย่อ").tag(PreviewMode.compact); Text("ขยาย").tag(PreviewMode.expanded)
                    if timers { Text("ตั้งเวลา").tag(PreviewMode.timer); Text("เตือน").tag(PreviewMode.alert) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                titleRow.frame(width: w)
            }
            .padding(.top, 20)  // clear of the traffic lights
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            ZStack {
                Color(red: 0.04, green: 0.05, blue: 0.1)
                RadialGradient(colors: [Pref.color(waveColor).opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 380)
            }
            .animation(.easeInOut(duration: 0.4), value: waveColor)
        }
        .environment(\.colorScheme, .dark)
        .clipped()
        .ignoresSafeArea()  // the stage runs up under the transparent title bar
    }

    private var form: some View {
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
                Section("ตั้งเวลา") {
                    Toggle(isOn: $timers) { row("timer", .orange, "ตั้งเวลาแจ้งเตือน") }
                        .onChange(of: timers) {
                            reminders.applyEnabled()
                            showPreview(timers ? .timer : .expanded)  // show what the feature looks like
                        }
                    if timers {
                        LabeledContent {
                            TextField("ชื่องาน", text: $note, prompt: Text("ไม่ใส่ก็ได้")).labelsHidden()
                                .multilineTextAlignment(.trailing).frame(maxWidth: 200)
                        } label: { row("pencil", .gray, "ชื่องาน") }
                        LabeledContent {
                            HStack(spacing: 6) {
                                ForEach(Reminders.presets, id: \.self) { m in
                                    Button("\(m)") { reminders.start(minutes: m, label: note); note = ""; showPreview(.timer) }
                                        .accessibilityLabel("\(m) นาที")
                                }
                                Text("นาที").foregroundStyle(.secondary)
                            }
                        } label: { row("hourglass", .yellow, "นับถอยหลัง") }
                        LabeledContent {
                            HStack(spacing: 6) {
                                DatePicker("เวลา", selection: $remindAt, displayedComponents: .hourAndMinute).labelsHidden()
                                Button("เพิ่ม") { addReminder() }
                            }
                        } label: { row("bell.fill", .pink, "เตือนตามเวลา") }
                        ForEach(reminders.sorted) { r in
                            LabeledContent {
                                HStack(spacing: 8) {
                                    TimelineView(.periodic(from: .now, by: 1)) { tl in
                                        Text("อีก " + Reminders.format(r.fireAt.timeIntervalSince(tl.date)))
                                            .monospacedDigit().foregroundStyle(.secondary)
                                    }
                                    Button("ยกเลิก") { reminders.cancel(r) }
                                }
                            } label: {
                                Text("\(r.label) · \(r.fireAt.formatted(date: .omitted, time: .shortened))").padding(.leading, 34)
                            }
                        }
                    }
                }
                Section("ระบบ") {
                    Toggle(isOn: $launchAtLogin) { row("power", .green, "เปิดเองตอนเข้าเครื่อง") }
                        .onChange(of: launchAtLogin) { Pref.applyLaunchAtLogin() }
                    Toggle(isOn: $autoUpdate) { row("arrow.triangle.2.circlepath", .teal, "ตรวจหาอัปเดตอัตโนมัติ") }
                        .onChange(of: autoUpdate) { updater.applyAutoCheck() }
                    LabeledContent { updateControl } label: { row("arrow.down.circle.fill", .blue, "อัปเดต") }
                }
                Section {
                    HStack {
                        Button("คืนค่าเริ่มต้น") { withAnimation { Pref.reset() }; Pref.applyLaunchAtLogin(); updater.applyAutoCheck(); reminders.applyEnabled() }
                        Spacer()
                        Button("ปิด Lagoon", role: .destructive) { NSApp.terminate(nil) }
                    }
                    .buttonStyle(.borderless)
                }
            }
            .formStyle(.grouped)
    }

    @State private var preview = PreviewMode.expanded

    private func addReminder() { reminders.remind(note, at: remindAt); note = ""; showPreview(.timer) }
    private func showPreview(_ m: PreviewMode) { withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { preview = m } }

    /// App name, version and the compact/expanded switch for the live preview.
    private var titleRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Lagoon").font(.system(size: 22, weight: .bold, design: .rounded))
                if let v = updater.available {
                    Text("เวอร์ชัน \(version) · มีเวอร์ชันใหม่ \(v)").font(.caption.weight(.medium)).foregroundStyle(.cyan)
                } else {
                    Text("เวอร์ชัน \(version)").font(.caption).foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer()
        }
        .foregroundStyle(.white)
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
            let hc = NSHostingController(rootView: SettingsView())
            hc.sizingOptions = [.minSize]  // window is resizable; SwiftUI only sets the minimum
            let w = NSWindow(contentViewController: hc)
            w.title = "ตั้งค่า Lagoon"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.collectionBehavior.insert(.fullScreenPrimary)  // green button goes full screen
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            // First open: wide enough for two columns, short enough for a 13" screen.
            let vis = (NSScreen.main?.visibleFrame.size) ?? NSSize(width: 1440, height: 900)
            w.setContentSize(NSSize(width: min(820, vis.width - 80), height: min(560, vis.height - 80)))
            w.center()
            w.setFrameAutosaveName("LagoonSettings")  // remember size/position after the user changes it
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)  // only when the user asked for settings
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Sample of the island on a tiny Mac screen, so settings changes are visible before music plays.
enum PreviewMode: Hashable { case compact, expanded, timer, alert }

private struct PreviewScreen: View {
    var mode: PreviewMode
    var timerEnd: Date?  // live countdown when a timer is running, else a sample
    var wave: Color
    var showDevices: Bool
    var scale: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.03, green: 0.06, blue: 0.14)
            RadialGradient(colors: [wave.opacity(0.5), .clear], center: .top, startRadius: 0, endRadius: 260 * scale)
            RadialGradient(colors: [Color(red: 0.1, green: 0.75, blue: 0.75).opacity(0.45), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 300 * scale)
            RadialGradient(colors: [Color(red: 0.35, green: 0.2, blue: 0.8).opacity(0.35), .clear],
                           center: .bottomLeading, startRadius: 0, endRadius: 260 * scale)
            // Menu bar with a few placeholder items either side of the notch.
            HStack(spacing: 8) {
                Image(systemName: "apple.logo").font(.system(size: 9))
                ForEach([22, 30, 18], id: \.self) { w in Capsule().frame(width: CGFloat(w), height: 4) }
                Spacer()
                ForEach([14, 14, 34], id: \.self) { w in Capsule().frame(width: CGFloat(w), height: 4) }
            }
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 12).frame(height: 18)
            .frame(width: 420)  // the screen is 420 pt wide before scaling
            .background(.black.opacity(0.25))
            .scaleEffect(scale, anchor: .top)
            .frame(width: 420 * scale, height: 18 * scale, alignment: .top)  // layout at the scaled size
            island
                .shadow(color: wave.opacity(0.45), radius: 18, y: 6)
                .scaleEffect(scale, anchor: .top)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14 * scale))
        .overlay(RoundedRectangle(cornerRadius: 14 * scale).strokeBorder(.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
        .shadow(color: wave.opacity(0.25), radius: 40)
        .animation(.easeInOut(duration: 0.4), value: wave)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ตัวอย่างเกาะ")
    }

    private var island: some View {
        let (w, h, r): (CGFloat, CGFloat, CGFloat) = switch mode {
            case .expanded: (250, 96, 22)
            case .alert: (230, 34, 16)
            case .compact, .timer: (170, 22, 10)
        }
        return ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: r, bottomTrailingRadius: r).fill(.black)
            switch mode {
            case .expanded: card.transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            case .compact: compact.transition(.opacity)
            case .timer: timer.transition(.opacity)
            case .alert: alert.transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(width: w, height: h)
    }

    private var timer: some View {
        HStack {
            Image(systemName: "timer").font(.system(size: 9, weight: .bold))
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { tl in
                Text(timerEnd.map { Reminders.format($0.timeIntervalSince(tl.date)) } ?? "25:00")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
            }
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 9).frame(height: 22)
    }

    private var alert: some View {
        HStack(spacing: 6) {
            Image(systemName: "bell.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.orange)
                .symbolEffect(.bounce, options: .repeat(2), value: mode)
            Text("ถึงเวลาแล้ว").font(.system(size: 10, weight: .semibold))
            Spacer()
            Text("ปิด").font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 7).padding(.vertical, 2).background(.white.opacity(0.15), in: Capsule())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.top, 10)  // below the notch, like the real banner
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
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 12)
    }
}
