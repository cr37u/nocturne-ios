import SwiftUI
import UIKit

final class AddMusicModel: ObservableObject {
    enum Phase {
        case idle
        case resolving
        case resolved(ResolvedLink, newCount: Int, existing: Int)
        case failed(ErrorKind)
    }

    @Published var link: String = ""
    @Published private(set) var phase: Phase = .idle
    private var task: Task<Void, Never>?
    private var resolvedFor: String?

    func resolve(_ raw: String) {
        guard let url = YouTubeLinks.extractURL(from: raw), let parsed = YouTubeLinks.parse(url) else {
            phase = raw.trimmingCharacters(in: .whitespaces).isEmpty ? .idle : .failed(.invalidLink)
            return
        }
        link = url
        guard resolvedFor != parsed.canonicalURL else { return }
        resolvedFor = parsed.canonicalURL
        task?.cancel()
        phase = .resolving
        task = Task { [weak self] in
            do {
                let resolved = try await YouTubeCatalog.shared.resolve(parsed)
                let known = Library.shared.knownVideoIds()
                let existing = resolved.items.filter { known.contains($0.videoId) }.count
                await MainActor.run {
                    guard let self, !Task.isCancelled else { return }
                    self.phase = .resolved(resolved, newCount: resolved.items.count - existing, existing: existing)
                }
            } catch {
                await MainActor.run {
                    guard let self, !Task.isCancelled else { return }
                    self.resolvedFor = nil
                    self.phase = .failed(ErrorKind.from(error))
                }
            }
        }
    }

    func reset() {
        task?.cancel()
        resolvedFor = nil
        phase = .idle
        link = ""
    }
}

/// "Adaugă muzică": link field, detected playlist / video card, downloads list.
struct AddMusicView: View {
    let initialLink: String?
    @StateObject private var model = AddMusicModel()
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.metrics) private var m
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    IconButton(icon: .chevronLeft, label: L10n.t("cd_back")) { dismiss() }
                    Text(L10n.t("add_music"))
                        .font(.manrope(22, .extraBold, relativeTo: .title2))
                        .foregroundStyle(NC.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("link_label"))
                        .font(.manrope(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(NC.text2)
                    HStack(spacing: 8) {
                        IconView(icon: .link, size: 17).foregroundStyle(NC.text2)
                        TextField("", text: $model.link, prompt: Text(L10n.t("link_placeholder")).foregroundColor(NC.placeholder))
                            .font(.manrope(14, relativeTo: .callout))
                            .foregroundStyle(NC.text)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .submitLabel(.go)
                            .focused($focused)
                            .onSubmit { model.resolve(model.link) }
                            .accessibilityIdentifier("add-link-field")
                        if !model.link.isEmpty {
                            Button { model.reset() } label: {
                                IconView(icon: .xmark, size: 15).foregroundStyle(NC.text2).frame(width: 36, height: 44)
                            }
                            .accessibilityLabel(L10n.t("cd_clear"))
                        }
                        GradientButton(title: L10n.t("paste")) {
                            Haptics.tap()
                            if let s = UIPasteboard.general.string, YouTubeLinks.extractURL(from: s) != nil {
                                model.resolve(s)
                            } else {
                                app.showToast(L10n.t("clipboard_empty"))
                            }
                        }
                    }
                    .padding(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 5))
                    .background(NC.surface, in: RoundedRectangle(cornerRadius: Radius.input, style: .continuous))
                }
                phaseView
                DownloadsSection(showEmpty: false)
            }
            .padding(.horizontal, m.hPad)
            .padding(.top, m.topPad)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(NC.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if let initialLink, !initialLink.isEmpty { model.resolve(initialLink) }
        }
        .accessibilityIdentifier("add-music")
    }

    @ViewBuilder private var phaseView: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .resolving:
            HStack(spacing: 12) {
                ProgressView().tint(NC.brightStart)
                Text(L10n.t("resolving")).font(.manrope(14, .semibold, relativeTo: .callout)).foregroundStyle(NC.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(NC.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        case .failed(let kind):
            HStack(alignment: .top, spacing: 12) {
                IconView(icon: .info, size: 20).foregroundStyle(NC.error)
                Text(kind.message).font(.manrope(14, .semibold, relativeTo: .callout)).foregroundStyle(NC.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if kind.retryable {
                    Button { model.resolve(model.link) } label: {
                        Text(L10n.t("retry")).font(.manrope(13, .bold)).foregroundStyle(NC.amber).frame(minHeight: 44)
                    }
                }
            }
            .padding(18)
            .background(NC.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        case .resolved(let resolved, let newCount, let existing):
            detectedCard(resolved, newCount: newCount, existing: existing)
        }
    }

    private func detectedCard(_ r: ResolvedLink, newCount: Int, existing: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ArtworkView(file: nil, seed: r.youtubePlaylistId ?? r.items.first?.videoId, size: 64, radius: 16)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(r.isPlaylist ? "playlist_detected" : "video_detected"))
                        .font(.manrope(11, .bold, relativeTo: .caption2))
                        .tracking(1.3)
                        .foregroundStyle(NC.amber)
                    Text(r.title)
                        .font(.manrope(17, .bold, relativeTo: .headline))
                        .foregroundStyle(NC.text)
                        .lineLimit(2)
                    Text(summary(r, existing: existing))
                        .font(.manrope(13, relativeTo: .footnote))
                        .foregroundStyle(NC.text2)
                        .lineLimit(2)
                }
            }
            if newCount > 0 {
                GradientButton(
                    title: r.isPlaylist ? L10n.p("download_new", newCount) : L10n.t("download_one"),
                    height: 50, radius: 16, fontSize: 15, icon: .download, expand: true
                ) {
                    Haptics.tap()
                    let added = DownloadManager.shared.enqueue(r)
                    app.showToast(r.isPlaylist && added > 0 ? L10n.p("added_to_downloads", added) : L10n.p("added_to_downloads", max(added, 1)))
                    model.reset()
                }
                .accessibilityIdentifier("download-button")
            } else {
                HStack(spacing: 8) {
                    IconView(icon: .check, size: 16, lineWidth: 2.4).foregroundStyle(NC.amber)
                    Text(L10n.t("all_in_library")).font(.manrope(14, .semibold, relativeTo: .callout)).foregroundStyle(NC.text)
                }
                if r.isPlaylist {
                    Button {
                        DownloadManager.shared.enqueue(r)
                        app.showToast(L10n.t("playlist_imported"))
                        model.reset()
                    } label: {
                        Text(L10n.t("import_playlist"))
                            .font(.manrope(14, .bold, relativeTo: .callout))
                            .foregroundStyle(NC.text)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(NC.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.97))
                }
            }
        }
        .padding(16)
        .background(NC.surface, in: RoundedRectangle(cornerRadius: Radius.cardLarge, style: .continuous))
    }

    /// "24 melodii · 1 h 32 min · 3 deja în bibliotecă"
    private func summary(_ r: ResolvedLink, existing: Int) -> String {
        var parts: [String] = []
        if r.isPlaylist { parts.append(L10n.p("songs_count", r.items.count)) }
        if r.totalSeconds > 0 { parts.append(Fmt.longDuration(Double(r.totalSeconds))) }
        if r.items.first.map({ $0.artist }) != nil && !r.isPlaylist { parts.append(r.items[0].artist) }
        if existing > 0 { parts.append(L10n.p("already_in_library", existing)) }
        return parts.joined(separator: " · ")
    }
}
