import Foundation
import GRDB
import Combine

enum TrackSort: String, CaseIterable, Identifiable {
    case recent, title, duration
    var id: String { rawValue }
    var labelKey: String {
        switch self {
        case .recent: return "sort_recent"
        case .title: return "sort_title"
        case .duration: return "sort_duration"
        }
    }
}

/// The music library: observes the database and exposes tracks, playlists and downloads.
/// All published values are delivered on the main queue.
final class Library: ObservableObject {
    static let shared = Library(db: AppDatabase.shared)

    let db: AppDatabase
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var playlists: [PlaylistSummary] = []
    @Published private(set) var playlistTrackIds: [Int64: [String]] = [:]
    @Published private(set) var downloads: [DownloadItem] = []

    /// Called whenever track rows change (the player refreshes edited metadata / removed tracks).
    let tracksChanged = PassthroughSubject<[Track], Never>()

    private var observers: [AnyDatabaseCancellable] = []

    init(db: AppDatabase) {
        self.db = db
        start()
    }

    private func start() {
        let tracksObs = ValueObservation.tracking { db in
            try Track.order(Column("addedAt").desc).fetchAll(db)
        }
        observers.append(tracksObs.start(in: db.writer, scheduling: .immediate, onError: { _ in }, onChange: { [weak self] value in
            self?.tracks = value
            self?.tracksChanged.send(value)
        }))

        let playlistObs = ValueObservation.tracking { db -> ([PlaylistSummary], [Int64: [String]]) in
            let rows = try Row.fetchAll(db, sql: """
                SELECT p.*,
                       (SELECT COUNT(*) FROM playlist_tracks pt WHERE pt.playlistId = p.id) AS trackCount,
                       (SELECT COALESCE(SUM(t.durationMs), 0) FROM playlist_tracks pt JOIN tracks t ON t.id = pt.trackId
                         WHERE pt.playlistId = p.id) AS totalMs,
                       (SELECT t.artworkFile FROM playlist_tracks pt JOIN tracks t ON t.id = pt.trackId
                         WHERE pt.playlistId = p.id AND t.artworkFile IS NOT NULL ORDER BY pt.position LIMIT 1) AS firstArt
                FROM playlists p ORDER BY p.createdAt DESC
                """)
            let summaries: [PlaylistSummary] = try rows.map { row in
                PlaylistSummary(
                    playlist: try Playlist(row: row),
                    trackCount: row["trackCount"] ?? 0,
                    totalMs: row["totalMs"] ?? 0,
                    firstArtwork: row["firstArt"]
                )
            }
            var map: [Int64: [String]] = [:]
            for ref in try PlaylistTrack.order(Column("playlistId"), Column("position")).fetchAll(db) {
                map[ref.playlistId, default: []].append(ref.trackId)
            }
            return (summaries, map)
        }
        observers.append(playlistObs.start(in: db.writer, scheduling: .immediate, onError: { _ in }, onChange: { [weak self] value in
            self?.playlists = value.0
            self?.playlistTrackIds = value.1
        }))

        let downloadsObs = ValueObservation.tracking { db in
            try DownloadItem.order(Column("createdAt").desc, Column("id")).fetchAll(db)
        }
        observers.append(downloadsObs.start(in: db.writer, scheduling: .immediate, onError: { _ in }, onChange: { [weak self] value in
            self?.downloads = value
        }))
    }

    // MARK: queries

    func track(_ id: String) -> Track? { tracks.first { $0.id == id } }

