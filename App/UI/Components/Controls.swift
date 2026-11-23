import SwiftUI
import AVKit
import MediaPlayer

/// 44 pt square icon button with 14 pt radius (boards: header, Now Playing).
struct IconButton: View {
    let icon: Icon
    let label: String
    var size: CGFloat = 44
    var iconSize: CGFloat = 19
    var background: Color = NC.surface
    var foreground: Color = NC.text
    var radius: CGFloat = Radius.iconButton
    var lineWidth: CGFloat = 2
    var filled = false
    var haptic = false
    let action: () -> Void

    var body: some View {
        Button {
            if haptic { Haptics.tap() }
            action()
        } label: {
            IconView(icon: icon, size: iconSize, lineWidth: lineWidth, filled: filled)
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(background, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }
}

/// Slight press feedback for custom buttons.
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Primary gradient button (#1E40AF → #3B0764, 135°). Text never has a fixed width.
struct GradientButton: View {
    let title: String
    var height: CGFloat = 44
    var radius: CGFloat = Radius.iconButton
    var fontSize: CGFloat = 14
    var icon: Icon?
    var expand = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { IconView(icon: icon, size: 17) }
                Text(title)
                    .font(.manrope(fontSize, .bold, relativeTo: .callout))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(NC.text)
            .padding(.horizontal, 16)
            .frame(maxWidth: expand ? .infinity : nil, minHeight: height)
            .background(NC.primary, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
    }
}

/// Round white play / pause button (mini-player 44, Now Playing 78 with purple glow).
struct PlayPauseButton: View {
    let isPlaying: Bool
    var size: CGFloat = 44
    var iconSize: CGFloat = 16
    var glow = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            ZStack {
                Circle().fill(NC.text)
                IconView(icon: isPlaying ? .pause : .play, size: iconSize, lineWidth: 0)
                    .foregroundStyle(NC.playIcon)
                    .offset(x: isPlaying ? 0 : iconSize * 0.06)
            }
            .frame(width: size, height: size)
            .shadow(color: glow ? NC.glow : .clear, radius: glow ? 22 : 0)
            .shadow(color: glow ? NC.bg.opacity(0.5) : .clear, radius: glow ? 15 : 0, y: glow ? 10 : 0)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(L10n.t(isPlaying ? "cd_pause" : "cd_play"))
    }
}

/// Amber equalizer bars for the current track (animated while playing, static when paused).
struct EqualizerBars: View {
    let playing: Bool
    var color: Color = NC.amber
    var bars = 4
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 3
    var height: CGFloat = 16

    private let rest: [CGFloat] = [0.62, 1.0, 0.75, 0.5, 0.86]

    var body: some View {
        if playing {
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { ctx in
                bar(time: ctx.date.timeIntervalSinceReferenceDate)
            }
        } else {
            bar(time: nil)
        }
    }

    private func level(_ i: Int, time: Double?) -> CGFloat {
        guard let t = time else { return rest[i % rest.count] * 0.7 }
        let phase: Double = t * (5.2 + Double(i) * 1.7) + Double(i) * 1.3
        let v: Double = (sin(phase) + 1) / 2
        return CGFloat(0.35 + 0.65 * v)
    }

    private func barHeight(_ i: Int, time: Double?) -> CGFloat {
        let h: CGFloat = height * level(i, time: time)
        return max(barWidth, h)
    }

    private func bar(time: Double?) -> some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(0..<bars, id: \.self) { (i: Int) in
                Capsule()
                    .fill(color)
                    .frame(width: barWidth, height: barHeight(i, time: time))
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// Thin progress line (mini-player 3 pt, bright gradient on #2A2A48).
struct ThinProgress: View {
    let fraction: Double
    var height: CGFloat = 3
    var track: Color = NC.progressTrack

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(NC.brightHorizontal)
                    .frame(width: max(0, geo.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Now Playing seek bar: 6 pt track, white fill, 16 pt white thumb with a halo; drag to seek.
struct SeekBar: View {
    @ObservedObject var clock: PlaybackClock
    let onSeek: (Double) -> Void
    @State private var dragFraction: Double?

    var body: some View {
        let fraction = dragFraction ?? clock.fraction
        VStack(spacing: 8) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(NC.text.opacity(0.2)).frame(height: 6)
                    Capsule().fill(NC.text).frame(width: max(6, w * fraction), height: 6)
                    Circle()
                        .fill(NC.text)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(NC.text.opacity(0.18)).frame(width: 26, height: 26))
                        .scaleEffect(dragFraction != nil ? 1.2 : 1)
                        .offset(x: w * fraction - 8)
                }
                .frame(height: 26)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in dragFraction = Double(min(max(0, v.location.x / max(w, 1)), 1)) }
                        .onEnded { v in
                            let f = Double(min(max(0, v.location.x / max(w, 1)), 1))
                            onSeek(f * clock.duration)
                            dragFraction = nil
                        }
                )
            }
            .frame(height: 26)
            HStack {
                Text(Fmt.clock((dragFraction.map { $0 * clock.duration }) ?? clock.position))
                Spacer()
                Text(Fmt.clock(clock.duration))
            }
            .font(.manrope(13, .semibold, relativeTo: .footnote))
            .monospacedDigit()
            .foregroundStyle(NC.onGradient)
            .padding(.top, -6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("now_playing"))
        .accessibilityValue("\(Fmt.clock(clock.position)) / \(Fmt.clock(clock.duration))")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: onSeek(min(clock.duration, clock.position + 10))
            case .decrement: onSeek(max(0, clock.position - 10))
            @unknown default: break
            }
        }
    }
}

