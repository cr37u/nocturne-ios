import SwiftUI
import UIKit

/// Live language switching (no restart): the selection is stored in UserDefaults + the App Group
/// (widgets, Live Activity, Share Extension follow it), and views observing this object re-render.
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published private(set) var selection: AppLanguage
    @Published private(set) var code: String

    var locale: Locale { L10n.current.locale }

    private init() {
        let stored = L10n.storedSelection()
        selection = stored
        L10n.apply(stored)
        code = L10n.current.code
        persist()
    }

    func select(_ language: AppLanguage) {
        selection = language
        L10n.apply(language)
        code = L10n.current.code
        persist()
        SystemSurfaces.shared.refreshAll()
    }

    /// Re-resolves "system" (the iOS per-app language may have changed while in the background).
    func refreshSystemLanguage() {
        guard selection == .system else { return }
        L10n.apply(.system)
        if code != L10n.current.code {
            code = L10n.current.code
            persist()
            SystemSurfaces.shared.refreshAll()
        }
    }

    private func persist() {
        UserDefaults.standard.set(selection.rawValue, forKey: L10n.storageKey)
        AppGroup.defaults?.set(selection.rawValue, forKey: L10n.storageKey)
        AppGroup.defaults?.set(L10n.current.code, forKey: L10n.resolvedKey)
    }
}

enum Route: Hashable {
    case playlist(Int64)
    case favorites
    case settings
    case add(String?)
}

enum LibraryTab: Int, CaseIterable {
    case songs, playlists, downloads

    var key: String {
        switch self {
        case .songs: return "tab_songs"
        case .playlists: return "tab_playlists"
        case .downloads: return "tab_downloads"
        }
    }
}

/// Navigation, sheets and toasts shared by all screens.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var path: [Route] = []
    @Published var tab: LibraryTab = .songs
    @Published var nowPlayingOpen = false
    @Published var toast: String?
    @Published var clipboardLink: String?

    // Sheets / dialogs
    @Published var playlistPickerTrack: Track?
    @Published var editTrack: Track?
    @Published var deleteTrack: Track?
    @Published var queueOpen = false
    @Published var lyricsOpen = false

    private var toastTask: Task<Void, Never>?

    func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.3)) { toast = text }
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
    }

    func openAdd(_ link: String?) {
        nowPlayingOpen = false
        if case .add? = path.last {
            path.removeLast()
        }
        path.append(.add(link))
    }

    /// "Descarcă în Nocturne" from Share: resolve the link and queue it right away, staying in the
    /// library (the Downloads tab shows the progress).
    func quickDownload(_ raw: String) {
        guard let url = YouTubeLinks.extractURL(from: raw), let parsed = YouTubeLinks.parse(url) else {
            showToast(L10n.t("error_invalid_link"))
            return
        }
        nowPlayingOpen = false
        path.removeAll()
        tab = .downloads
        showToast(L10n.t("quick_download_started"))
        Task { @MainActor in
            do {
                let resolved = try await YouTubeCatalog.shared.resolve(parsed)
                let added = DownloadManager.shared.enqueue(resolved)
                if added == 0 {
                    self.showToast(L10n.t(resolved.isPlaylist ? "playlist_imported" : "all_in_library"))
                } else {
                    self.showToast(L10n.p("added_to_downloads", added))
                }
            } catch {
                self.showToast(ErrorKind.from(error).message)
            }
        }
    }

    /// nocturne://add?url=… (Share Extension, widget "Adaugă link") and nocturne://player.
    func handle(url: URL) {
        guard url.scheme == "nocturne" else { return }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        switch url.host {
        case "add":
            let link = comps?.queryItems?.first(where: { $0.name == "url" })?.value
            if comps?.queryItems?.contains(where: { $0.name == "auto" && $0.value == "1" }) == true, let link {
                quickDownload(link)
            } else {
                openAdd(link)
            }
        case "player":
            if PlayerEngine.shared.hasTrack { nowPlayingOpen = true }
        default:
            break
        }
    }
}

@MainActor
enum Haptics {
    private static let light: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        return g
    }()
    private static let softGenerator: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.prepare()
        return g
    }()

    static func tap() {
        light.impactOccurred()
        light.prepare()
    }

    static func soft() {
        softGenerator.impactOccurred()
        softGenerator.prepare()
    }
}
