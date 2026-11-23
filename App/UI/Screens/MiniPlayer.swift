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
            .gesture(DragGesture(minimumDistance: 20).onEnded { v in
                if v.translation.height < -30 { open() }
                else if v.translation.width < -60 { engine.next() }
                else if v.translation.width > 60 { engine.previous() }
            })
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mini-player")
            .accessibilityAction(named: L10n.t("now_playing")) { open() }
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
