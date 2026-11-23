import Foundation

/// Shared container between the app, the widgets / Live Activity extension and the Share Extension.
///
/// Sideloading tools may rename the group when they re-sign the app, so the identifier is found
/// at runtime: the one from Info.plist (`NCAppGroup`) first, then `group.<app bundle id>`.
/// When no group is usable everything degrades gracefully: widgets show "Deschide Nocturne",
/// the Share Extension hands the link over through the `nocturne://add` URL, the app works normally.
enum AppGroup {
    static let identifier: String? = {
        var candidates: [String] = []
        if let fromPlist = Bundle.main.object(forInfoDictionaryKey: "NCAppGroup") as? String,
           !fromPlist.isEmpty, !fromPlist.contains("$(") {
            candidates.append(fromPlist)
        }
        if let appId = appBundleIdentifier {
            candidates.append("group.\(appId)")
        }
        for id in candidates {
            guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else { continue }
            // Make sure we can really write there (an unsigned / re-signed build may not be entitled).
            let probe = url.appendingPathComponent(".probe")
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try Data("ok".utf8).write(to: probe, options: .atomic)
                return id
            } catch {
                continue
            }
        }
        return nil
    }()

    static var isAvailable: Bool { identifier != nil }

    static var container: URL? {
        identifier.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }

    static var defaults: UserDefaults? {
        identifier.flatMap { UserDefaults(suiteName: $0) }
    }

    /// Bundle id of the containing app (strips the extension suffix inside an .appex).
    static var appBundleIdentifier: String? {
        guard let id = Bundle.main.bundleIdentifier else { return nil }
        if Bundle.main.bundleURL.pathExtension == "appex" {
            var parts = id.split(separator: ".")
            if parts.count > 1 { parts.removeLast() }
            return parts.joined(separator: ".")
        }
        return id
    }

    // MARK: Pending links from the Share Extension

    private static let pendingKey = "pendingLinks"

    static func pushPendingLink(_ url: String) {
        guard let d = defaults else { return }
        var list = d.stringArray(forKey: pendingKey) ?? []
        if !list.contains(url) { list.append(url) }
        d.set(list, forKey: pendingKey)
    }

    static func popPendingLinks() -> [String] {
        guard let d = defaults else { return [] }
        let list = d.stringArray(forKey: pendingKey) ?? []
        d.removeObject(forKey: pendingKey)
        return list
    }
}

/// What the widgets and the Live Activity show. Written by the app on every state change.
struct NowPlayingSnapshot: Codable, Equatable {
    var trackId: String?
    var title: String
    var artist: String
    var playlist: String?
    var isPlaying: Bool
    var position: Double
    var duration: Double
    var updatedAt: Date
    var shuffle: Bool
    /// 0 = off, 1 = all, 2 = one
    var repeatMode: Int
    var nextTitle: String?
    var nextArtist: String?
    /// File name inside the App Group container (`Artwork/…`), nil = gradient placeholder.
    var artworkFile: String?

    static let key = "nowPlaying"

    static let empty = NowPlayingSnapshot(
        trackId: nil, title: "", artist: "", playlist: nil, isPlaying: false, position: 0, duration: 0,
        updatedAt: Date(), shuffle: false, repeatMode: 0, nextTitle: nil, nextArtist: nil, artworkFile: nil
    )

    var hasTrack: Bool { trackId != nil }

    /// Position extrapolated to `date` while playing.
    func position(at date: Date) -> Double {
        guard isPlaying else { return position }
        return min(duration, position + date.timeIntervalSince(updatedAt))
    }

    func progress(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return max(0, min(1, position(at: date) / duration))
    }

    static func load() -> NowPlayingSnapshot? {
        guard let data = AppGroup.defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(NowPlayingSnapshot.self, from: data)
    }

    func save() {
        guard let d = AppGroup.defaults, let data = try? JSONEncoder().encode(self) else { return }
        d.set(data, forKey: Self.key)
    }

    static func artworkURL(_ file: String?) -> URL? {
        guard let file, let c = AppGroup.container else { return nil }
        return c.appendingPathComponent("Artwork", isDirectory: true).appendingPathComponent(file)
    }
}
