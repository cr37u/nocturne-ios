import SwiftUI
import UIKit

/// Cover image, or the deterministic gradient with a music note (lists) / moon (players).
struct ArtworkView: View {
    enum Placeholder { case note, moon, moonWave }

    let file: String?
    let seed: String?
    var size: CGFloat
    var radius: CGFloat
    var placeholder: Placeholder = .note
    var iconScale: CGFloat = 0.39
    var gradient: LinearGradient?

    var body: some View {
        ZStack {
            if let image = ArtworkCache.shared.image(file) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                (gradient ?? NC.cover(seed))
                switch placeholder {
                case .note:
                    IconView(icon: .music, size: size * iconScale).foregroundStyle(NC.text.opacity(0.75))
                case .moon:
                    IconView(icon: .moon, size: size * iconScale).foregroundStyle(NC.text)
                case .moonWave:
                    IconView(icon: .moonWave, size: size * iconScale, lineWidth: 1.2).foregroundStyle(NC.text.opacity(0.85))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Library track row (boards 01 / 04): current row on #141426 with amber title + equalizer.
struct TrackRow: View {
    @Environment(\.metrics) private var m
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    var subtitleExtra: String?
    let onTap: () -> Void
    let menu: TrackMenuItems

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                ArtworkView(file: track.artworkFile, seed: track.id, size: m.thumb, radius: m.thumbRadius)
                if isCurrent {
                    RoundedRectangle(cornerRadius: m.thumbRadius, style: .continuous)
                        .fill(NC.bg.opacity(0.45))
                        .frame(width: m.thumb, height: m.thumb)
                    EqualizerBars(playing: isPlaying, bars: 4, barWidth: 3, spacing: 2.5, height: m.thumb * 0.34)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.manrope(m.rowTitle, .bold, relativeTo: .body))
                    .foregroundStyle(isCurrent ? NC.amber : NC.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.manrope(m.rowSubtitle, .regular, relativeTo: .subheadline))
                    .foregroundStyle(NC.text2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                menu
            } label: {
                IconView(icon: .more, size: 18)
                    .foregroundStyle(NC.text2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.t("cd_track_options"))
        }
        .padding(m.rowPad)
        .background(isCurrent ? NC.surface : Color.clear, in: RoundedRectangle(cornerRadius: m.rowRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: m.rowRadius, style: .continuous))
        .onTapGesture(perform: onTap)
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: L10n.t("cd_play"), onTap)
    }

    private var subtitle: String {
        let base = "\(track.artist) · \(Fmt.clock(track.duration))"
        if let extra = subtitleExtra { return "\(base) · \(extra)" }
        return base
    }
}

/// Context-menu items for a track (shared by the ⋮ menu, long-press and Now Playing "…").
struct TrackMenuItems: View {
    let track: Track
    var playlistId: Int64?
    var includeQueueActions = true
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        let library = Library.shared
        let engine = PlayerEngine.shared
        if includeQueueActions {
            Button { engine.playNext(track); app.showToast(L10n.t("playing_next")) } label: {
                Label(L10n.t("menu_play_next"), systemImage: "text.insert")
            }
            Button { engine.addToQueue(track); app.showToast(L10n.t("added_to_queue")) } label: {
                Label(L10n.t("menu_add_queue"), systemImage: "text.append")
            }
        }
        Button { app.playlistPickerTrack = track } label: {
            Label(L10n.t("menu_add_playlist"), systemImage: "text.badge.plus")
        }
        Button { library.toggleFavorite(track.id) } label: {
            Label(L10n.t(track.isFavorite ? "menu_favorite_remove" : "menu_favorite_add"),
                  systemImage: track.isFavorite ? "heart.slash" : "heart")
        }
        Button { app.editTrack = track } label: {
            Label(L10n.t("menu_edit_details"), systemImage: "pencil")
        }
        if let playlistId {
            Button { library.remove(track.id, fromPlaylist: playlistId) } label: {
                Label(L10n.t("menu_remove_from_playlist"), systemImage: "minus.circle")
            }
        }
        Button(role: .destructive) { app.deleteTrack = track } label: {
            Label(L10n.t("menu_delete"), systemImage: "trash")
        }
    }
}

/// Pill tabs: active = #F1F1F7 with dark text; inactive = #141426 with #9A9AB8.
struct PillTabs: View {
    @Binding var selection: LibraryTab
    @EnvironmentObject private var lang: LanguageManager
    @Namespace private var pill

