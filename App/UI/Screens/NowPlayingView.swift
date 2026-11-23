import SwiftUI
import UIKit

/// Now Playing (boards 02 / 03): 170° gradient, top bar, big artwork (1.0 playing / 0.9 paused),
/// title + artist, add-to-playlist + amber favorite, seek bar, controls, volume + AirPlay + queue.
struct NowPlayingView: View {
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.metrics) private var m
    let namespace: Namespace.ID
    @State private var dragOffset: CGFloat = 0
    @State private var artworkSwipe: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let artSide = m.npArtwork(availableHeight: geo.size.height)
            ZStack {
                CSSLinearGradient.nowPlaying.ignoresSafeArea()
                if let track = engine.current {
                    content(track, artSide: artSide)
                        .padding(.horizontal, m.npPad)
                        .padding(.top, 8)
                        .padding(.bottom, m.npBottomPad)
                }
            }
        }
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { v in if v.translation.height > 0 && abs(v.translation.height) > abs(v.translation.width) { dragOffset = v.translation.height } }
                .onEnded { v in
                    if v.translation.height > 140 || v.predictedEndTranslation.height > 320 {
                        close()
                    } else {
                        withAnimation(.spring(response: 0.3)) { dragOffset = 0 }
                    }
                }
        )
        .accessibilityIdentifier("now-playing")
    }

    @ViewBuilder
    private func content(_ track: Track, artSide: CGFloat) -> some View {
        VStack(spacing: 0) {
            topBar(track)
            artwork(track, side: artSide)
                .padding(.top, m.npGap)
            titleRow(track)
                .padding(.top, m.npGap)
            SeekBar(clock: engine.clock) { engine.seek(to: $0) }
                .padding(.top, 22 - 10)
            controls
                .padding(.top, 14)
            Spacer(minLength: 12)
            HStack(spacing: 12) {
                VolumeSlider()
                AirPlayButton()
                IconButton(icon: .queue, label: L10n.t("cd_queue"), iconSize: 20, background: NC.onGradientButton) {
                    app.queueOpen = true
                }
            }
        }
    }

    private func topBar(_ track: Track) -> some View {
        HStack(alignment: .center) {
            IconButton(icon: .chevronDown, label: L10n.t("cd_close"), iconSize: 22, background: NC.onGradientButton, lineWidth: 2.2) {
                close()
            }
            .accessibilityIdentifier("np-close")
            Spacer(minLength: 8)
            VStack(spacing: 2) {
                Text(L10n.t(engine.context.isPlaylist ? "playing_from_playlist" : "playing_from_library"))
                    .font(.manrope(11, .bold, relativeTo: .caption2))
                    .tracking(11 * 0.12)
                    .foregroundStyle(NC.onGradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(engine.context.label ?? L10n.t("all_songs"))
                    .font(.manrope(14, .bold, relativeTo: .subheadline))
                    .foregroundStyle(NC.text)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 8)
            Menu {
                Button { app.lyricsOpen = true } label: { Label(L10n.t("lyrics"), systemImage: "quote.bubble") }
                TrackMenuItems(track: track, includeQueueActions: false)
                Button { app.queueOpen = true } label: { Label(L10n.t("queue"), systemImage: "list.bullet") }
            } label: {
                IconView(icon: .more, size: 20)
                    .foregroundStyle(NC.text)
                    .frame(width: 44, height: 44)
                    .background(NC.onGradientButton, in: RoundedRectangle(cornerRadius: Radius.iconButton, style: .continuous))
            }
            .accessibilityLabel(L10n.t("cd_more"))
        }
    }

    private func artwork(_ track: Track, side: CGFloat) -> some View {
        ArtworkView(file: track.artworkFile, seed: track.id, size: side, radius: Radius.nowPlayingArtwork,
                    placeholder: .moonWave, iconScale: 0.374, gradient: track.artworkFile == nil ? NC.artwork : nil)
            .matchedGeometryEffect(id: "artwork", in: namespace)
            .shadow(color: NC.shadow, radius: 30, y: 30)
            .scaleEffect(engine.isPlaying ? 1.0 : 0.9)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: engine.isPlaying)
            .offset(x: artworkSwipe)
            .frame(maxWidth: .infinity)
            .gesture(
                // Swipe left / right on the artwork to skip (same as Android).
                DragGesture(minimumDistance: 16)
                    .onChanged { v in
                        if abs(v.translation.width) > abs(v.translation.height) { artworkSwipe = v.translation.width * 0.4 }
                    }
                    .onEnded { v in
                        let dx = v.translation.width
                        if abs(dx) > 80 && abs(dx) > abs(v.translation.height) {
                            Haptics.tap()
                            if dx < 0 { engine.next() } else { engine.previous() }
                        }
                        withAnimation(.spring(response: 0.3)) { artworkSwipe = 0 }
                    }
            )
            .onTapGesture(count: 2) { library.toggleFavorite(track.id) }
            .accessibilityElement()
            .accessibilityLabel("\(track.title), \(track.artist)")
    }

    private func titleRow(_ track: Track) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                TruncatingText(text: track.title, font: .manrope(24, .extraBold, relativeTo: .title2))
                    .tracking(-0.24)
                Text(track.artist)
                    .font(.manrope(16, relativeTo: .callout))
                    .foregroundStyle(NC.onGradient)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            IconButton(icon: .listPlus, label: L10n.t("cd_add_to_playlist"), iconSize: 20, background: NC.onGradientButton) {
                app.playlistPickerTrack = track
            }
            IconButton(icon: .heart, label: L10n.t("cd_favorite"), iconSize: 20, background: NC.onGradientButton,
                       foreground: track.isFavorite ? NC.amber : NC.text, filled: track.isFavorite, haptic: true) {
                library.toggleFavorite(track.id)
            }
            .accessibilityAddTraits(track.isFavorite ? .isSelected : [])
        }
    }

    private var controls: some View {
        HStack {
            toggle(icon: .shuffle, on: engine.shuffle, label: L10n.t(engine.shuffle ? "shuffle_on" : "shuffle_off")) {
                engine.toggleShuffle()
            }
            Spacer(minLength: 0)
            Button {
                Haptics.tap()
                engine.previous()
            } label: {
                IconView(icon: .previous, size: 30).foregroundStyle(NC.text).frame(width: 56, height: 56).contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(L10n.t("cd_previous"))
            Spacer(minLength: 0)
            PlayPauseButton(isPlaying: engine.isPlaying, size: 78, iconSize: 30, glow: true) { engine.togglePlayPause() }
                .accessibilityIdentifier("np-playpause")
            Spacer(minLength: 0)
            Button {
                Haptics.tap()
                engine.next()
            } label: {
                IconView(icon: .next, size: 30).foregroundStyle(NC.text).frame(width: 56, height: 56).contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(L10n.t("cd_next"))
            Spacer(minLength: 0)
            ZStack(alignment: .topTrailing) {
                toggle(icon: .repeat, on: engine.repeatMode != .off, label: L10n.t(engine.repeatMode.labelKey)) {
                    engine.cycleRepeat()
                }
                if engine.repeatMode == .one {
                    Text(verbatim: "1")
                        .font(.manropeFixed(10, .extraBold))
                        .foregroundStyle(NC.bg)
                        .frame(width: 16, height: 16)
                        .background(NC.amber, in: Circle())
                        .offset(x: 4, y: -4)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func toggle(icon: Icon, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.soft()
            action()
        } label: {
            IconView(icon: icon, size: 22)
                .foregroundStyle(on ? NC.amber : NC.text)
                .frame(width: 48, height: 48)
                .background(on ? NC.amberBg : Color.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func close() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            app.nowPlayingOpen = false
            dragOffset = 0
        }
    }
}
