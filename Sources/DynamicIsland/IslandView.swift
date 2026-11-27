import SwiftUI

struct IslandView: View {
    @ObservedObject var np: NowPlaying
    @ObservedObject var state: IslandState
    @ObservedObject var bt: BluetoothWatcher
    @ObservedObject var audio: OutputAudio
    @State private var showVol = false   // volume slider row inside the expanded card
    @AppStorage(Pref.waveColor) private var waveColor = "blue"
    @AppStorage(Pref.deviceIcons) private var showDevices = true
    @State private var showBT = false   // Bluetooth detail list inside the expanded card
    @State private var lastTrack: Track?  // kept while the island fades out after the music stops
    private var shown: Track? { np.track ?? lastTrack }
    private var hidden: Bool { np.track == nil && banner == nil }

    private var expanded: Bool { state.hover && np.track != nil }
    private var banner: BTEvent? { expanded ? nil : bt.event }
    private var size: CGSize {
        if expanded {
            var rows: CGFloat = showVol ? 50 : 0
            if showBT { rows += bt.devices.isEmpty ? 40 : bt.devices.reduce(CGFloat(14)) { $0 + ($1.battery != nil ? 96 : 26) } }
            return CGSize(width: 380, height: 118 + Notch.topInset + rows)
        }
        if banner != nil { return CGSize(width: 340, height: Notch.topInset + 40) }
        // Device icons only appear in the expanded card, not here.
        // On a notch the art and wave sit either side of the camera, so wider notches get a wider island.
        let compact = Notch.present ? max(280, Notch.width + 100) : 260
        return shown == nil ? CGSize(width: 200, height: 32) : CGSize(width: compact, height: 32)
    }
    private var accent: Color {
        if np.track?.isVideo == true { return .red }
        return np.track?.app == "Spotify" ? .green : .pink
    }

    var body: some View {
        let _ = state.screenChanges  // re-layout when displays change
        return island.contextMenu { Button("ตั้งค่า…") { SettingsWindow.show() } }
    }

    private var island: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Notch: square top that merges with the camera housing. No notch: a floating, fully rounded pill.
                let r: CGFloat = expanded ? 32 : banner != nil ? 22 : Notch.present ? 14 : 16
                let top: CGFloat = Notch.present ? 0 : r
                UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: r, bottomTrailingRadius: r, topTrailingRadius: top)
                    .fill(.black)
                if let e = banner {
                    btBanner(e).transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else if let t = shown {
                    if expanded {
                        full(t).transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                    } else {
                        compact(t).transition(.opacity)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .shadow(color: .black.opacity(Notch.present ? 0 : 0.3), radius: 10, y: 4)
            .padding(.top, Notch.present ? 0 : Notch.floatGap)
            // Music closed (or paused > 5 min): shrink slightly and fade out, keeping the last song on
            // screen while it goes so nothing pops.
            .opacity(hidden ? 0 : 1)
            .scaleEffect(hidden ? 0.92 : 1, anchor: .top)
            .animation(.easeInOut(duration: 0.8), value: hidden)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: np.track?.title)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: bt.event)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: bt.devices)
        .onChange(of: size, initial: true) { _, s in state.size = s }
        .onChange(of: expanded) { _, e in if !e { showBT = false; showVol = false } }
        .onChange(of: np.track) { _, t in
            if let t { lastTrack = t; return }
            // Forget the old song once the fade-out has finished (unless something started meanwhile).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { if np.track == nil { lastTrack = nil } }
        }
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
            if bt.devices.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "hifispeaker.fill").frame(width: 18)
                    Text(audio.deviceName).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Spacer()
                    Text("ลำโพงที่ใช้อยู่").font(.system(size: 12)).foregroundStyle(.gray)
                }
            }
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
        .padding(.top, Notch.topInset)  // drop the row below the notch
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
        HStack { art(20); Spacer(); Bars(playing: t.playing, color: Pref.color(waveColor)) }
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
                .buttonStyle(LiftStyle())
                .accessibilityLabel("เปิด \(t.title) ใน \(t.app)")
                Spacer()
                Bars(playing: t.playing, color: Pref.color(waveColor))
                Button { SettingsWindow.show() } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 13)).foregroundStyle(.gray)
                        .frame(width: 26, height: 26).contentShape(Circle())
                }
                .buttonStyle(PressStyle()).help("ตั้งค่า Lagoon").accessibilityLabel("ตั้งค่า Lagoon")
                .onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
            }
            if t.duration > 0 { TimelineView(.animation(paused: !t.playing)) { tl in
                let pos = t.position(at: tl.date)
                HStack(spacing: 8) {
                    Text(fmt(pos)).font(.caption2.monospacedDigit())
                    Scrubber(position: pos, duration: t.duration) { np.send(.seek($0)) }
                    Text(fmt(t.duration)).font(.caption2.monospacedDigit())
                }.foregroundStyle(.gray)
            } }
            HStack(spacing: 36) {
                btn("backward.fill", "ก่อนหน้า") { np.send(.previous) }
                btn(t.playing ? "pause.fill" : "play.fill", "เล่น/หยุด") { np.send(.playPause) }
                btn("forward.fill", "ถัดไป") { np.send(.next) }
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                Button { withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { showVol.toggle(); showBT = false } } label: {
                    Image(systemName: audio.icon).font(.system(size: 14)).contentTransition(.symbolEffect(.replace))
                        .frame(width: 40, height: 32)
                        .background(showVol ? Color.white.opacity(0.15) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ระดับเสียง \(Int(audio.volume * 100))%")
                .onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
                .offset(x: -12)
            }
            .overlay(alignment: .trailing) {
                if showDevices {
                    Button { withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { showBT.toggle(); showVol = false } } label: {
                        Group {
                            if bt.devices.isEmpty { Image(systemName: "hifispeaker.fill").font(.system(size: 14)) } else { deviceIcons }
                        }
                        .padding(.horizontal, 8).frame(minHeight: 32)
                            .background(showBT ? Color.white.opacity(0.15) : .clear, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showBT ? "ซ่อนข้อมูล Bluetooth" : "ดูข้อมูล Bluetooth")
                    .onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
                    .offset(x: 12)  // a bit more breathing room from the Next button
                }
            }
            if showVol { volumeRow.transition(.opacity) }
            if showBT { btList.transition(.opacity) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22).padding(.top, Notch.topInset + 4).padding(.bottom, 14)
    }

    /// Mute toggle + live volume slider for the current output device.
    private var volumeRow: some View {
        VStack(spacing: 8) {
            Divider().overlay(Color.white.opacity(0.15))
            HStack(spacing: 10) {
                Button { audio.toggleMute() } label: {
                    Image(systemName: audio.muted ? "speaker.slash.fill" : "speaker.fill").font(.system(size: 13))
                        .contentTransition(.symbolEffect(.replace)).frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle()).accessibilityLabel(audio.muted ? "เปิดเสียง" : "ปิดเสียง")
                Slider(value: Binding(get: { Double(audio.muted ? 0 : audio.volume) }, set: { audio.setVolume(Float($0)) }))
                    .controlSize(.small).tint(.white).disabled(!audio.canSetVolume)
                    .accessibilityLabel("ระดับเสียง")
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 13)).foregroundStyle(.gray)
            }
        }
    }

    private func btn(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3)
                .contentTransition(.symbolEffect(.replace))  // play ↔ pause morphs instead of popping
                .frame(width: 44, height: 32)
        }
        .buttonStyle(PressStyle()).accessibilityLabel(label)
    }

    private func fmt(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}

