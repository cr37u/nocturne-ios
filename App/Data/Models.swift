import Foundation
import GRDB

/// A downloaded, locally playable track. `id` IS the YouTube video id (primary key): duplicates are
/// detected by it, never by title. Title / artist are library data saved once at download time and
/// never re-fetched or translated; `userEdited` marks a manual edit that must never be overwritten.
struct Track: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    static let databaseTableName = "tracks"

    var id: String
    var title: String
    var artist: String
    var durationMs: Int64
    /// File name inside Documents/Music/Nocturne (relative: the container path changes between installs).
    var fileName: String
    /// File name inside Application Support/Artwork.
    var artworkFile: String?
    var sizeBytes: Int64
    var format: String
    var addedAt: Date
    var isFavorite: Bool
    var sourceUrl: String
    var userEdited: Bool
    var searchKey: String

    var duration: Double { Double(durationMs) / 1000 }
    var fileURL: URL { Storage.musicDir.appendingPathComponent(fileName) }
    var artworkURL: URL? { artworkFile.map { Storage.artworkDir.appendingPathComponent($0) } }
    var fileExists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }
}

struct Playlist: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    static let databaseTableName = "playlists"

    var id: Int64?
    var name: String
    var fromYoutube: Bool
    /// YouTube playlist id for imported lists (re-imports merge into the same playlist).
    var youtubeId: String?
    var createdAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct PlaylistTrack: Codable, FetchableRecord, PersistableRecord, Hashable {
    static let databaseTableName = "playlist_tracks"
    var playlistId: Int64
    var trackId: String
    var position: Int
}

enum DownloadStatus: String, Codable {
    case queued = "QUEUED", active = "ACTIVE", paused = "PAUSED", done = "DONE", failed = "FAILED"
}

struct DownloadItem: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    static let databaseTableName = "downloads"

    var id: Int64?
    var videoId: String
    var url: String
    var title: String
    var artist: String
    var thumbnailUrl: String?
    var durationMs: Int64
    var batchId: Int64
    var batchName: String?
    /// Local playlist that receives the track when done.
    var playlistId: Int64?
    var playlistPosition: Int
    var status: DownloadStatus
    var attempts: Int
    var errorKey: String?
    var totalBytes: Int64
    var format: String?
    var createdAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct QueueEntry: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "queue_items"
    var position: Int
    var trackId: String
}

struct SettingRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "settings"
    var key: String
    var value: String
}

/// Playlist + count + first artwork, for the grid.
struct PlaylistSummary: Identifiable, Hashable {
    var playlist: Playlist
    var trackCount: Int
    var totalMs: Int64
    var firstArtwork: String?
    var id: Int64 { playlist.id ?? -1 }
}

/// Accent- and case-insensitive search key: "Lumini de oraș" → "lumini de oras".
/// Latin diacritics are folded (ș/ş → s, ț/ţ → t, ă/â → a, î → i …); Cyrillic stays Cyrillic and
/// is lower-cased ("Горы" matches "горы", ё ↔ е).
enum SearchKey {
    static func of(_ parts: String?...) -> String {
        normalize(parts.compactMap { $0 }.joined(separator: " "))
    }

    static func normalize(_ text: String) -> String {
        let folded = text
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "Ё", with: "Е")
            .replacingOccurrences(of: "й", with: "и")
            .replacingOccurrences(of: "Й", with: "И")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "ı", with: "i")
            .lowercased()
        return folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

enum Storage {
    /// Documents/Music/Nocturne — visible in the Files app (UIFileSharingEnabled), survives updates.
    static let musicDir: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Music", isDirectory: true).appendingPathComponent("Nocturne", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Nocturne", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let artworkDir: URL = {
        let dir = supportDir.appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let partsDir: URL = {
        let dir = supportDir.appendingPathComponent("Parts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let lyricsDir: URL = {
        let dir = supportDir.appendingPathComponent("Lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// "Title [videoId].m4a" with characters the Files app dislikes removed.
    static func audioFileName(title: String, videoId: String, ext: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>:\n\r\t")
        var clean = title.components(separatedBy: bad).joined(separator: " ")
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count > 80 { clean = String(clean.prefix(80)).trimmingCharacters(in: .whitespaces) }
        if clean.isEmpty { clean = "Nocturne" }
        return "\(clean) [\(videoId)].\(ext)"
    }
}
