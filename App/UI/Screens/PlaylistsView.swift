import SwiftUI
import UIKit

/// 2-column grid of square gradient covers (radius 22), "Din YouTube" badge, play button on cover.
struct PlaylistsGrid: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.metrics) private var m
    @State private var creating = false
    @State private var newName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Spacer()
                    Button {
                        newName = ""
                        creating = true
                    } label: {
                        HStack(spacing: 6) {
                            IconView(icon: .plus, size: 16)
                            Text(L10n.t("new_playlist")).font(.manrope(13, .bold, relativeTo: .footnote)).lineLimit(1)
                        }
                        .foregroundStyle(NC.text)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(NC.surface, in: Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("new-playlist")
                }
                if library.playlists.isEmpty && library.favorites.isEmpty {
                    Text(L10n.t("playlists_empty"))
                        .font(.manrope(14, relativeTo: .body))
                        .foregroundStyle(NC.text2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                    if !library.favorites.isEmpty {
                        let favs = library.favorites
                        PlaylistCard(
                            name: L10n.t("favorites"), count: favs.count, coverFile: favs.first?.artworkFile,
                            seed: "favorites", fromYoutube: false, isFavorites: true,
                            onOpen: { app.path.append(.favorites) },
                            onPlay: { engine.play(favs, context: PlaybackContext(playlistId: -1, label: L10n.t("favorites"))) }
                        )
                    }
                    ForEach(library.playlists) { summary in
                        PlaylistCard(
                            name: summary.playlist.name, count: summary.trackCount, coverFile: summary.firstArtwork,
                            seed: "pl-\(summary.id)", fromYoutube: summary.playlist.fromYoutube, isFavorites: false,
                            onOpen: { app.path.append(.playlist(summary.id)) },
                            onPlay: {
                                let tracks = library.tracks(inPlaylist: summary.id)
                                engine.play(tracks, context: PlaybackContext(playlistId: summary.id, label: summary.playlist.name))
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, m.hPad)
            MiniPlayerSpacer()
        }
        .alert(L10n.t("new_playlist_title"), isPresented: $creating) {
            TextField(L10n.t("playlist_name_hint"), text: $newName)
            Button(L10n.t("cancel"), role: .cancel) {}
            Button(L10n.t("create")) { library.createPlaylist(name: newName) }
        }
    }
}

struct PlaylistCard: View {
    let name: String
    let count: Int
    let coverFile: String?
    let seed: String
    let fromYoutube: Bool
    let isFavorites: Bool
    let onOpen: () -> Void
    let onPlay: () -> Void
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let side = geo.size.width
                ZStack(alignment: .bottomTrailing) {
                    cover(side: side)
                    if count > 0 {
                        Button {
                            Haptics.tap()
                            onPlay()
                        } label: {
                            ZStack {
                                Circle().fill(NC.text)
                                IconView(icon: .play, size: 16).foregroundStyle(NC.playIcon).offset(x: 1)
                            }
                            .frame(width: 44, height: 44)
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                        }
                        .buttonStyle(PressScaleStyle())
                        .padding(10)
                        .accessibilityLabel(L10n.t("cd_play_playlist"))
                    }
                }
                .overlay(alignment: .topLeading) {
                    if fromYoutube {
                        HStack(spacing: 4) {
                            IconView(icon: .youtube, size: 13, lineWidth: 2)
                            Text(L10n.t("from_youtube")).font(.manrope(11, .bold, relativeTo: .caption2)).lineLimit(1)
                        }
                        .foregroundStyle(NC.text)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(NC.bg.opacity(0.55), in: Capsule())
                        .padding(10)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.manrope(15, .bold, relativeTo: .body))
                    .foregroundStyle(NC.text)
                    .lineLimit(1)
                Text(L10n.p("songs_count", count))
                    .font(.manrope(13, relativeTo: .footnote))
                    .foregroundStyle(NC.text2)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name), \(L10n.p("songs_count", count))")
    }

    @ViewBuilder private func cover(side: CGFloat) -> some View {
        ZStack {
            if let image = ArtworkCache.shared.image(coverFile) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                NC.cover(seed)
                IconView(icon: isFavorites ? .heart : .music, size: side * 0.28, filled: isFavorites)
                    .foregroundStyle(isFavorites ? NC.amber : NC.text.opacity(0.75))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: Radius.cardLarge, style: .continuous))
    }
}

