import SwiftUI
import UIKit

/// Library (boards 01 / 04): header, link bar with gradient "Lipește", pill tabs and the lists.
struct LibraryView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.metrics) private var m

    @State private var searching = false
    @State private var query = ""
    @State private var link = ""
    @State private var sort: TrackSort = .recent
    @FocusState private var searchFocused: Bool
    @FocusState private var linkFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                if searching {
                    searchBar.padding(.top, 16)
                } else {
                    linkBar.padding(.top, 16)
                }
                if let clip = app.clipboardLink, !searching {
                    clipboardBanner(clip).padding(.top, 10)
                }
                HStack(spacing: 8) {
                    PillTabs(selection: $app.tab)
                    if !library.tracks.isEmpty {
                        // Always in the layout (only hidden off "Melodii") so the pills don't jump.
                        sortMenu
                            .opacity(app.tab == .songs ? 1 : 0)
                            .allowsHitTesting(app.tab == .songs)
                            .animation(.easeOut(duration: 0.2), value: app.tab)
                    }
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, m.hPad)
            .padding(.top, m.topPad)

            // Swipe left / right between the tabs; the pills follow the page.
            TabView(selection: $app.tab) {
                songs.tag(LibraryTab.songs)
                PlaylistsGrid().tag(LibraryTab.playlists)
                downloads.tag(LibraryTab.downloads)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .padding(.top, 10)
        }
        .background(NC.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(NC.primary)
                IconView(icon: .moon, size: 18).foregroundStyle(NC.text)
            }
            .frame(width: 34, height: 34)
            .accessibilityLabel(L10n.t("cd_logo"))
            Text(verbatim: "Nocturne")
                .font(.manrope(m.brandFont, .extraBold, relativeTo: .title2))
                .tracking(-0.02 * m.brandFont)
                .foregroundStyle(NC.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            IconButton(icon: searching ? .xmark : .search, label: L10n.t(searching ? "cd_close_search" : "cd_search")) {
                withAnimation(.easeOut(duration: 0.2)) {
                    searching.toggle()
                    if searching { app.tab = .songs } else { query = "" }
                }
                searchFocused = searching
            }
            .accessibilityIdentifier("search-button")
            IconButton(icon: .sliders, label: L10n.t("cd_settings")) {
                app.path.append(.settings)
            }
            .accessibilityIdentifier("settings-button")
        }
    }

    private var linkBar: some View {
        HStack(spacing: 8) {
            IconView(icon: .link, size: 17).foregroundStyle(NC.text2)
            TextField("", text: $link, prompt: Text(L10n.t("link_placeholder")).foregroundColor(NC.placeholder))
                .font(.manrope(14, relativeTo: .callout))
                .foregroundStyle(NC.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .focused($linkFocused)
                .onSubmit(submitLink)
                .accessibilityLabel(L10n.t("link_label"))
            GradientButton(title: L10n.t("paste")) { pasteLink() }
                .accessibilityIdentifier("paste-button")
        }
        .padding(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 5))
        .background(NC.surface, in: RoundedRectangle(cornerRadius: Radius.input, style: .continuous))
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            IconView(icon: .search, size: 17).foregroundStyle(NC.text2)
            TextField("", text: $query, prompt: Text(L10n.t("search_placeholder")).foregroundColor(NC.placeholder))
                .font(.manrope(14, relativeTo: .callout))
                .foregroundStyle(NC.text)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    IconView(icon: .xmark, size: 16).foregroundStyle(NC.text2).frame(width: 44, height: 44)
                }
                .accessibilityLabel(L10n.t("cd_clear"))
            }
        }
        .frame(minHeight: 54)
        .padding(.leading, 14)
        .padding(.trailing, 5)
        .background(NC.surface, in: RoundedRectangle(cornerRadius: Radius.input, style: .continuous))
    }

    private func clipboardBanner(_ clip: String) -> some View {
        HStack(spacing: 10) {
            IconView(icon: .clipboard, size: 18).foregroundStyle(NC.amber)
            Text(L10n.t("clipboard_found"))
                .font(.manrope(13, .semibold, relativeTo: .footnote))
                .foregroundStyle(NC.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                let candidate = clip.isEmpty ? UIPasteboard.general.string : clip
                app.clipboardLink = nil
                if let url = YouTubeLinks.extractURL(from: candidate) {
                    app.openAdd(url)
                } else {
                    app.showToast(L10n.t("clipboard_empty"))
                }
            } label: {
                Text(L10n.t("clipboard_add"))
                    .font(.manrope(13, .bold, relativeTo: .footnote))
                    .foregroundStyle(NC.bg)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 34)
                    .background(NC.text, in: Capsule())
            }
            .frame(minHeight: 44)
            Button { app.clipboardLink = nil } label: {
                IconView(icon: .xmark, size: 14).foregroundStyle(NC.text2).frame(width: 32, height: 44)
            }
            .accessibilityLabel(L10n.t("cd_close"))
        }
        .padding(.horizontal, 12)
        .background(NC.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var sortMenu: some View {
        Menu {
            Picker(L10n.t("sort"), selection: $sort) {
                ForEach(TrackSort.allCases) { s in Text(L10n.t(s.labelKey)).tag(s) }
            }
            Divider()
            Button { engine.play(visibleTracks, context: .library) } label: {
                Label(L10n.t("play_all"), systemImage: "play.fill")
            }
            Button { engine.play(visibleTracks, context: .library, shuffled: true) } label: {
                Label(L10n.t("shuffle_all"), systemImage: "shuffle")
            }
        } label: {
            IconView(icon: .sort, size: 17)
                .foregroundStyle(NC.text2)
                .frame(width: 44, height: 44)
                .background(NC.surface, in: Circle())
        }
        .accessibilityLabel(L10n.t("sort"))
    }

    // MARK: lists

    private var visibleTracks: [Track] {
        library.search(query, in: library.sorted(library.tracks, by: sort))
    }

    @ViewBuilder
    private var songs: some View {
        let list = visibleTracks
        if library.tracks.isEmpty {
            EmptyLibrary()
        } else if list.isEmpty {
            Text(L10n.t("search_empty"))
                .font(.manrope(15, relativeTo: .body))
                .foregroundStyle(NC.text2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 40)
        } else {
            List {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, track in
                    TrackRow(
                        track: track,
                        isCurrent: engine.current?.id == track.id,
                        isPlaying: engine.isPlaying,
                        onTap: {
                            if engine.current?.id == track.id {
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { app.nowPlayingOpen = true }
                            } else {
                                engine.play(list, startAt: i, context: .library)
                            }
                        },
                        menu: TrackMenuItems(track: track)
                    )
                    .listRowInsets(EdgeInsets(top: 1, leading: m.hPad, bottom: 1, trailing: m.hPad))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { app.deleteTrack = track } label: {
                            Label(L10n.t("delete"), systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button { library.toggleFavorite(track.id) } label: {
                            Label(L10n.t("cd_favorite"), systemImage: track.isFavorite ? "heart.slash.fill" : "heart.fill")
                        }
                        .tint(NC.amber)
                    }
                }
                Color.clear.frame(height: 0).miniPlayerSpacerRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .environment(\.defaultMinListRowHeight, 10)
            .accessibilityIdentifier("songs-list")
        }
    }

    private var downloads: some View {
        ScrollView {
            DownloadsSection()
                .padding(.horizontal, m.hPad)
            MiniPlayerSpacer()
        }
    }

    // MARK: actions

    private func pasteLink() {
        Haptics.tap()
        let text = UIPasteboard.general.string
        if let url = YouTubeLinks.extractURL(from: text) {
            link = ""
            app.clipboardLink = nil
            app.openAdd(url)
        } else if YouTubeLinks.extractURL(from: link) != nil {
            submitLink()
        } else {
            app.showToast(L10n.t("clipboard_empty"))
        }
    }

    private func submitLink() {
        let typed = link
        guard let url = YouTubeLinks.extractURL(from: typed) else {
            if !typed.isEmpty { app.showToast(L10n.t("error_invalid_link")) }
            return
        }
        link = ""
        linkFocused = false
        app.openAdd(url)
    }
}

private struct EmptyLibrary: View {
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(NC.primary)
                IconView(icon: .moonWave, size: 40, lineWidth: 1.6).foregroundStyle(NC.text)
            }
            .frame(width: 84, height: 84)
            Text(L10n.t("library_empty_title"))
                .font(.manrope(20, .extraBold, relativeTo: .title3))
                .foregroundStyle(NC.text)
            Text(L10n.t("library_empty_body"))
                .font(.manrope(14, relativeTo: .body))
                .foregroundStyle(NC.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.bottom, 80)
    }
}