struct Bars: View {
    var playing: Bool
    var color: Color
    @State private var changedAt = Date.distantPast
    @State private var settled = true   // true once the pause fade is over → stop redrawing

    /// 0…1 wave height: eases in over 0.3 s on play and fades out over 0.6 s on pause.
    private func amp(_ t: Date) -> Double {
        let dt = t.timeIntervalSince(changedAt)
        return playing ? min(1, dt / 0.3) : max(0, 1 - dt / 0.6)
    }

    var body: some View {
        TimelineView(.animation(paused: !playing && settled)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate, a = amp(tl.date)
            HStack(spacing: 2) {
                ForEach(0..<4) { i in
                    Capsule().fill(color)
                        .frame(width: 3, height: 4 + 10 * a * abs(sin(t * 4 + Double(i))))
                }
            }.frame(height: 16)
        }
        .onChange(of: playing) {
            changedAt = Date()
            settled = false
            if !playing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { if !playing { settled = true } }
            }
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

/// Shrinks and dims while pressed, with a hover highlight, all animated.
struct PressStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(.white.opacity(hover ? 0.12 : 0)).frame(width: 40, height: 40))
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hover)
            .onHover { hover = $0; $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
            .contentShape(Rectangle())
    }
}

/// Seek bar: thickens and shows a knob on hover; click or drag to jump.
struct Scrubber: View {
    var position: Double
    var duration: Double
    var onSeek: (Double) -> Void
    @State private var hover = false
    @State private var drag: Double?   // 0…1 while dragging

    var body: some View {
        GeometryReader { g in
            let f = drag ?? (duration > 0 ? min(1, position / duration) : 0)
            let active = hover || drag != nil
            // Apple-style: no knob, the bar just gets a little thicker and brighter under the pointer.
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(active ? 0.25 : 0.18))
                Capsule().fill(.white.opacity(active ? 1 : 0.85)).frame(width: max(0, g.size.width * f))
            }
            .frame(height: active ? 8 : 5)
            .clipShape(Capsule())
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag = min(1, max(0, $0.location.x / g.size.width)) }
                .onEnded { _ in
                    if let d = drag { onSeek(d * duration) }
                    drag = nil
                })
            .onHover { hover = $0; $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: active)
        }
        .frame(height: 16)
        .accessibilityElement()
        .accessibilityLabel("ตำแหน่งเพลง")
        .accessibilityValue("\(Int(position) / 60):\(String(format: "%02d", Int(position) % 60))")
        .accessibilityAdjustableAction { dir in
            onSeek(min(duration, max(0, position + (dir == .increment ? 10 : -10))))
        }
    }
}

/// Grows a little under the pointer (and dips when pressed) so it reads as clickable.
struct LiftStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : hover ? 1.06 : 1, anchor: .leading)
            .brightness(hover ? 0.08 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
            .onHover { hover = $0; $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
    }
}

/// Geometry of the screen the island lives on. Notched MacBooks: the island hugs the camera housing.
/// Other screens (external monitors, Macs without a notch): a floating pill just below the top edge.
@MainActor enum Notch {
    static var screen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }
    static var present: Bool { screen.safeAreaInsets.top > 0 }
    /// Camera housing width, from the menu-bar areas either side of it (0 without a notch).
    static var width: CGFloat {
        guard present, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea else { return 0 }
        return screen.frame.width - l.width - r.width
    }
    /// Content must start below this or the camera covers it.
    static var topInset: CGFloat { present ? screen.safeAreaInsets.top : 10 }
    static let floatGap: CGFloat = 6
}
