import SwiftUI

struct IslandView: View {
    @ObservedObject var np: NowPlaying
    @ObservedObject var state: IslandState
    @ObservedObject var bt: BluetoothWatcher
    @State private var showBT = false   // Bluetooth detail list inside the expanded card

    private var expanded: Bool { state.hover && np.track != nil }
    private var banner: BTEvent? { expanded ? nil : bt.event }
    private var size: CGSize {
        if expanded {
            let rows = showBT ? bt.devices.reduce(CGFloat(14)) { $0 + ($1.battery != nil ? 96 : 26) } : 0
            return CGSize(width: 380, height: 150 + rows)
        }
        if banner != nil { return CGSize(width: 340, height: Self.notch + 40) }
        // Device icons only appear in the expanded card, not here.
        return np.track == nil ? CGSize(width: 200, height: 32) : CGSize(width: 280, height: 32)
    }
    private var accent: Color {
        if np.track?.isVideo == true { return .red }
        return np.track?.app == "Spotify" ? .green : .pink
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(bottomLeadingRadius: expanded ? 32 : banner != nil ? 22 : 14,
                                       bottomTrailingRadius: expanded ? 32 : banner != nil ? 22 : 14)
                    .fill(.black)
                if let e = banner {
                    btBanner(e).transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else if let t = np.track {
                    if expanded {
                        full(t).transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                    } else {
                        compact(t).transition(.opacity)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: np.track?.title)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: bt.event)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: bt.devices)
        .onChange(of: size, initial: true) { _, s in state.size = s }
        .onChange(of: expanded) { _, e in if !e { showBT = false } }
    }

    /// Small icons for every connected Bluetooth device (hover shows the name).
    private var deviceIcons: some View {
        HStack(spacing: 6) {
            ForEach(bt.devices, id: \.self) { d in
                HStack(spacing: 3) {
                    Image(systemName: d.icon).font(.system(size: 12, weight: .medium))
                    if let n = d.battery?.headline {
                        Text("\(n)%").font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(n <= 20 ? .red : .white.opacity(0.85))
                    }
                }
                .foregroundStyle(.white.opacity(0.85))
                .help(d.battery.map { "\(d.name) — \($0.detail)" } ?? d.name)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(d.battery.map { "\(d.name) \($0.detail)" } ?? d.name)
            }
        }
    }

    /// Expanded-card list: every connected device with its full battery breakdown.
    private var btList: some View {
        VStack(spacing: 8) {
            Divider().overlay(Color.white.opacity(0.15))
            ForEach(bt.devices, id: \.self) { d in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: d.icon).frame(width: 18)
                        Text(d.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Spacer()
                        if d.battery == nil { Text("เชื่อมต่ออยู่").font(.system(size: 12)).foregroundStyle(.gray) }
                    }
                    if let b = d.battery {
                        HStack(spacing: 18) {
                            if let v = b.left { BatteryRing(level: v, icon: "airpod.left", label: "ซ้าย") }
                            if let v = b.right { BatteryRing(level: v, icon: "airpod.right", label: "ขวา") }
                            if let v = b.case_ { BatteryRing(level: v, icon: "airpods.chargingcase", label: "กล่อง") }
                            if let v = b.main { BatteryRing(level: v, icon: d.icon, label: "แบต") }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    /// Height of the camera notch; content must sit below it or the hardware covers it.
    static let notch: CGFloat = NSScreen.screens.map(\.safeAreaInsets.top).max().flatMap { $0 > 0 ? $0 : nil } ?? 32

    private func btBanner(_ e: BTEvent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: e.icon).font(.system(size: 15, weight: .semibold))
            Text(e.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Spacer()
            Text(e.connected ? "เชื่อมต่อแล้ว" : "ตัดการเชื่อมต่อ").font(.system(size: 12, weight: .medium))
                .foregroundStyle(e.connected ? Color.green : Color.orange)  // gray was unreadable on black
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18).frame(height: 40)
        .padding(.top, Self.notch)  // drop the row below the notch
        .accessibilityElement(children: .combine)
    }

    private func art(_ s: CGFloat) -> some View {
        ZStack {
            if let img = np.art {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [accent, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: np.track?.isVideo == true ? "play.rectangle.fill" : "music.note").font(.system(size: s * 0.45)).foregroundStyle(.white)
            }
        }
        .frame(width: s, height: s)
        .clipShape(RoundedRectangle(cornerRadius: s / 4))
        .animation(.easeInOut(duration: 0.25), value: np.art)
    }

    private func compact(_ t: Track) -> some View {
        HStack { art(20); Spacer(); Bars(playing: t.playing, color: accent) }
            .padding(.horizontal, 12).frame(height: 32)
    }

    private func full(_ t: Track) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button { np.openInApp() } label: {
                    HStack(spacing: 12) {
                        art(48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title).font(.headline).lineLimit(1)
                            Text(t.artist).font(.subheadline).foregroundStyle(.gray).lineLimit(1)
                        }
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("เปิด \(t.title) ใน \(t.app)")
                .onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
                Spacer()
                Bars(playing: t.playing, color: accent)
            }
            if t.duration > 0 { TimelineView(.animation(paused: !t.playing)) { tl in
                let pos = t.position(at: tl.date)
                HStack(spacing: 8) {
                    Text(fmt(pos)).font(.caption2.monospacedDigit())
                    ProgressView(value: pos, total: max(t.duration, 1)).tint(.white)
                    Text(fmt(t.duration)).font(.caption2.monospacedDigit())
                }.foregroundStyle(.gray)
            } }
            HStack(spacing: 36) {
                btn("backward.fill", "ก่อนหน้า") { np.send(.previous) }
                btn(t.playing ? "pause.fill" : "play.fill", "เล่น/หยุด") { np.send(.playPause) }
                btn("forward.fill", "ถัดไป") { np.send(.next) }
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                if !bt.devices.isEmpty {
                    Button { withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { showBT.toggle() } } label: {
                        deviceIcons.padding(.horizontal, 8).frame(minHeight: 32)
                            .background(showBT ? Color.white.opacity(0.15) : .clear, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showBT ? "ซ่อนข้อมูล Bluetooth" : "ดูข้อมูล Bluetooth")
                    .offset(x: 12)  // a bit more breathing room from the Next button
                }
            }
            if showBT { btList.transition(.opacity) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22).padding(.top, 36).padding(.bottom, 14)
    }

    private func btn(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.title3).frame(width: 44, height: 32) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }

    private func fmt(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}

struct Bars: View {
    var playing: Bool
    var color: Color
    var body: some View {
        TimelineView(.animation(paused: !playing)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<4) { i in
                    Capsule().fill(color)
                        .frame(width: 3, height: playing ? 4 + 10 * abs(sin(t * 4 + Double(i))) : 4)
                }
            }.frame(height: 16)
        }
    }
}

/// Circular battery gauge: gray track, green arc (red at 20% or less), device glyph in the middle.
struct BatteryRing: View {
    var level: Int
    var icon: String
    var label: String

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 4)
                Circle().trim(from: 0, to: CGFloat(level) / 100)
                    .stroke(level <= 20 ? Color.red : Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: icon).font(.system(size: 14, weight: .medium))
            }
            .frame(width: 44, height: 44)
            Text("\(level)%").font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(level)%")
    }
}
