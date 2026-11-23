import SwiftUI
import UIKit

/// Sheet chrome: dark surface, grabber, title.
struct SheetContainer<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.manrope(18, .extraBold, relativeTo: .headline))
                .foregroundStyle(NC.text)
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 12)
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NC.surface.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }
}

/// "Alege playlistul" (+ "Playlist nou").
struct PlaylistPickerSheet: View {
    let track: Track
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var name = ""

    var body: some View {
        SheetContainer(title: L10n.t("choose_playlist")) {
            ScrollView {
                VStack(spacing: 4) {
                    Button {
                        name = ""
                        creating = true
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NC.primary)
                                IconView(icon: .plus, size: 20).foregroundStyle(NC.text)
                            }
                            .frame(width: 46, height: 46)
                            Text(L10n.t("new_playlist_title")).font(.manrope(15, .bold)).foregroundStyle(NC.text)
                            Spacer()
                        }
                        .padding(8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.98))
                    ForEach(library.playlists) { s in
                        let contains = library.playlistTrackIds[s.id]?.contains(track.id) == true
                        Button {
                            library.add(track.id, toPlaylist: s.id)
                            app.showToast(L10n.f("added_to_playlist", s.playlist.name))
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                ArtworkView(file: s.firstArtwork, seed: "pl-\(s.id)", size: 46, radius: 12)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.playlist.name).font(.manrope(15, .bold)).foregroundStyle(NC.text).lineLimit(1)
                                    Text(L10n.p("songs_count", s.trackCount)).font(.manrope(13)).foregroundStyle(NC.text2)
                                }
                                Spacer()
                                if contains { IconView(icon: .check, size: 18, lineWidth: 2.4).foregroundStyle(NC.amber) }
                            }
                            .padding(8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.98))
                        .disabled(contains)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
        }
        .alert(L10n.t("new_playlist_title"), isPresented: $creating) {
            TextField(L10n.t("playlist_name_hint"), text: $name)
            Button(L10n.t("cancel"), role: .cancel) {}
            Button(L10n.t("create")) {
                if let id = library.createPlaylist(name: name) {
                    library.add(track.id, toPlaylist: id)
                    app.showToast(L10n.f("added_to_playlist", name))
                    dismiss()
                }
            }
        }
    }
}

/// "Editează detaliile": title / artist; marks the track userEdited so it is never overwritten.
struct EditDetailsSheet: View {
    let track: Track
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var artist: String = ""

