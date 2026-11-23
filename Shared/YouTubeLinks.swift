import Foundation

enum ParsedLink: Equatable {
    case video(String)
    case playlist(String)

    /// Auto-generated YouTube Mix ("RD…"): endless, so it is capped when importing.
    var isMix: Bool {
        if case .playlist(let id) = self { return id.hasPrefix("RD") }
        return false
    }

    var canonicalURL: String {
        switch self {
        case .video(let id):
            return YouTubeLinks.videoURL(id)
        case .playlist(let id):
            let seed = String(id.suffix(11))
            if isMix && seed.count == 11 {
                return "https://www.youtube.com/watch?v=\(seed)&list=\(id)"
            }
            return "https://www.youtube.com/playlist?list=\(id)"
        }
    }

    /// Seed video of a Mix ("RD<videoId>").
    var mixSeed: String? {
        guard isMix, case .playlist(let id) = self else { return nil }
        let seed = String(id.suffix(11))
        return YouTubeLinks.isVideoId(seed) ? seed : nil
    }
}

/// YouTube link parsing (watch?v=, youtu.be, music.youtube.com, shorts, live, embed, list=…),
/// a direct port of the Android `YouTubeLinks`.
enum YouTubeLinks {
    private static let hosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be", "www.youtu.be",
    ]

    static func videoURL(_ id: String) -> String { "https://www.youtube.com/watch?v=\(id)" }

    static func isVideoId(_ s: String) -> Bool {
        s.count == 11 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    static func isListId(_ s: String) -> Bool {
        s.count >= 10 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    /// Finds the first YouTube URL inside arbitrary text ("Title – https://youtu.be/…").
    static func extractURL(from text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let pattern = #"https?://[^\s<>"']+"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let ns = text as NSString
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                var candidate = ns.substring(with: m.range)
                while let last = candidate.last, ".,)]".contains(last) { candidate.removeLast() }
                if parse(candidate) != nil { return candidate }
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains(" "), parse("https://\(trimmed)") != nil { return "https://\(trimmed)" }
        return nil
    }

    static func parse(_ raw: String?) -> ParsedLink? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        s = s.replacingOccurrences(of: " ", with: "%20")
        guard let comps = URLComponents(string: s), let host = comps.host?.lowercased(), hosts.contains(host) else {
            return nil
        }
        let segments = comps.path.split(separator: "/").map(String.init)
        var query: [String: String] = [:]
        for item in comps.queryItems ?? [] where query[item.name] == nil {
            query[item.name] = item.value ?? ""
        }
        let isShortHost = host.hasSuffix("youtu.be")

        // Playlists and YouTube Mixes (list=RD…).
        if let list = query["list"], isListId(list) {
            let first = segments.first
            if first == nil || first == "playlist" || first == "watch" || isShortHost {
                return .playlist(list)
            }
        }

        let id: String?
        if isShortHost {
            id = segments.first
        } else if segments.first == "watch" {
            id = query["v"]
        } else if let first = segments.first, ["shorts", "live", "embed", "v"].contains(first) {
            id = segments.count > 1 ? segments[1] : nil
        } else {
            id = query["v"]
        }
        if let id, isVideoId(id) { return .video(id) }
        return nil
    }

    static func videoId(fromURL url: String) -> String? {
        if case .video(let id)? = parse(url) { return id }
        guard let comps = URLComponents(string: url), let v = comps.queryItems?.first(where: { $0.name == "v" })?.value else {
            return nil
        }
        return isVideoId(v) ? v : nil
    }
}
