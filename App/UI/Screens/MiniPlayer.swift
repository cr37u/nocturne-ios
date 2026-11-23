import SwiftUI
import UIKit

/// Floating mini-player (boards 01 / 04): 1 pt bright-gradient border, #161630 inside, artwork,
/// title / artist, white play/pause, next, thin progress line. Tap or swipe up → Now Playing.
struct MiniPlayer: View {
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.metrics) private var m
    let namespace: Namespace.ID
    @State private var swipeX: CGFloat = 0

    var body: some View {
        if let track = engine.current {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ArtworkView(file: track.artworkFile, seed: track.id, size: 42, radius: 12,
                                placeholder: .moon, iconScale: 0.38, gradient: track.artworkFile == nil ? NC.primary : nil)
                        .matchedGeometryEffect(id: "artwork", in: namespace)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.title)
                            .font(.manrope(14, .bold, relativeTo: .subheadline))
                            .foregroundStyle(NC.text)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.manrope(12, relativeTo: .caption))
                            .foregroundStyle(NC.text2)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(x: swipeX)
                    .opacity(1 - min(0.8, Double(abs(swipeX) / 160)))
                    PlayPauseButton(isPlaying: engine.isPlaying, size: 44, iconSize: 16) {
                        engine.togglePlayPause()
                    }
                    .accessibilityIdentifier("mini-playpause")
                    Button {
                        Haptics.tap()
                        engine.next()
                    } label: {
                        IconView(icon: .next, size: 18)
                            .foregroundStyle(NC.text)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel(L10n.t("cd_next"))
                }
                MiniProgress(clock: engine.clock)
                    .padding(.horizontal, 4)
            }
            .padding(EdgeInsets(top: 8, leading: 8, bottom: 10, trailing: 8))
            .background(NC.miniPlayer, in: RoundedRectangle(cornerRadius: Radius.miniPlayer - 1, style: .continuous))
            .padding(1)
            .background(NC.brightDiagonal, in: RoundedRectangle(cornerRadius: Radius.miniPlayer, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            .contentShape(Rectangle())
            .onTapGesture { open() }
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { v in
                        if abs(v.translation.width) > abs(v.translation.height) { swipeX = v.translation.width * 0.7 }
                    }
                    .onEnded { v in
                        let dx = v.translation.width
                        if v.translation.height < -30 && abs(v.translation.height) > abs(dx) {
                            withAnimation(.spring(response: 0.3)) { swipeX = 0 }
                            open()
                        } else if abs(dx) > 60 || abs(v.predictedEndTranslation.width) > 200 {
                            slide(direction: dx < 0 ? -1 : 1)
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { swipeX = 0 }
                        }
                    }
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mini-player")
            .accessibilityAction(named: L10n.t("now_playing")) { open() }
        }
    }

    /// -1 = next, +1 = previous: text slides out, the new title slides in from the other side.
    private func slide(direction: CGFloat) {
        Haptics.tap()
        withAnimation(.easeIn(duration: 0.13)) { swipeX = direction * 140 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
            if direction < 0 { engine.next() } else { engine.previous(force: true) }
            var jump = Transaction()
            jump.disablesAnimations = true
            withTransaction(jump) { swipeX = -direction * 140 }
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { swipeX = 0 }
            }
        }
    }

    private func open() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { app.nowPlayingOpen = true }
    }
}

private struct MiniProgress: View {
    @ObservedObject var clock: PlaybackClock
    var body: some View { ThinProgress(fraction: clock.fraction, height: 3) }
}