    func tracks(ids: [String]) -> [Track] {
        let byId = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byId[$0] }
    }

    func tracks(inPlaylist id: Int64) -> [Track] { tracks(ids: playlistTrackIds[id] ?? []) }

    var favorites: [Track] { tracks.filter(\.isFavorite) }

    func sorted(_ list: [Track], by sort: TrackSort) -> [Track] {
        switch sort {
        case .recent: return list.sorted { $0.addedAt > $1.addedAt }
        case .title: return list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .duration: return list.sorted { $0.durationMs < $1.durationMs }
        }
    }

    /// Case- and diacritics-insensitive search ("oras" finds "oraș", Cyrillic too).
    func search(_ query: String, in list: [Track]) -> [Track] {
        let q = SearchKey.normalize(query)
        guard !q.isEmpty else { return list }
        let words = q.split(separator: " ").map(String.init)
        return list.filter { t in words.allSatisfy { t.searchKey.contains($0) } }
    }

    /// Video ids already in the library or waiting in the download queue.
    func knownVideoIds() -> Set<String> {
        (try? db.writer.read { db -> Set<String> in
            let ids = try String.fetchAll(db, sql: "SELECT id FROM tracks")
            let pending = try String.fetchAll(db, sql: "SELECT videoId FROM downloads WHERE status IN ('QUEUED','ACTIVE','PAUSED')")
            return Set(ids).union(pending)
        }) ?? []
    }

    func libraryIds() -> Set<String> {
        (try? db.writer.read { db in Set(try String.fetchAll(db, sql: "SELECT id FROM tracks")) }) ?? []
    }

    var totalBytes: Int64 { tracks.reduce(0) { $0 + $1.sizeBytes } }

    // MARK: tracks

    func toggleFavorite(_ id: String) {
        try? db.writer.write { db in
            try db.execute(sql: "UPDATE tracks SET isFavorite = NOT isFavorite WHERE id = ?", arguments: [id])
        }
    }

    /// "Editează detaliile": manual edit, never overwritten afterwards.
    func updateDetails(_ id: String, title: String, artist: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        try? db.writer.write { db in
            try db.execute(
                sql: "UPDATE tracks SET title = ?, artist = ?, userEdited = 1, searchKey = ? WHERE id = ?",
                arguments: [t, a, SearchKey.of(t, a), id]
            )
        }
    }

    /// After the m4a repair: real length and size.
    func updateFileInfo(_ id: String, durationMs: Int64, sizeBytes: Int64) {
        try? db.writer.write { db in
            try db.execute(sql: "UPDATE tracks SET durationMs = ?, sizeBytes = ? WHERE id = ?", arguments: [durationMs, sizeBytes, id])
        }
    }

    func delete(_ track: Track) {
        try? FileManager.default.removeItem(at: track.fileURL)
        if let art = track.artworkURL { try? FileManager.default.removeItem(at: art) }
        try? FileManager.default.removeItem(at: Storage.lyricsDir.appendingPathComponent("\(track.id).json"))
        try? db.writer.write { db in
            _ = try Track.deleteOne(db, key: track.id)
            try db.execute(sql: "DELETE FROM queue_items WHERE trackId = ?", arguments: [track.id])
        }
    }

    func insert(_ track: Track) throws {
        try db.writer.write { db in
            // Never overwrite a manual edit.
            if let existing = try Track.fetchOne(db, key: track.id), existing.userEdited {
                var merged = track
                merged.title = existing.title
                merged.artist = existing.artist
                merged.userEdited = true
                merged.isFavorite = existing.isFavorite
                merged.searchKey = existing.searchKey
                try merged.save(db)
            } else {
                try track.save(db)
            }
        }
    }

    // MARK: playlists

    @discardableResult
    func createPlaylist(name: String, youtubeId: String? = nil) -> Int64? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        return try? db.writer.write { db -> Int64? in
            if let yt = youtubeId, let existing = try Playlist.filter(Column("youtubeId") == yt).fetchOne(db) {
                return existing.id
            }
            var p = Playlist(id: nil, name: clean, fromYoutube: youtubeId != nil, youtubeId: youtubeId, createdAt: Date())
            try p.insert(db)
            return p.id
        }
    }

    func renamePlaylist(_ id: Int64, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        try? db.writer.write { db in
            try db.execute(sql: "UPDATE playlists SET name = ? WHERE id = ?", arguments: [clean, id])
        }
    }

    /// Deletes the playlist and, optionally, its songs (files included).
    func deletePlaylist(_ id: Int64, withSongs: Bool) {
        if withSongs {
            for track in tracks(inPlaylist: id) { delete(track) }
        }
        deletePlaylist(id)
    }

    /// Songs whose file was deleted outside the app (Files app) are removed from the library.
    @discardableResult
    func pruneMissingFiles() -> Int {
        let missing = tracks.filter { !$0.fileExists }
        for track in missing { delete(track) }
        return missing.count
    }

    func deletePlaylist(_ id: Int64) {
        try? db.writer.write { db in _ = try Playlist.deleteOne(db, key: id) }
    }

    func add(_ trackId: String, toPlaylist playlistId: Int64, at position: Int? = nil) {
        try? db.writer.write { db in
            let exists = try PlaylistTrack.filter(Column("playlistId") == playlistId && Column("trackId") == trackId).fetchCount(db) > 0
            guard !exists else { return }
            let next = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position), -1) + 1 FROM playlist_tracks WHERE playlistId = ?", arguments: [playlistId]) ?? 0
            try PlaylistTrack(playlistId: playlistId, trackId: trackId, position: position ?? next).insert(db)
        }
    }

    func remove(_ trackId: String, fromPlaylist playlistId: Int64) {
        try? db.writer.write { db in
            try db.execute(sql: "DELETE FROM playlist_tracks WHERE playlistId = ? AND trackId = ?", arguments: [playlistId, trackId])
        }
    }

    func reorder(playlist playlistId: Int64, ids: [String]) {
        try? db.writer.write { db in
            for (i, id) in ids.enumerated() {
                try db.execute(sql: "UPDATE playlist_tracks SET position = ? WHERE playlistId = ? AND trackId = ?", arguments: [i, playlistId, id])
            }
        }
    }

    func playlistName(_ id: Int64) -> String? { playlists.first { $0.playlist.id == id }?.playlist.name }
}
