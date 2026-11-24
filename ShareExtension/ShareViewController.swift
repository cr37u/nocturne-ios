import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Share → Nocturne (YouTube app, Safari, …): finds the YouTube link, stores it in the App Group
/// and opens Nocturne at "Adaugă muzică" via nocturne://add?url=… (works without an App Group too).
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        FontRegistry.registerIfNeeded()
        L10n.applyStored()
        view.backgroundColor = .clear
        let host = UIHostingController(rootView: ShareView(model: model,
                                                           download: { [weak self] in self?.openApp(autoDownload: true) },
                                                           open: { [weak self] in self?.openApp(autoDownload: false) },
                                                           close: { [weak self] in self?.finish() }))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        extractLink()
    }

    private func extractLink() {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        let group = DispatchGroup()
        let box = CandidateBox(items.compactMap { $0.attributedContentText?.string })
        for p in providers {
            for type in [UTType.url.identifier, UTType.plainText.identifier] where p.hasItemConformingToTypeIdentifier(type) {
                group.enter()
                p.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                    var text: String?
                    if let url = item as? URL { text = url.absoluteString }
                    else if let s = item as? String { text = s }
                    else if let d = item as? Data { text = String(data: d, encoding: .utf8) }
                    if let text { box.append(text) }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            let link = box.all.lazy.compactMap { YouTubeLinks.extractURL(from: $0) }.first
            self.model.link = link
            self.model.state = link == nil ? .noLink : .ready
            if let link { AppGroup.pushPendingLink(link) }
        }
    }

    /// `autoDownload`: Nocturne starts the download immediately instead of showing "Adaugă muzică".
    private func openApp(autoDownload: Bool) {
        guard let link = model.link else { finish(); return }
        var comps = URLComponents()
        comps.scheme = "nocturne"
        comps.host = "add"
        comps.queryItems = [URLQueryItem(name: "url", value: link)]
        if autoDownload { comps.queryItems?.append(URLQueryItem(name: "auto", value: "1")) }
        if let url = comps.url { openURL(url) }
        // The pending link in the App Group would add it twice: the URL handles it.
        _ = AppGroup.popPendingLinks()
        finish()
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    /// Share extensions can't call UIApplication.open directly; walk the responder chain.
    private func openURL(_ url: URL) {
        var responder: UIResponder? = self
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        while let r = responder {
            if r.responds(to: selector), r !== self, NSStringFromClass(type(of: r)).contains("UIApplication") {
                typealias OpenFn = @convention(c) (AnyObject, Selector, URL, NSDictionary, Any?) -> Void
                let imp = r.method(for: selector)
                let fn = unsafeBitCast(imp, to: OpenFn.self)
                fn(r, selector, url, NSDictionary(), nil)
                return
            }
            responder = r.next
        }
    }
}

/// Thread-safe collector for item-provider results.
final class CandidateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String]

    init(_ initial: [String]) { items = initial }

    func append(_ s: String) {
        lock.lock(); items.append(s); lock.unlock()
    }

    var all: [String] {
        lock.lock(); defer { lock.unlock() }
        return items
    }
}

final class ShareModel: ObservableObject {
    enum State { case loading, ready, noLink }
    @Published var state: State = .loading
    @Published var link: String?
}

private struct ShareView: View {
    @ObservedObject var model: ShareModel
    let download: () -> Void
    let open: () -> Void
    let close: () -> Void

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(NC.primary)
                        IconView(icon: .moon, size: 18).foregroundStyle(NC.text)
                    }
                    .frame(width: 34, height: 34)
                    Text(verbatim: "Nocturne").font(.manrope(20, .extraBold)).foregroundStyle(NC.text)
                    Spacer()
                    Button(action: close) {
                        IconView(icon: .xmark, size: 16).foregroundStyle(NC.text2).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(L10n.t("cd_close"))
                }
                switch model.state {
                case .loading:
                    ProgressView().tint(NC.brightStart).frame(maxWidth: .infinity, minHeight: 80)
                case .noLink:
                    Text(L10n.t("share_no_link"))
                        .font(.manrope(15, .semibold)).foregroundStyle(NC.text)
                    Button(action: close) {
                        Text(L10n.t("share_done")).font(.manrope(15, .bold)).foregroundStyle(NC.text)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(NC.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                case .ready:
                    Text(L10n.t("share_title"))
                        .font(.manrope(18, .extraBold)).foregroundStyle(NC.text)
                    Text(model.link ?? "")
                        .font(.manrope(13)).foregroundStyle(NC.text2).lineLimit(2)
                    Button(action: download) {
                        HStack(spacing: 8) {
                            IconView(icon: .download, size: 18)
                            Text(L10n.t("share_download_label")).font(.manrope(15, .bold))
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(NC.text)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(NC.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    Button(action: open) {
                        Text(L10n.t("share_open")).font(.manrope(15, .bold)).foregroundStyle(NC.text)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(NC.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
            .padding(20)
            .background(NC.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(12)
        }
        .preferredColorScheme(.dark)
    }
}
