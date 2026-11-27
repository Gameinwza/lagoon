import SwiftUI

struct IslandView: View {
    @ObservedObject var np: NowPlaying
    var onResize: (CGSize) -> Void = { _ in }
    @State private var hover = false

    private var expanded: Bool { hover && np.track != nil }
    private var size: CGSize {
        if expanded { return CGSize(width: 380, height: 150) }
        return np.track == nil ? CGSize(width: 200, height: 32) : CGSize(width: 280, height: 32)
    }
    private var accent: Color { np.track?.app == "Spotify" ? .green : .pink }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(bottomLeadingRadius: expanded ? 32 : 14,
                                       bottomTrailingRadius: expanded ? 32 : 14)
                    .fill(.black)
                if let t = np.track {
                    if expanded { full(t).transition(.opacity) } else { compact(t).transition(.opacity) }
                }
            }
            .frame(width: size.width, height: size.height)
            .onHover { h in withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { hover = h } }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: np.track?.title)
        .onChange(of: size, initial: true) { _, s in onResize(s) }
    }

    private func art(_ s: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: s / 4)
            .fill(LinearGradient(colors: [accent, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: s, height: s)
            .overlay(Image(systemName: "music.note").font(.system(size: s * 0.45)).foregroundStyle(.white))
    }

    private func compact(_ t: Track) -> some View {
        HStack { art(20); Spacer(); Bars(playing: t.playing, color: accent) }
            .padding(.horizontal, 12).frame(height: 32)
    }

    private func full(_ t: Track) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                art(48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title).font(.headline).lineLimit(1)
                    Text(t.artist).font(.subheadline).foregroundStyle(.gray).lineLimit(1)
                }
                Spacer()
                Bars(playing: t.playing, color: accent)
            }
            TimelineView(.animation(paused: !t.playing)) { tl in
                let pos = t.position(at: tl.date)
                HStack(spacing: 8) {
                    Text(fmt(pos)).font(.caption2.monospacedDigit())
                    ProgressView(value: pos, total: max(t.duration, 1)).tint(.white)
                    Text(fmt(t.duration)).font(.caption2.monospacedDigit())
                }.foregroundStyle(.gray)
            }
            HStack(spacing: 36) {
                btn("backward.fill", "ก่อนหน้า") { np.send("previous track") }
                btn(t.playing ? "pause.fill" : "play.fill", "เล่น/หยุด") { np.send("playpause") }
                btn("forward.fill", "ถัดไป") { np.send("next track") }
            }
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
