import Foundation
import GRDB

/// Sample library used by the CI screenshot job (`-demoData`), matching the design boards.
/// `-demoScreen nowPlaying|playlists|downloads|settings|add` opens a screen directly.
@MainActor
enum DemoData {
    static func install() {
        let library = Library.shared
        let now = Date()
        let rows: [(String, String, String, Int)] = [
            ("demo0000001", "Lumini de oraș", "Aria Vale", 238),
            ("demo0000002", "Midnight Drive", "Neon Harbor", 252),
            ("demo0000003", "Ploaie pe asfalt", "Luca M.", 201),
            ("demo0000004", "Silent Orbit", "Kaito Rey", 304),
            ("demo0000005", "Vals de noiembrie", "Corina S.", 167),
            ("demo0000006", "Afterglow", "The Velvet Hours", 216),
            ("demo0000007", "Departe", "Ion & Mira", 241),
            ("demo0000008", "Felinare", "Aria Vale", 192),
            ("demo0000009", "Горы", "Лера Н.", 223),
            ("demo0000010", "Northern Lights", "Polar Sun", 259),
        ]
        var tracks: [Track] = []
        for (i, r) in rows.enumerated() {
            let t = Track(
                id: r.0, title: r.1, artist: r.2, durationMs: Int64(r.3 * 1000), fileName: "\(r.0).m4a",
                artworkFile: nil, sizeBytes: Int64(r.3) * 32_000, format: "m4a",
                addedAt: now.addingTimeInterval(-Double(i) * 60), isFavorite: i == 0 || i == 3,
                sourceUrl: YouTubeLinks.videoURL(r.0), userEdited: false, searchKey: SearchKey.of(r.1, r.2)
            )
            try? library.insert(t)
            tracks.append(t)
        }
        let night = library.createPlaylist(name: "Noaptea târziu", youtubeId: "PLdemo00000001")
        let drive = library.createPlaylist(name: "Drum lung")
        let focus = library.createPlaylist(name: "Focus", youtubeId: "PLdemo00000002")
        for (i, t) in tracks.prefix(6).enumerated() { if let night { library.add(t.id, toPlaylist: night, at: i) } }
        for (i, t) in tracks.suffix(4).enumerated() { if let drive { library.add(t.id, toPlaylist: drive, at: i) } }
        for (i, t) in tracks.enumerated() where i % 2 == 0 { if let focus { library.add(t.id, toPlaylist: focus, at: i) } }

        let downloads: [(String, String, DownloadStatus, String?)] = [
            ("demoDl00001", "Stele căzătoare", .active, nil),
            ("demoDl00002", "Orașul doarme", .active, nil),
            ("demoDl00003", "Neon Rain", .queued, nil),
            ("demoDl00004", "Lumini de oraș", .done, nil),
            ("demoDl00005", "Private Session", .failed, ErrorKind.privateVideo.rawValue),
        ]
        try? library.db.writer.write { db in
            for (i, d) in downloads.enumerated() {
                var item = DownloadItem(
                    id: nil, videoId: d.0, url: YouTubeLinks.videoURL(d.0), title: d.1, artist: "Nocturne",
                    thumbnailUrl: nil, durationMs: 200_000, batchId: 1, batchName: "Noaptea târziu", playlistId: night,
                    playlistPosition: i, status: d.2, attempts: d.2 == .failed ? 3 : 0, errorKey: d.3,
                    totalBytes: 4_400_000, format: "m4a", createdAt: now.addingTimeInterval(Double(i))
                )
                try item.insert(db)
            }
        }

        PlayerEngine.shared.loadDemo(
            Array(tracks.prefix(6)),
            context: PlaybackContext(playlistId: night, label: "Noaptea târziu"),
            position: 102,
            playing: true
        )

        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-demoScreen"), i + 1 < args.count {
            let app = AppState.shared
            switch args[i + 1] {
            case "nowPlaying": app.nowPlayingOpen = true
            case "playlists": app.tab = .playlists
            case "downloads": app.tab = .downloads
            case "settings": app.path = [.settings]
            case "add": app.path = [.add(nil)]
            default: break
            }
        }
        if let i = args.firstIndex(of: "-demoLanguage"), i + 1 < args.count, let l = AppLanguage(rawValue: args[i + 1]) {
            LanguageManager.shared.select(l)
        } else {
            LanguageManager.shared.select(.ro)
        }
    }
}