    var body: some View {
        SheetContainer(title: L10n.t("edit_details_title")) {
            VStack(alignment: .leading, spacing: 16) {
                field(L10n.t("edit_title_label"), text: $title)
                field(L10n.t("edit_artist_label"), text: $artist)
                HStack(spacing: 10) {
                    Button { dismiss() } label: {
                        Text(L10n.t("cancel"))
                            .font(.manrope(15, .bold))
                            .foregroundStyle(NC.text)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(NC.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    GradientButton(title: L10n.t("save"), height: 48, radius: 16, fontSize: 15, expand: true) {
                        library.updateDetails(track.id, title: title, artist: artist)
                        app.showToast(L10n.t("details_saved"))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            title = track.title
            artist = track.artist
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.manrope(13, .semibold)).foregroundStyle(NC.text2)
            TextField("", text: text)
                .font(.manrope(16))
                .foregroundStyle(NC.text)
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(NC.bg, in: RoundedRectangle(cornerRadius: Radius.input, style: .continuous))
        }
    }
}

/// Reorderable queue: drag to reorder, swipe to remove, tap to play.
struct QueueSheet: View {
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        SheetContainer(title: L10n.t("queue")) {
            if engine.queue.isEmpty {
                Text(L10n.t("queue_empty"))
                    .font(.manrope(14)).foregroundStyle(NC.text2)
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                List {
                    ForEach(Array(engine.queue.enumerated()), id: \.element.id) { i, track in
                        HStack(spacing: 12) {
                            ArtworkView(file: track.artworkFile, seed: track.id, size: 44, radius: 12)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.manrope(15, .bold))
                                    .foregroundStyle(i == engine.index ? NC.amber : NC.text)
                                    .lineLimit(1)
                                Text(track.artist).font(.manrope(13)).foregroundStyle(NC.text2).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if i == engine.index { EqualizerBars(playing: engine.isPlaying, height: 14) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { engine.playAt(i) }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .onMove { engine.moveInQueue(from: $0, to: $1) }
                    .onDelete { engine.removeFromQueue(at: $0) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))
            }
        }
    }
}

/// "Versuri": synced lyrics follow the song (current line highlighted, tap a line to seek).
struct LyricsSheet: View {
    let track: Track
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var lang: LanguageManager
    @State private var state: LoadState = .loading

    enum LoadState: Equatable { case loading, ready(Lyrics), offline }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("lyrics").uppercased())
                    .font(.manrope(12, .bold)).tracking(0.7).foregroundStyle(NC.text2)
                Text(track.title).font(.manrope(17, .bold)).foregroundStyle(NC.text).lineLimit(1)
                Text(track.artist).font(.manrope(13)).foregroundStyle(NC.text2).lineLimit(1)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 12)
            Group {
                switch state {
                case .loading: message(L10n.t("lyrics_loading"), loading: true)
                case .offline: message(L10n.t("lyrics_offline"), retry: true)
                case .ready(let lyrics):
                    switch lyrics {
                    case .synced(let lines): SyncedLyricsView(lines: lines, clock: engine.clock) { engine.seek(to: $0) }
                    case .plain(let text):
                        ScrollView {
                            Text(text)
                                .font(.manrope(16))
                                .lineSpacing(8)
                                .foregroundStyle(NC.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 8)
                        }
                    case .instrumental: message(L10n.t("lyrics_instrumental"))
                    case .notFound: message(L10n.t("lyrics_not_found"), retry: true)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            Text(L10n.t("lyrics_source"))
                .font(.manrope(11)).foregroundStyle(NC.text2)
                .padding(.horizontal, 24).padding(.vertical, 10)
        }
        .background(NC.surface.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .task(id: track.id) { await load(force: false) }
    }

    private func load(force: Bool) async {
        state = .loading
        do {
            state = .ready(try await LyricsRepository.load(track, forceRefresh: force))
        } catch {
            if let cached = LyricsRepository.cached(track) { state = .ready(cached) } else { state = .offline }
        }
    }

    private func message(_ text: String, loading: Bool = false, retry: Bool = false) -> some View {
        VStack(spacing: 12) {
            if loading {
                ProgressView().tint(NC.brightStart).scaleEffect(1.3)
            } else {
                IconView(icon: .lyrics, size: 32).foregroundStyle(NC.text2)
            }
            Text(text).font(.manrope(15)).foregroundStyle(NC.text2).multilineTextAlignment(.center)
            if retry {
                Button { Task { await load(force: true) } } label: {
                    Text(L10n.t("retry")).font(.manrope(14, .bold)).foregroundStyle(NC.amber).frame(minHeight: 44)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

private struct SyncedLyricsView: View {
    let lines: [LyricLine]
    @ObservedObject var clock: PlaybackClock
    let onSeek: (Double) -> Void

    var body: some View {
        let current = max(0, (lines.lastIndex { $0.time <= clock.position + 0.25 }) ?? 0)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.manrope(i == current ? 22 : 19, i == current ? .extraBold : .bold))
                            .foregroundStyle(i == current ? NC.text : (i < current ? NC.text2.opacity(0.55) : NC.text2))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                            .onTapGesture { onSeek(line.time) }
                            .id(i)
                            .animation(.easeOut(duration: 0.2), value: current)
                    }
                    Color.clear.frame(height: 160)
                }
            }
            .onChange(of: current) { value in
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(max(0, value - 2), anchor: .top) }
            }
        }
    }
}
