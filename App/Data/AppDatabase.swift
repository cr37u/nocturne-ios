import Foundation
import GRDB

/// SQLite (GRDB) with versioned migrations from day one. Schema mirrors the Android Room v2 schema
/// plus the player queue and settings.
final class AppDatabase {
    let writer: any DatabaseWriter

    static let shared: AppDatabase = {
        if ProcessInfo.processInfo.arguments.contains("-demoData") {
            return try! AppDatabase.inMemory()
        }
        do {
            let url = Storage.supportDir.appendingPathComponent("library.sqlite")
            var config = Configuration()
            config.foreignKeysEnabled = true
            let pool = try DatabasePool(path: url.path, configuration: config)
            return try AppDatabase(pool)
        } catch {
            // Last resort: keep the app usable.
            return try! AppDatabase.inMemory()
        }
    }()

    static func inMemory() throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        return try AppDatabase(DatabaseQueue(configuration: config))
    }

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()

        m.registerMigration("v1") { db in
            try db.create(table: "tracks") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("artist", .text).notNull()
                t.column("durationMs", .integer).notNull().defaults(to: 0)
                t.column("fileName", .text).notNull()
                t.column("artworkFile", .text)
                t.column("sizeBytes", .integer).notNull().defaults(to: 0)
                t.column("format", .text).notNull().defaults(to: "m4a")
                t.column("addedAt", .datetime).notNull()
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("sourceUrl", .text).notNull()
                t.column("userEdited", .boolean).notNull().defaults(to: false)
                t.column("searchKey", .text).notNull().defaults(to: "")
            }
            try db.create(table: "playlists") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("fromYoutube", .boolean).notNull().defaults(to: false)
                t.column("youtubeId", .text).unique()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "playlist_tracks") { t in
                t.column("playlistId", .integer).notNull().references("playlists", onDelete: .cascade)
                t.column("trackId", .text).notNull().references("tracks", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.primaryKey(["playlistId", "trackId"])
            }
            try db.create(index: "index_playlist_tracks_trackId", on: "playlist_tracks", columns: ["trackId"])
            try db.create(table: "downloads") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("videoId", .text).notNull().indexed()
                t.column("url", .text).notNull()
                t.column("title", .text).notNull()
                t.column("artist", .text).notNull()
                t.column("thumbnailUrl", .text)
                t.column("durationMs", .integer).notNull().defaults(to: 0)
                t.column("batchId", .integer).notNull().indexed()
                t.column("batchName", .text)
                t.column("playlistId", .integer)
                t.column("playlistPosition", .integer).notNull().defaults(to: 0)
                t.column("status", .text).notNull()
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("errorKey", .text)
                t.column("totalBytes", .integer).notNull().defaults(to: 0)
                t.column("format", .text)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "queue_items") { t in
                t.column("position", .integer).primaryKey()
                t.column("trackId", .text).notNull()
            }
            try db.create(table: "settings") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }
        }

        // Future schema changes go here as "v2", "v3", … (never edit a shipped migration).
        return m
    }

    // MARK: settings

    func setting(_ key: String) -> String? {
        try? writer.read { db in try SettingRow.fetchOne(db, key: key)?.value }
    }

    func setSetting(_ key: String, _ value: String?) {
        try? writer.write { db in
            if let value {
                try SettingRow(key: key, value: value).save(db)
            } else {
                _ = try SettingRow.deleteOne(db, key: key)
            }
        }
    }
}
