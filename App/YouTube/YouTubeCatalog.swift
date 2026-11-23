import Foundation

struct RemoteItem: Hashable {
    let videoId: String
    let title: String
    let artist: String
    let durationSec: Int
    let thumbnailUrl: String?

    var url: String { YouTubeLinks.videoURL(videoId) }
}

struct ResolvedLink {
    let isPlaylist: Bool
    let title: String
    let youtubePlaylistId: String?
    let items: [RemoteItem]

    var totalSeconds: Int { items.reduce(0) { $0 + $1.durationSec } }
}

/// Metadata provider (titles, playlists). Separate from `StreamResolver` so either can be swapped.
protocol CatalogProvider {
    func resolve(_ link: ParsedLink) async throws -> ResolvedLink
    func videoMetadata(_ videoId: String) async throws -> RemoteItem
    func videoLength(_ videoId: String) async -> Int
}

/// Uses YouTube's public web endpoints (InnerTube `browse` / `next`, oEmbed) with a FIXED metadata
/// language (en / US) — independent of the UI language — so titles are stable. oEmbed returns the
/// original (untranslated) title, which is preferred at download time.
final class YouTubeCatalog: CatalogProvider {
    static let shared = YouTubeCatalog()

    static let mixLimit = 50
    private let clientVersion = "2.20251120.01.00"
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36",
            "Accept-Language": "en-US,en;q=0.9",
        ]
        return URLSession(configuration: c)
    }()

    func resolve(_ link: ParsedLink) async throws -> ResolvedLink {
        switch link {
        case .video(let id):
            let item = try await videoMetadata(id)
            return ResolvedLink(isPlaylist: false, title: item.title, youtubePlaylistId: nil, items: [item])
        case .playlist(let listId):
            if let seed = link.mixSeed {
                return try await resolveMix(listId: listId, seed: seed)
            }
            return try await resolvePlaylist(listId)
        }
    }

    // MARK: single video

    func videoMetadata(_ videoId: String) async throws -> RemoteItem {
        if let o = try? await oEmbed(videoId) { return o }
        // Fallback (embedding disabled etc.): the watch-next payload.
        let json = try await post("next", body: ["videoId": videoId])
        var title: String?
        var owner: String?
        Self.walk(json) { key, value in
            if key == "videoPrimaryInfoRenderer", let d = value as? [String: Any], title == nil { title = Self.text(d["title"]) }
            if key == "videoOwnerRenderer", let d = value as? [String: Any], owner == nil { owner = Self.text(d["title"]) }
        }
        guard let title, !title.isEmpty else { throw ErrorKind.unavailable }
        return RemoteItem(videoId: videoId, title: title, artist: Self.cleanArtist(owner), durationSec: 0,
                          thumbnailUrl: Self.thumbnail(videoId))
    }

    private func oEmbed(_ videoId: String) async throws -> RemoteItem {
        var comps = URLComponents(string: "https://www.youtube.com/oembed")!
        comps.queryItems = [.init(name: "format", value: "json"), .init(name: "url", value: YouTubeLinks.videoURL(videoId))]
        let (data, response) = try await session.data(from: comps.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = obj["title"] as? String else {
            throw ErrorKind.unavailable
        }
        return RemoteItem(videoId: videoId, title: title, artist: Self.cleanArtist(obj["author_name"] as? String),
                          durationSec: 0, thumbnailUrl: Self.thumbnail(videoId))
    }

    /// Real length of a video in seconds, as YouTube reports it (0 when unknown).
    func videoLength(_ videoId: String) async -> Int {
        guard let json = try? await post("player", body: ["videoId": videoId]),
              let details = (json as? [String: Any])?["videoDetails"] as? [String: Any] else { return 0 }
        if let s = details["lengthSeconds"] as? String, let v = Int(s) { return v }
        return (details["lengthSeconds"] as? NSNumber)?.intValue ?? 0
    }

    // MARK: playlists (every page)

    private func resolvePlaylist(_ listId: String) async throws -> ResolvedLink {
        var json = try await post("browse", body: ["browseId": "VL" + listId])
        var title = Self.playlistTitle(json) ?? "YouTube"
        var items: [RemoteItem] = []
        var seen = Set<String>()
        var guardCount = 0
        while true {
            let (found, token) = Self.collect(json)
            for item in found where !seen.contains(item.videoId) {
                seen.insert(item.videoId)
                items.append(item)
            }
            guardCount += 1
            guard let token, guardCount < 200 else { break }
            try Task.checkCancellation()
            json = try await post("browse", body: ["continuation": token])
            if title == "YouTube", let t = Self.playlistTitle(json) { title = t }
        }
        if items.isEmpty { throw ErrorKind.unavailable }
        return ResolvedLink(isPlaylist: true, title: title, youtubePlaylistId: listId, items: items)
    }

    /// YouTube Mix ("RD…"): the watch-next panel, followed until it repeats or hits the cap.
    private func resolveMix(listId: String, seed: String) async throws -> ResolvedLink {
        var items: [RemoteItem] = []
        var seen = Set<String>()
        var videoId = seed
        var title = "Mix"
        for _ in 0..<6 {
            let json = try await post("next", body: ["videoId": videoId, "playlistId": listId])
            if let t = Self.firstValue(json, key: "playlist").flatMap({ ($0 as? [String: Any])?["title"] }) as? String {
                title = t
            }
            let (found, _) = Self.collect(json)
            let before = items.count
            for item in found where !seen.contains(item.videoId) && items.count < Self.mixLimit {
                seen.insert(item.videoId)
                items.append(item)
            }
            guard items.count < Self.mixLimit, items.count > before, let last = items.last else { break }
            videoId = last.videoId
        }
        if items.isEmpty { throw ErrorKind.unavailable }
        return ResolvedLink(isPlaylist: true, title: title, youtubePlaylistId: listId, items: items)
    }

    // MARK: InnerTube transport

    private func post(_ endpoint: String, body: [String: Any]) async throws -> Any {
        var req = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/\(endpoint)?prettyPrint=false")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        req.setValue("1", forHTTPHeaderField: "X-YouTube-Client-Name")
        req.setValue(clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        var payload = body
        payload["context"] = [
            "client": [
                "clientName": "WEB",
                "clientVersion": clientVersion,
                "hl": "en",
                "gl": "US",
            ],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 || code == 400 { throw ErrorKind.unavailable }
        if code == 429 { throw ErrorKind.bot }
        guard (200..<300).contains(code) else { throw ErrorKind.generic }
        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: JSON helpers (layout-agnostic: walk the whole tree)

    static func walk(_ node: Any, _ visit: (String, Any) -> Void) {
        if let dict = node as? [String: Any] {
            for (k, v) in dict {
                visit(k, v)
                walk(v, visit)
            }
        } else if let arr = node as? [Any] {
            for v in arr { walk(v, visit) }
        }
    }

    static func firstValue(_ node: Any, key: String) -> Any? {
        var found: Any?
        walk(node) { k, v in if found == nil && k == key { found = v } }
        return found
    }

    static func text(_ node: Any?) -> String? {
        guard let d = node as? [String: Any] else { return node as? String }
        if let s = d["simpleText"] as? String { return s }
        if let s = d["content"] as? String { return s }
        if let runs = d["runs"] as? [[String: Any]] {
            let s = runs.compactMap { $0["text"] as? String }.joined()
            return s.isEmpty ? nil : s
        }
        return nil
    }

    static func parseClock(_ s: String?) -> Int {
        guard let s else { return 0 }
        var total = 0
        for part in s.split(separator: ":") {
            guard let v = Int(part.trimmingCharacters(in: .whitespaces)) else { return 0 }
            total = total * 60 + v
        }
        return total
    }

    static func playlistTitle(_ json: Any) -> String? {
        if let m = firstValue(json, key: "playlistMetadataRenderer") as? [String: Any], let t = m["title"] as? String { return t }
        if let h = firstValue(json, key: "playlistHeaderRenderer") as? [String: Any], let t = text(h["title"]) { return t }
        if let h = firstValue(json, key: "pageHeaderRenderer") as? [String: Any], let t = h["pageTitle"] as? String { return t }
        return nil
    }

    /// Collects playlist entries (classic + panel + lockup layouts) and the next continuation token.
    static func collect(_ json: Any) -> ([RemoteItem], String?) {
        var items: [RemoteItem] = []
        var token: String?
        walk(json) { key, value in
            guard let d = value as? [String: Any] else { return }
            switch key {
            case "playlistVideoRenderer", "playlistPanelVideoRenderer":
                guard let id = d["videoId"] as? String, YouTubeLinks.isVideoId(id),
                      let title = text(d["title"]) else { return }
                if d["isPlayable"] as? Bool == false { return }
                let artist = text(d["shortBylineText"]) ?? text(d["longBylineText"]) ?? text(d["ownerText"])
                let seconds = (d["lengthSeconds"] as? String).flatMap(Int.init) ?? parseClock(text(d["lengthText"]))
                items.append(RemoteItem(videoId: id, title: title, artist: cleanArtist(artist), durationSec: seconds,
                                        thumbnailUrl: thumbnail(id)))
            case "lockupViewModel":
                guard let id = d["contentId"] as? String, YouTubeLinks.isVideoId(id) else { return }
                let meta = (d["metadata"] as? [String: Any])?["lockupMetadataViewModel"] as? [String: Any]
                guard let title = text(meta?["title"]) else { return }
                items.append(RemoteItem(videoId: id, title: title, artist: "YouTube", durationSec: 0, thumbnailUrl: thumbnail(id)))
            case "continuationCommand":
                if token == nil, let t = d["token"] as? String { token = t }
            case "nextContinuationData":
                if token == nil, let t = d["continuation"] as? String { token = t }
            default:
                break
            }
        }
        return (items, token)
    }

    static func thumbnail(_ id: String) -> String { "https://i.ytimg.com/vi/\(id)/hqdefault.jpg" }

    /// "Artist - Topic" channels → "Artist"; strips VEVO.
    static func cleanArtist(_ raw: String?) -> String {
        var s = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix(" - Topic") { s = String(s.dropLast(8)) }
        if s.hasSuffix("VEVO") { s = String(s.dropLast(4)) }
        s = s.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "YouTube" : s
    }
}
