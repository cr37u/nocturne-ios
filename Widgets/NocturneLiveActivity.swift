import SwiftUI
import UIKit
import WidgetKit
import ActivityKit

/// Live Activity matching the "Dynamic Island + Live Activity" board:
/// compact (25 pt artwork + amber equalizer), minimal (round artwork), expanded (56 pt artwork, title,
/// artist, equalizer, bright-gradient progress with times, previous · play/pause · next) and the
/// lock-screen card (gradient #1E40AF → #3B0764) shown on every model.
struct NocturneLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NocturneActivityAttributes.self) { context in
            LockScreenActivityView(state: context.state)
                .activityBackgroundTint(Color.clear)
                .activitySystemActionForegroundColor(NC.text)
                .widgetURL(URL(string: "nocturne://player"))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 12) {
                        ActivityArtwork(state: state, size: 56, radius: 14)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.title)
                                .font(.manropeFixed(16, .extraBold))
                                .foregroundStyle(NC.text)
                                .lineLimit(1)
                            Text(state.artist)
                                .font(.manropeFixed(13, .regular))
                                .foregroundStyle(NC.onDark2)
                                .lineLimit(1)
                        }
                    }
                    .padding(.leading, 6)
                    .dynamicIsland(verticalPlacement: .belowIfTooWide)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StaticEqualizer(playing: state.isPlaying, heights: [14, 20, 16, 22, 12])
                        .padding(.trailing, 8)
                        .frame(maxHeight: .infinity)
                        .dynamicIsland(verticalPlacement: .belowIfTooWide)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 12) {
                        ActivityProgress(state: state, gradient: true)
                        ActivityControls(state: state, glow: true, iconSize: 24)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                }
            } compactLeading: {
                ActivityArtwork(state: state, size: 25, radius: 8, iconScale: 0.52)
            } compactTrailing: {
                StaticEqualizer(playing: state.isPlaying, heights: [10, 15, 12, 8], barWidth: 3, spacing: 3)
                    .frame(width: 22)
            } minimal: {
                ActivityArtwork(state: state, size: 25, radius: 12.5, iconScale: 0)
            }
            .widgetURL(URL(string: "nocturne://player"))
            .keylineTint(NC.brightEnd)
        }
    }
}

private struct ActivityArtwork: View {
    let state: NocturneActivityAttributes.ContentState
    let size: CGFloat
    let radius: CGFloat
    var iconScale: CGFloat = 0.43

    var body: some View {
        ZStack {
            if let url = NowPlayingSnapshot.artworkURL(state.artworkFile), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                NC.artwork
                if iconScale > 0 {
                    IconView(icon: .moon, size: size * iconScale, lineWidth: size < 30 ? 2.4 : 1.6)
                        .foregroundStyle(NC.text.opacity(0.92))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Times + bar. While playing the bar and the elapsed time are driven by the system timer
/// (no updates needed); paused shows the frozen position.
private struct ActivityProgress: View {
    let state: NocturneActivityAttributes.ContentState
    var gradient: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if state.isPlaying {
                    Text(timerInterval: state.trackStart...state.trackEnd, countsDown: false)
                        .multilineTextAlignment(.leading)
                } else {
                    Text(Fmt.clock(state.position))
                }
            }
            .frame(width: 38, alignment: .leading)
            Group {
                if state.isPlaying {
                    ProgressView(timerInterval: state.trackStart...state.trackEnd, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.linear)
                    .tint(gradient ? NC.brightEnd : NC.text)
                } else {
                    WidgetProgressBar(
                        fraction: state.progress,
                        height: 4,
                        track: gradient ? NC.progressTrack : NC.text.opacity(0.22),
                        fill: gradient ? AnyShapeStyle(NC.brightHorizontal) : AnyShapeStyle(NC.text)
                    )
                }
            }
            Text(Fmt.clock(state.duration))
                .frame(width: 38, alignment: .trailing)
        }
        .font(.manropeFixed(11, .semibold))
        .monospacedDigit()
        .foregroundStyle(gradient ? NC.onDark2 : NC.onGradient)
    }
}

private struct ActivityControls: View {
    let state: NocturneActivityAttributes.ContentState
    var glow: Bool
    var iconSize: CGFloat

    var body: some View {
        HStack(spacing: 34) {
            WidgetControl(command: .previous) {
                IconView(icon: .previous, size: iconSize).foregroundStyle(NC.text).frame(width: 44, height: 44)
            }
            WidgetControl(command: .toggle) {
                ZStack {
                    Circle().fill(NC.text)
                    IconView(icon: state.isPlaying ? .pause : .play, size: 20).foregroundStyle(NC.playIcon)
                }
                .frame(width: 48, height: 48)
                .shadow(color: glow ? NC.brightEnd.opacity(0.6) : .clear, radius: 11)
            }
            WidgetControl(command: .next) {
                IconView(icon: .next, size: iconSize).foregroundStyle(NC.text).frame(width: 44, height: 44)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Lock-screen presentation (all models, iOS 16.1+).
private struct LockScreenActivityView: View {
    let state: NocturneActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ActivityArtwork(state: state, size: 56, radius: 14)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NC.text.opacity(0.14), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title)
                        .font(.manropeFixed(16, .extraBold))
                        .foregroundStyle(NC.text)
                        .lineLimit(1)
                    Text(state.playlist.map { "\(state.artist) · \($0)" } ?? state.artist)
                        .font(.manropeFixed(13, .regular))
                        .foregroundStyle(NC.onGradient)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: "Nocturne")
                    .font(.manropeFixed(11, .bold))
                    .foregroundStyle(NC.text)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(NC.bg.opacity(0.35), in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .fixedSize(horizontal: false, vertical: true)
            ActivityProgress(state: state, gradient: false)
            ActivityControls(state: state, glow: false, iconSize: 22)
        }
        .padding(16)
        .background(
            LinearGradient(colors: [NC.gradStart.opacity(0.9), NC.gradEnd.opacity(0.92)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }
}
