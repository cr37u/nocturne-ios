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
        Storage.lyricsDir.appendingPathComponent("\(trackId).v2.json")
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

    /// Tries several artist / title spellings (title artist and channel name, "prod." / "feat." removed),
    /// then picks the best search result by title match, artist match, synced lyrics and duration.
    private static func fetch(_ track: Track) async throws -> Lyrics {
        let q = SongQuery.candidates(title: track.title, channel: track.artist)
        let duration = track.duration

        // 1. Exact signatures (fast path).
        for artist in q.artists.prefix(2) {
            for title in q.titles.prefix(2) {
                var comps = URLComponents(string: "\(base)/get")!
                comps.queryItems = [.init(name: "artist_name", value: artist), .init(name: "track_name", value: title)]
                if duration > 0 { comps.queryItems?.append(.init(name: "duration", value: String(Int(duration)))) }
                if let body = try await request(comps.url!),
                   let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                   let parsed = parse(obj) {
                    return parsed
                }
            }
        }

        // 2. Searches, collected and ranked.
        var queries: [[URLQueryItem]] = []
        if let title = q.titles.first {
            for artist in q.artists.prefix(2) {
                queries.append([.init(name: "track_name", value: title), .init(name: "artist_name", value: artist)])
            }
            for artist in q.artists.prefix(2) {
                queries.append([.init(name: "q", value: "\(artist) \(title)")])
            }
            queries.append([.init(name: "q", value: title)])
        }
        var results: [[String: Any]] = []
        for items in queries {
            var comps = URLComponents(string: "\(base)/search")!
            comps.queryItems = items
            if let body = try await request(comps.url!),
               let arr = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]] {
                results.append(contentsOf: arr)
            }
            if let best = pickBest(results, q: q, duration: duration), (best["syncedLyrics"] as? String) != nil {
                return parse(best) ?? .notFound
            }
        }
        if let best = pickBest(results, q: q, duration: duration), let parsed = parse(best) {
            return parsed
        }
        return .notFound
    }

    private static func pickBest(_ results: [[String: Any]], q: SongQuery.Candidates, duration: Double) -> [String: Any]? {
        func dur(_ o: [String: Any]) -> Double { (o["duration"] as? NSNumber)?.doubleValue ?? 0 }
        let titles = q.titles.map(SearchKey.normalize).filter { !$0.isEmpty }
        let artists = q.artists.map(SearchKey.normalize).filter { !$0.isEmpty }
        var bestScore = -Double.infinity
        var bestItem: [String: Any]?
        for o in results {
            let name = SearchKey.normalize(o["trackName"] as? String ?? "")
            let artist = SearchKey.normalize(o["artistName"] as? String ?? "")
            if name.isEmpty { continue }
            let exactTitle = titles.contains(name) || titles.contains(where: { name.hasSuffix(" - " + $0) })
            let looseTitle = titles.contains(where: { name.contains($0) || $0.contains(name) })
            if !exactTitle && !looseTitle { continue }
            let artistMatch = artists.contains(where: { artist.contains($0) || $0.contains(artist) || name.contains($0) })
            var diff = 0.0
            if duration > 0 && dur(o) > 0 { diff = abs(dur(o) - duration) }
            // Without an artist match the duration must agree closely.
            if !artistMatch && diff > 8 { continue }
            var score = exactTitle ? 40.0 : 15.0
            if artistMatch { score += 40 }
            if (o["syncedLyrics"] as? String) != nil { score += 15 }
            score -= min(30, diff / 4)
            if score > bestScore {
                bestScore = score
                bestItem = o
            }
        }
        return bestItem
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

/// YouTube title → artist / song candidates:
/// "Макс Корж — Animals prod. Insando (Official Video)" on channel "Max Korzh"
/// → artists ["Макс Корж", "Max Korzh"], titles ["Animals"].
enum SongQuery {
    struct Candidates {
        var artists: [String]
        var titles: [String]
    }

    private static func replace(_ s: String, _ pattern: String, _ with: String = "") -> String {
        guard let r = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return s }
        return r.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: with)
    }

    private static let noise = #"\s*[(\[][^)\]]*(official|video|audio|lyric|lyrics|visualizer|clip|премьера|клип|hd|4k|remaster|live|explicit|mood|prod)[^)\]]*[)\]]"#
    private static let feat = #"\s+(ft\.?|feat\.?|featuring)\s+.*$"#
    private static let prod = #"\s+(prod\.?|produced by|prod by)\s+.*$"#

    static func cleanTitle(_ raw: String) -> String {
        var t = replace(raw, noise)
        t = replace(t, #"\s+(\||//)\s.*$"#)
        t = replace(t, prod)
        t = replace(t, feat)
        t = replace(t, #"\s*[(\[][^)\]]*[)\]]\s*$"#)
        t = replace(t, #"\s{2,}"#, " ")
        return t.trimmingCharacters(in: CharacterSet(charactersIn: " \"“”«»'.-–—"))
    }

    static func cleanArtist(_ raw: String) -> String {
        var a = replace(raw, #"\s*-\s*Topic$"#)
        a = replace(a, #"VEVO$"#)
        a = replace(a, feat)
        if let r = try? NSRegularExpression(pattern: #"\s*,\s*|\s+(?:&|×|x|X)\s+"#),
           let m = r.firstMatch(in: a, range: NSRange(location: 0, length: (a as NSString).length)) {
            a = (a as NSString).substring(to: m.range.location)
        }
        return a.trimmingCharacters(in: .whitespaces)
    }

    static func candidates(title: String, channel: String) -> Candidates {
        var artists: [String] = []
        var titles: [String] = []
        func add(_ value: String, _ list: inout [String]) {
            let v = value.trimmingCharacters(in: .whitespaces)
            if v.isEmpty || v == "YouTube" { return }
            if list.contains(where: { SearchKey.normalize($0) == SearchKey.normalize(v) }) { return }
            list.append(v)
        }
        let base = replace(title, noise)
        if let r = try? NSRegularExpression(pattern: #"\s[-–—]\s"#),
           let m = r.firstMatch(in: base, range: NSRange(location: 0, length: (base as NSString).length)) {
            let ns = base as NSString
            add(cleanArtist(ns.substring(to: m.range.location)), &artists)
            add(cleanTitle(ns.substring(from: m.range.location + m.range.length)), &titles)
        }
        add(cleanArtist(channel), &artists)
        add(cleanTitle(title), &titles)
        return Candidates(artists: artists, titles: titles)
    }

    /// First artist / title pair.
    static func from(title: String, channel: String) -> (String, String) {
        let c = candidates(title: title, channel: channel)
        return (c.artists.first ?? "", c.titles.first ?? title)
    }
}
