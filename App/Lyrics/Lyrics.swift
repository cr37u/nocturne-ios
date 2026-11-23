import Foundation

struct LyricLine: Codable, Hashable {
    let time: Double // seconds
    let text: String
}

enum Lyrics: Equatable {
    case synced([LyricLine])
    case plain(String)
    case instrumental
    case notFound
}

/// Lyrics from LRCLIB (https://lrclib.net — free, no account, no key): fetched the first time,
/// then cached in Application Support so they are available offline (same as Android).
enum LyricsRepository {
    private static let base = "https://lrclib.net/api"
    private static let notFoundTTL: TimeInterval = 7 * 24 * 3600

    private struct Cached: Codable {
        var kind: String
        var lines: [LyricLine]?
        var text: String?
    }

    private static func cacheURL(_ trackId: String) -> URL {
        Storage.lyricsDir.appendingPathComponent("\(trackId).json")
    }

    /// Cached result only (no network). "Not found" is re-checked after a week.
    static func cached(_ track: Track) -> Lyrics? {
        let url = cacheURL(track.id)
        guard let data = try? Data(contentsOf: url), let c = try? JSONDecoder().decode(Cached.self, from: data) else { return nil }
        if c.kind == "notfound",
           let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
           Date().timeIntervalSince(date) > notFoundTTL {
            return nil
        }
        switch c.kind {
        case "synced": return .synced(c.lines ?? [])
        case "plain": return .plain(c.text ?? "")
        case "instrumental": return .instrumental
        default: return .notFound
        }
    }

    /// Cache first, then LRCLIB. Throws when offline and nothing is cached.
    static func load(_ track: Track, forceRefresh: Bool = false) async throws -> Lyrics {
        if !forceRefresh, let c = cached(track) { return c }
        let result = try await fetch(track)
        let c: Cached
        switch result {
        case .synced(let lines): c = Cached(kind: "synced", lines: lines, text: nil)
        case .plain(let text): c = Cached(kind: "plain", lines: nil, text: text)
        case .instrumental: c = Cached(kind: "instrumental", lines: nil, text: nil)
        case .notFound: c = Cached(kind: "notfound", lines: nil, text: nil)
        }
        if let data = try? JSONEncoder().encode(c) { try? data.write(to: cacheURL(track.id), options: .atomic) }
        return result
    }

    private static func fetch(_ track: Track) async throws -> Lyrics {
        let (artist, title) = SongQuery.from(title: track.title, channel: track.artist)
        let duration = Int(track.duration)

        // 1. Exact signature: artist + title + duration (±2 s).
        if !artist.isEmpty {
            var comps = URLComponents(string: "\(base)/get")!
            comps.queryItems = [.init(name: "artist_name", value: artist), .init(name: "track_name", value: title)]
            if duration > 0 { comps.queryItems?.append(.init(name: "duration", value: String(duration))) }
            if let body = try await request(comps.url!),
               let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let parsed = parse(obj) {
                return parsed
            }
        }

        // 2. Free search, best duration match.
        var search = URLComponents(string: "\(base)/search")!
        search.queryItems = [.init(name: "q", value: [artist, title].filter { !$0.isEmpty }.joined(separator: " "))]
        guard let body = try await request(search.url!),
              let arr = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]] else { return .notFound }
        func dur(_ o: [String: Any]) -> Double { (o["duration"] as? Double) ?? Double(o["duration"] as? Int ?? 0) }
        let candidates = arr
            .filter { duration <= 0 || abs(dur($0) - Double(duration)) <= 8 }
            .sorted { a, b in
                let sa = (a["syncedLyrics"] as? String) != nil, sb = (b["syncedLyrics"] as? String) != nil
                if sa != sb { return sa }
                return abs(dur(a) - Double(duration)) < abs(dur(b) - Double(duration))
            }
        return candidates.first.flatMap(parse) ?? .notFound
    }

    /// Body for 200, nil for 404; throws for network / server errors.
    private static func request(_ url: URL) async throws -> Data? {
        var req = URLRequest(url: url)
        req.setValue("Nocturne iOS (https://github.com/cr37u/nocturne-ios)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return nil }
        guard (200..<300).contains(code) else { throw URLError(.badServerResponse) }
        return data
    }

    private static func parse(_ o: [String: Any]) -> Lyrics? {
        if o["instrumental"] as? Bool == true { return .instrumental }
        if let synced = o["syncedLyrics"] as? String, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = Lrc.parse(synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let plain = o["plainLyrics"] as? String, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .plain(plain.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}

/// LRC "[mm:ss.xx] text" parser (several timestamps per line supported).
enum Lrc {
    static func parse(_ lrc: String) -> [LyricLine] {
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#) else { return [] }
        var out: [LyricLine] = []
        for raw in lrc.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.location + last.range.length).trimmingCharacters(in: .whitespaces)
            for m in matches {
                let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let sec = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var frac = 0.0
                if m.range(at: 3).location != NSNotFound {
                    let f = ns.substring(with: m.range(at: 3))
                    frac = (Double(f) ?? 0) / pow(10, Double(f.count))
                }
                out.append(LyricLine(time: min * 60 + sec + frac, text: text))
            }
        }
        return out.sorted { $0.time < $1.time }
    }
}

/// YouTube title → (artist, song): "Kavinsky - Nightcall (Official Audio)" → ("Kavinsky", "Nightcall").
enum SongQuery {
    static func from(title: String, channel: String) -> (String, String) {
        func replace(_ s: String, _ pattern: String, _ with: String = "") -> String {
            guard let r = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return s }
            return r.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: with)
        }
        let noise = #"\s*[(\[][^)\]]*(official|video|audio|lyric|lyrics|visualizer|clip|премьера|клип|hd|4k|remaster|live|explicit)[^)\]]*[)\]]"#
        let feat = #"\s+(ft\.?|feat\.?|featuring)\s+.*$"#
        var t = replace(title, noise)
        t = replace(t, #"\s{2,}"#, " ").trimmingCharacters(in: .whitespaces)
        var artist = replace(channel, #"\s*-\s*Topic$"#).trimmingCharacters(in: .whitespaces)
        if let r = try? NSRegularExpression(pattern: #"\s[-–—]\s"#),
           let m = r.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length)) {
            let ns = t as NSString
            artist = ns.substring(to: m.range.location).trimmingCharacters(in: .whitespaces)
            t = ns.substring(from: m.range.location + m.range.length).trimmingCharacters(in: .whitespaces)
        }
        t = replace(t, feat).trimmingCharacters(in: CharacterSet(charactersIn: " \"“”«»"))
        artist = replace(artist, feat)
        if let r = try? NSRegularExpression(pattern: #"\s*,\s*|\s+(?:&|×|x|X)\s+"#),
           let m = r.firstMatch(in: artist, range: NSRange(location: 0, length: (artist as NSString).length)) {
            artist = (artist as NSString).substring(to: m.range.location)
        }
        return (artist.trimmingCharacters(in: .whitespaces), t)
    }
}