    /// One spring for taps and page swipes, so the white pill glides between tabs.
    static let motion = Animation.spring(response: 0.38, dampingFraction: 0.86)

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryTab.allCases, id: \.self) { tab in
                    let active = tab == selection
                    Button {
                        guard tab != selection else { return }
                        Haptics.soft()
                        withAnimation(Self.motion) { selection = tab }
                    } label: {
                        Text(L10n.t(tab.key))
                            .font(.manrope(13, .bold, relativeTo: .subheadline))
                            .foregroundStyle(active ? NC.bg : NC.text2)
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 38)
                            .background {
                                ZStack {
                                    Capsule().fill(NC.surface)
                                    if active {
                                        Capsule().fill(NC.text).matchedGeometryEffect(id: "activePill", in: pill)
                                    }
                                }
                            }
                            .animation(Self.motion, value: selection)
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.97))
                    .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
                    .accessibilityIdentifier("tab-\(tab.rawValue)")
                }
            }
        }
    }
}

/// Download row: active (% + bar + MB/s) / done ("Gata" amber + check) / failed ("Eșuat" red +
/// "Reîncearcă") / queued ("În așteptare") / paused.
struct DownloadRow: View {
    @Environment(\.metrics) private var m
    let item: DownloadItem
    let progress: LiveProgress?
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(file: item.status == .done ? Library.shared.track(item.videoId)?.artworkFile : nil,
                        seed: item.videoId, size: m.thumb, radius: m.thumbRadius)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.manrope(m.rowTitle - 1, .bold, relativeTo: .body))
                    .foregroundStyle(NC.text)
                    .lineLimit(1)
                statusLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(m.rowPad)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var statusLine: some View {
        switch item.status {
        case .active:
            if let p = progress, p.totalBytes > 0 {
                VStack(alignment: .leading, spacing: 5) {
                    ThinProgress(fraction: p.fraction, height: 4)
                    HStack(spacing: 6) {
                        Text(verbatim: "\(Int(p.fraction * 100))%").foregroundStyle(NC.text)
                        Text(verbatim: "\(Fmt.size(p.downloadedBytes)) / \(Fmt.size(p.totalBytes))")
                        Spacer(minLength: 0)
                        if p.bytesPerSecond > 0 { Text(Fmt.speed(p.bytesPerSecond)) }
                    }
                    .font(.manrope(12, .semibold, relativeTo: .caption))
                    .monospacedDigit()
                    .foregroundStyle(NC.text2)
                    .lineLimit(1)
                }
            } else {
                Text(L10n.t("status_preparing")).font(.manrope(12, .semibold, relativeTo: .caption)).foregroundStyle(NC.text2)
            }
        case .done:
            Text(item.artist).font(.manrope(12, relativeTo: .caption)).foregroundStyle(NC.text2).lineLimit(1)
        case .failed:
            Text(ErrorKind.from(key: item.errorKey).message)
                .font(.manrope(12, relativeTo: .caption)).foregroundStyle(NC.error).lineLimit(2)
        case .queued:
            Text(item.attempts > 0 ? "\(L10n.t("status_queued")) · \(L10n.f("attempt", item.attempts + 1, DownloadManager.maxAttempts))" : L10n.t("status_queued"))
                .font(.manrope(12, relativeTo: .caption)).foregroundStyle(NC.text2).lineLimit(1)
        case .paused:
            Text(L10n.t("status_paused")).font(.manrope(12, relativeTo: .caption)).foregroundStyle(NC.text2)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch item.status {
        case .done:
            HStack(spacing: 4) {
                Text(L10n.t("status_done")).font(.manrope(13, .bold, relativeTo: .footnote))
                IconView(icon: .check, size: 16, lineWidth: 2.4)
            }
            .foregroundStyle(NC.amber)
        case .failed:
            VStack(alignment: .trailing, spacing: 4) {
                Text(L10n.t("status_failed")).font(.manrope(12, .bold, relativeTo: .caption)).foregroundStyle(NC.error)
                Button(action: onRetry) {
                    Text(L10n.t("retry"))
                        .font(.manrope(13, .bold, relativeTo: .footnote))
                        .foregroundStyle(NC.text)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background(NC.elevated, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .frame(minHeight: 44)
            }
        case .active:
            EqualizerBars(playing: true, color: NC.brightStart, bars: 3, barWidth: 3, spacing: 2, height: 14)
                .padding(.trailing, 6)
        default:
            EmptyView()
        }
    }
}

/// Header + list for the downloads (library tab and Add screen).
struct DownloadsSection: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.metrics) private var m
    var showEmpty = true
    @State private var confirmClearAll = false

    var body: some View {
        let all = library.downloads
        let stats = downloads.stats(all)
        VStack(alignment: .leading, spacing: 10) {
            if !all.isEmpty {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("downloads"))
                            .font(.manrope(17, .bold, relativeTo: .headline))
                            .foregroundStyle(NC.text)
                        Text(stats.active > 0
                             ? L10n.f("downloads_stats", stats.done, stats.total, stats.active, Fmt.speed(stats.bytesPerSecond))
                             : L10n.f("downloads_stats_idle", stats.done, stats.total))
                            .font(.manrope(12, .semibold, relativeTo: .caption))
                            .monospacedDigit()
                            .foregroundStyle(NC.text2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 8)
                    if stats.hasPending {
                        Button {
                            Haptics.tap()
                            if stats.allPaused { downloads.resumeAll() } else { downloads.pauseAll() }
                        } label: {
                            Text(L10n.t(stats.allPaused ? "resume_all" : "pause_all"))
                                .font(.manrope(13, .bold, relativeTo: .footnote))
                                .foregroundStyle(NC.text)
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 36)
                                .background(NC.surface, in: Capsule())
                        }
                        .buttonStyle(PressScaleStyle())
                        .frame(minHeight: 44)
                    } else {
                        Button { downloads.clearFinished() } label: {
                            Text(L10n.t("clear_finished"))
                                .font(.manrope(13, .bold, relativeTo: .footnote))
                                .foregroundStyle(NC.text2)
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 36)
                                .background(NC.surface, in: Capsule())
                        }
                        .buttonStyle(PressScaleStyle())
                        .frame(minHeight: 44)
                    }
                    Button { confirmClearAll = true } label: {
                        IconView(icon: .trash, size: 17)
                            .foregroundStyle(NC.error)
                            .frame(width: 36, height: 36)
                            .background(NC.surface, in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel(L10n.t("clear_all"))
                    .confirmationDialog(L10n.t("clear_all_title"), isPresented: $confirmClearAll, titleVisibility: .visible) {
                        Button(L10n.t("clear_all"), role: .destructive) { downloads.clearAll() }
                        Button(L10n.t("cancel"), role: .cancel) {}
                    } message: {
                        Text(L10n.t("clear_all_body"))
                    }
                }
                if stats.hasPending {
                    ThinProgress(fraction: stats.fraction, height: 4)
                }
            }
            if all.isEmpty && showEmpty {
                Text(L10n.t("downloads_empty"))
                    .font(.manrope(14, relativeTo: .body))
                    .foregroundStyle(NC.text2)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 40)
            }
            LazyVStack(spacing: 2) {
                ForEach(all) { item in
                    DownloadRow(item: item, progress: item.id.flatMap { downloads.progress[$0] }) {
                        if let id = item.id { downloads.retry(id) }
                    }
                }
            }
        }
    }
}