/// Playlist detail: cover, name, count + duration, play / shuffle, rename / delete, reorderable list.
struct PlaylistDetailView: View {
    let playlistId: Int64?
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.metrics) private var m
    @Environment(\.dismiss) private var dismiss
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var editing = false
    /// The big header scrolled away → show the slim top bar.
    @State private var compact = false

    private var isFavorites: Bool { playlistId == nil }
    private var summary: PlaylistSummary? { library.playlists.first { $0.playlist.id == playlistId } }
    private var name: String { isFavorites ? L10n.t("favorites") : (summary?.playlist.name ?? "") }
    private var tracks: [Track] { playlistId.map { library.tracks(inPlaylist: $0) } ?? library.favorites }
    private var context: PlaybackContext { PlaybackContext(playlistId: playlistId ?? -1, label: name) }

    var body: some View {
        let list = tracks
        List {
            // The big header is a normal row (section headers stay pinned): it scrolls away.
            header(list)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .onAppear { if compact { withAnimation(.easeOut(duration: 0.2)) { compact = false } } }
                .onDisappear { withAnimation(.easeOut(duration: 0.2)) { compact = true } }
            Section {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, track in
                    TrackRow(
                        track: track,
                        isCurrent: engine.current?.id == track.id,
                        isPlaying: engine.isPlaying,
                        onTap: { engine.play(list, startAt: i, context: context) },
                        menu: TrackMenuItems(track: track, playlistId: playlistId)
                    )
                    .listRowInsets(EdgeInsets(top: 1, leading: m.hPad, bottom: 1, trailing: m.hPad))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing) {
                        if let pid = playlistId {
                            Button(role: .destructive) { library.remove(track.id, fromPlaylist: pid) } label: {
                                Label(L10n.t("cd_remove"), systemImage: "minus.circle")
                            }
                        } else {
                            Button { library.toggleFavorite(track.id) } label: {
                                Label(L10n.t("menu_favorite_remove"), systemImage: "heart.slash")
                            }
                        }
                    }
                }
                .onMove(perform: playlistId == nil ? nil : { from, to in
                    var ids = list.map(\.id)
                    ids.move(fromOffsets: from, toOffset: to)
                    if let pid = playlistId { library.reorder(playlist: pid, ids: ids) }
                })
            }
            if list.isEmpty {
                Text(L10n.t("playlist_empty"))
                    .font(.manrope(14, relativeTo: .body))
                    .foregroundStyle(NC.text2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Color.clear.frame(height: 0).miniPlayerSpacerRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(editing ? .active : .inactive))
        .background(NC.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            if compact { compactBar(list).transition(.move(edge: .top).combined(with: .opacity)) }
        }
        .alert(L10n.t("rename_playlist_title"), isPresented: $renaming) {
            TextField(L10n.t("playlist_name_hint"), text: $newName)
            Button(L10n.t("cancel"), role: .cancel) {}
            Button(L10n.t("save")) { if let pid = playlistId { library.renamePlaylist(pid, to: newName) } }
        }
        .confirmationDialog(L10n.t("delete_playlist_title"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L10n.t("delete_playlist_only"), role: .destructive) {
                if let pid = playlistId {
                    dismiss()
                    library.deletePlaylist(pid, withSongs: false)
                }
            }
            Button(L10n.t("delete_playlist_with_songs"), role: .destructive) {
                if let pid = playlistId {
                    dismiss()
                    library.deletePlaylist(pid, withSongs: true)
                }
            }
            Button(L10n.t("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("delete_playlist_choice_body"))
        }
    }

    /// Slim bar shown once the header has scrolled away: back · name · play.
    private func compactBar(_ list: [Track]) -> some View {
        HStack(spacing: 12) {
            IconButton(icon: .chevronLeft, label: L10n.t("cd_back")) { dismiss() }
            Text(name)
                .font(.manrope(17, .extraBold, relativeTo: .headline))
                .foregroundStyle(NC.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !list.isEmpty {
                PlayPauseButton(isPlaying: false, size: 40, iconSize: 15) {
                    engine.play(list, context: context)
                }
                .accessibilityLabel(L10n.t("play_all"))
            }
        }
        .padding(.horizontal, m.hPad)
        .padding(.vertical, 8)
        .background(NC.bg.opacity(0.96).ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Rectangle().fill(NC.surface).frame(height: 1) }
    }

    private func header(_ list: [Track]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                IconButton(icon: .chevronLeft, label: L10n.t("cd_back")) { dismiss() }
                Spacer()
                if !isFavorites {
                    if editing {
                        Button { editing = false } label: {
                            Text(L10n.t("done")).font(.manrope(14, .bold)).foregroundStyle(NC.amber).frame(minHeight: 44)
                        }
                    }
                    Menu {
                        Button { newName = name; renaming = true } label: { Label(L10n.t("rename"), systemImage: "pencil") }
                        Button { editing = true } label: { Label(L10n.t("edit"), systemImage: "arrow.up.arrow.down") }
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label(L10n.t("delete_playlist"), systemImage: "trash")
                        }
                    } label: {
                        IconView(icon: .more, size: 19)
                            .foregroundStyle(NC.text)
                            .frame(width: 44, height: 44)
                            .background(NC.surface, in: RoundedRectangle(cornerRadius: Radius.iconButton, style: .continuous))
                    }
                    .accessibilityLabel(L10n.t("cd_more"))
                }
            }
            HStack(alignment: .bottom, spacing: 16) {
                PlaylistCover(file: list.first(where: { $0.artworkFile != nil })?.artworkFile,
                              seed: isFavorites ? "favorites" : "pl-\(playlistId ?? 0)", isFavorites: isFavorites)
                    .frame(width: min(150, m.width * 0.38), height: min(150, m.width * 0.38))
                VStack(alignment: .leading, spacing: 6) {
                    if summary?.playlist.fromYoutube == true {
                        Text(L10n.t("from_youtube").uppercased())
                            .font(.manrope(11, .bold, relativeTo: .caption2))
                            .tracking(1.2)
                            .foregroundStyle(NC.text2)
                    }
                    Text(name)
                        .font(.manrope(22, .extraBold, relativeTo: .title2))
                        .foregroundStyle(NC.text)
                        .lineLimit(3)
                    Text(verbatim: "\(L10n.p("songs_count", list.count)) · \(Fmt.longDuration(list.reduce(0) { $0 + $1.duration }))")
                        .font(.manrope(13, relativeTo: .footnote))
                        .foregroundStyle(NC.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            HStack(spacing: 10) {
                GradientButton(title: L10n.t("play_all"), icon: .play, expand: true) {
                    engine.play(list, context: context)
                }
                Button {
                    engine.play(list, context: context, shuffled: true)
                } label: {
                    HStack(spacing: 8) {
                        IconView(icon: .shuffle, size: 17)
                        Text(L10n.t("shuffle_all")).font(.manrope(14, .bold, relativeTo: .callout)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(NC.text)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(NC.surface, in: RoundedRectangle(cornerRadius: Radius.iconButton, style: .continuous))
                }
                .buttonStyle(PressScaleStyle(scale: 0.97))
            }
            .disabled(list.isEmpty)
            .opacity(list.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, m.hPad)
        .padding(.top, m.topPad)
        .padding(.bottom, 12)
        .background(NC.bg)
    }
}

struct PlaylistCover: View {
    let file: String?
    let seed: String
    let isFavorites: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image = ArtworkCache.shared.image(file) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    NC.cover(seed)
                    IconView(icon: isFavorites ? .heart : .music, size: geo.size.width * 0.3, filled: isFavorites)
                        .foregroundStyle(isFavorites ? NC.amber : NC.text.opacity(0.75))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: Radius.cardLarge, style: .continuous))
        }
    }
}