// MARK: - System volume (MPVolumeView-backed, styled like the board)

final class SystemVolume: ObservableObject {
    static let shared = SystemVolume()

    @Published var value: Float = AVAudioSession.sharedInstance().outputVolume
    /// The on-screen (hidden) MPVolumeView; its UISlider is looked up when needed, because iOS
    /// builds the slider lazily after the view is in a window.
    fileprivate weak var volumeView: MPVolumeView?
    private var observation: NSKeyValueObservation?

    private init() {
        // outputVolume is only reported while the audio session is active.
        try? AVAudioSession.sharedInstance().setActive(true)
        value = AVAudioSession.sharedInstance().outputVolume
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let v = change.newValue else { return }
            DispatchQueue.main.async { self?.value = v }
        }
    }

    private var slider: UISlider? {
        guard let view = volumeView else { return nil }
        if let direct = view.subviews.compactMap({ $0 as? UISlider }).first { return direct }
        // Newer iOS versions nest it one level deeper.
        return view.subviews.flatMap(\.subviews).compactMap { $0 as? UISlider }.first
    }

    func set(_ v: Float) {
        let target = min(1, max(0, v))
        value = target
        guard let slider else { return }
        slider.setValue(target, animated: false)
        slider.sendActions(for: .valueChanged)
        slider.sendActions(for: .touchUpInside)
    }
}

/// Hidden MPVolumeView: the supported way to change the system volume from a custom slider.
/// It must stay in the window (tiny and nearly transparent, not `isHidden`) for iOS to accept it.
struct HiddenVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        v.alpha = 0.011
        v.showsRouteButton = false
        SystemVolume.shared.volumeView = v
        return v
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        SystemVolume.shared.volumeView = uiView
    }
}

struct VolumeSlider: View {
    @ObservedObject var volume = SystemVolume.shared
    @State private var drag: Float?

    var body: some View {
        HStack(spacing: 12) {
            IconView(icon: .volume, size: 20)
                .foregroundStyle(NC.onGradient)
            GeometryReader { geo in
                let w = max(geo.size.width, 1)
                let v = CGFloat(drag ?? volume.value)
                ZStack(alignment: .leading) {
                    Capsule().fill(NC.text.opacity(0.2)).frame(height: 4)
                    Capsule().fill(NC.onGradient).frame(width: w * v, height: 4)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let f = Float(min(max(0, g.location.x / w), 1))
                            drag = f
                            volume.set(f)
                        }
                        .onEnded { _ in drag = nil }
                )
            }
            .frame(height: 44)
        }
        .background(alignment: .leading) {
            HiddenVolumeView()
                .frame(width: 40, height: 20)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("cd_volume"))
        .accessibilityValue("\(Int(volume.value * 100))%")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: volume.set(min(1, volume.value + 0.0625))
            case .decrement: volume.set(max(0, volume.value - 0.0625))
            @unknown default: break
            }
        }
    }
}

/// AirPlay route picker inside the 44 pt rounded button.
struct AirPlayButton: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.iconButton, style: .continuous).fill(NC.onGradientButton)
            IconView(icon: .airplay, size: 20).foregroundStyle(NC.text)
            RoutePicker().frame(width: 44, height: 44).opacity(0.02)
        }
        .frame(width: 44, height: 44)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("cd_airplay"))
    }
}

private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.prioritizesVideoDevices = false
        v.tintColor = .white
        v.activeTintColor = .white
        return v
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// Bottom snackbar.
struct ToastView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.manrope(14, .semibold, relativeTo: .callout))
            .foregroundStyle(NC.text)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(NC.elevated, in: Capsule())
            .overlay(Capsule().stroke(NC.text.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// Text that truncates on one line and shows the full text on long-press (long EN/RU strings).
struct TruncatingText: View {
    let text: String
    var font: Font
    var color: Color = NC.text
    @State private var showFull = false

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .onLongPressGesture(minimumDuration: 0.4) { showFull = true }
            .popoverCompat(isPresented: $showFull, text: text)
    }
}

extension View {
    @ViewBuilder
    func popoverCompat(isPresented: Binding<Bool>, text: String) -> some View {
        if #available(iOS 16.4, *) {
            self.popover(isPresented: isPresented) {
                Text(text)
                    .font(.manrope(14, .semibold))
                    .foregroundStyle(NC.text)
                    .padding(14)
                    .presentationCompactAdaptation(.popover)
                    .background(NC.elevated)
            }
        } else {
            self.alert(text, isPresented: isPresented) { Button("OK", role: .cancel) {} }
        }
    }
}
