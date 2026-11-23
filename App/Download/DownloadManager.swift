import Foundation
import UIKit
import UserNotifications
import AVFoundation
import GRDB

struct LiveProgress: Equatable {
    var downloadedBytes: Int64
    var totalBytes: Int64
    var bytesPerSecond: Double

    var fraction: Double { totalBytes > 0 ? min(1, Double(downloadedBytes) / Double(totalBytes)) : 0 }
}

struct DownloadStats {
    var done: Int
    var total: Int
    var active: Int
    var bytesPerSecond: Double
    var hasPending: Bool
    var allPaused: Bool
    /// 0…1 over the whole batch.
    var fraction: Double
}

/// Downloads audio with a background `URLSession` (continues while the app is in the background):
/// up to 4 tracks in parallel, 10 MB range chunks (avoids YouTube throttling), 3 attempts per track,
/// duplicates skipped by video id. Finished files go to Documents/Music/Nocturne.
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    static let maxParallel = 4
    static let maxAttempts = 3
    static let chunkSize: Int64 = 10 * 1024 * 1024
    static let sessionId = (AppGroup.appBundleIdentifier ?? "com.nocturne.player") + ".downloads"

    @Published private(set) var progress: [Int64: LiveProgress] = [:]

    var resolver: StreamResolver = YouTubeKitResolver()
    var catalog: CatalogProvider = YouTubeCatalog.shared
    private let library = Library.shared

    /// Background-session completion handler from the app delegate.
    var backgroundCompletionHandler: (() -> Void)?

    private struct Job {
        var streamURL: URL
        var total: Int64
        var ext: String
        var format: String
        var lastSampleBytes: Int64 = 0
        var lastSampleTime: Date = Date()
        var speed: Double = 0
    }

    /// Download id → job. Accessed on the main queue only.
    private var jobs: [Int64: Job] = [:]
    private var starting: Set<Int64> = []
    private lazy var delegate = SessionDelegate(owner: self)
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionId)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.allowsCellularAccess = true
        config.httpMaximumConnectionsPerHost = Self.maxParallel
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config, delegate: delegate, delegateQueue: .main)
    }()

    private init() {}

    /// Re-attaches to tasks that survived a relaunch, then resumes the queue.
    func start() {
        guard !ProcessInfo.processInfo.arguments.contains("-demoData") else { return }
        session.getAllTasks { [weak self] tasks in
            DispatchQueue.main.async {
                guard let self else { return }
                let running = Set(tasks.compactMap { ChunkInfo(task: $0)?.downloadId })
                // Rows marked ACTIVE without a live task were interrupted (app killed): queue them again.
                try? self.library.db.writer.write { db in
                    let active = try DownloadItem.filter(Column("status") == DownloadStatus.active.rawValue).fetchAll(db)
                    for var d in active where !running.contains(d.id ?? -1) {
                        d.status = .queued
                        try d.update(db)
                    }
                }
                for task in tasks {
                    guard let info = ChunkInfo(task: task), let url = task.originalRequest?.url else { continue }
                    if self.jobs[info.downloadId] == nil {
                        let total = info.total > 0 ? info.total : (YouTubeKitResolver.clen(url) ?? 0)
                        self.jobs[info.downloadId] = Job(streamURL: url, total: total, ext: "m4a", format: "m4a")
                    }
                }
                self.pump()
            }
        }
    }

    // MARK: enqueue / controls

    /// Adds the resolved items to the queue, skipping ids already in the library or queued.
    /// Returns how many were added.
    @discardableResult
    func enqueue(_ resolved: ResolvedLink) -> Int {
        let known = library.knownVideoIds()
        let playlistId: Int64? = resolved.isPlaylist
            ? library.createPlaylist(name: resolved.title, youtubeId: resolved.youtubePlaylistId)
            : nil
        if let pid = playlistId {
            // Tracks already in the library join the imported playlist right away.
            let inLibrary = library.libraryIds()
            for (i, item) in resolved.items.enumerated() where inLibrary.contains(item.videoId) {
                library.add(item.videoId, toPlaylist: pid, at: i)
            }
        }
        let batchId = Int64(Date().timeIntervalSince1970 * 1000)
        let added: Int = (try? library.db.writer.write { db -> Int in
            var count = 0
            for (i, item) in resolved.items.enumerated() where !known.contains(item.videoId) {
                var d = DownloadItem(
                    id: nil, videoId: item.videoId, url: item.url, title: item.title, artist: item.artist,
                    thumbnailUrl: item.thumbnailUrl, durationMs: Int64(item.durationSec) * 1000, batchId: batchId,
                    batchName: resolved.isPlaylist ? resolved.title : nil, playlistId: playlistId, playlistPosition: i,
                    status: .queued, attempts: 0, errorKey: nil, totalBytes: 0, format: nil, createdAt: Date()
                )
                try d.insert(db)
                count += 1
            }
            return count
        }) ?? 0
        if added > 0 {
            requestNotificationPermission()
            pump()
        }
        return added
    }

    func pauseAll() {
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
        jobs.removeAll()
        progress.removeAll()
        try? library.db.writer.write { db in
            try db.execute(sql: "UPDATE downloads SET status = 'PAUSED' WHERE status IN ('QUEUED','ACTIVE')")
        }
    }

    func resumeAll() {
        try? library.db.writer.write { db in
            try db.execute(sql: "UPDATE downloads SET status = 'QUEUED' WHERE status = 'PAUSED'")
        }
        pump()
    }

    func retry(_ id: Int64) {
        try? library.db.writer.write { db in
            try db.execute(sql: "UPDATE downloads SET status = 'QUEUED', attempts = 0, errorKey = NULL WHERE id = ?", arguments: [id])
        }
        pump()
    }

    func clearFinished() {
        try? library.db.writer.write { db in
            try db.execute(sql: "DELETE FROM downloads WHERE status IN ('DONE','FAILED')")
        }
    }

    func stats(_ all: [DownloadItem]) -> DownloadStats {
        let latestBatch = all.map(\.batchId).max()
        let batch = all.filter { $0.batchId == latestBatch || $0.status == .active || $0.status == .queued }
        let done = batch.filter { $0.status == .done }.count
        let active = all.filter { $0.status == .active }.count
        let pending = all.contains { $0.status == .queued || $0.status == .active || $0.status == .paused }
        let paused = all.contains { $0.status == .paused } && !all.contains { $0.status == .queued || $0.status == .active }
        let speed = progress.values.reduce(0) { $0 + $1.bytesPerSecond }
        var fraction = 0.0
        if !batch.isEmpty {
            let partial = batch.reduce(0.0) { acc, d in
                if d.status == .done { return acc + 1 }
                if let id = d.id, let p = progress[id] { return acc + p.fraction }
                return acc
            }
            fraction = partial / Double(batch.count)
        }
        return DownloadStats(done: done, total: batch.count, active: active, bytesPerSecond: speed,
                             hasPending: pending, allPaused: paused, fraction: fraction)
    }

    // MARK: scheduler

    /// Starts queued downloads until `maxParallel` are running.
    func pump() {
        guard !ProcessInfo.processInfo.arguments.contains("-demoData") else { return }
        let running = jobs.count + starting.count
        guard running < Self.maxParallel else { return }
        let queued: [DownloadItem] = (try? library.db.writer.read { db in
            try DownloadItem.filter(Column("status") == DownloadStatus.queued.rawValue)
                .order(Column("createdAt"), Column("playlistPosition"))
                .limit(Self.maxParallel - running)
                .fetchAll(db)
        }) ?? []
        for d in queued {
            guard let id = d.id, jobs[id] == nil, !starting.contains(id) else { continue }
            begin(d)
        }
        if jobs.isEmpty && starting.isEmpty {
            finishedEverything()
        }
    }

    private func begin(_ d: DownloadItem) {
        guard let id = d.id else { return }
        starting.insert(id)
        setStatus(id, .active)
        let resolver = self.resolver
        Task {
            do {
                let stream = try await resolver.resolveAudio(videoId: d.videoId)
                var total = stream.contentLength ?? 0
                if total <= 0 { total = (try? await Self.probeLength(stream.url)) ?? 0 }
                await MainActor.run {
                    self.starting.remove(id)
                    guard self.isActive(id) else { self.pump(); return }
                    self.jobs[id] = Job(streamURL: stream.url, total: total, ext: stream.fileExtension, format: stream.format)
                    self.updateRow(id) { $0.totalBytes = total; $0.format = stream.format }
                    self.scheduleNextChunk(id)
                }
            } catch {
                await MainActor.run {
                    self.starting.remove(id)
                    self.fail(id, error)
                }
            }
        }
    }

    private func isActive(_ id: Int64) -> Bool {
        let row = try? library.db.writer.read { db in try DownloadItem.fetchOne(db, key: id) }
        return row?.status == .active
    }

    private func partURL(_ id: Int64) -> URL { Storage.partsDir.appendingPathComponent("\(id).part") }

    private func partSize(_ id: Int64) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: partURL(id).path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func scheduleNextChunk(_ id: Int64) {
        guard let job = jobs[id] else { return }
        let have = partSize(id)
        if job.total > 0 && have >= job.total {
            complete(id)
            return
        }
        var req = URLRequest(url: job.streamURL)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        let end = job.total > 0 ? min(have + Self.chunkSize, job.total) - 1 : have + Self.chunkSize - 1
        req.setValue("bytes=\(have)-\(end)", forHTTPHeaderField: "Range")
        let task = session.downloadTask(with: req)
        task.taskDescription = ChunkInfo(downloadId: id, start: have, end: end, total: job.total).encoded
        task.resume()
    }

    // MARK: session callbacks (main queue)

    fileprivate func chunkFinished(_ info: ChunkInfo, task: URLSessionTask, file: URL?) {
        defer { if let file { try? FileManager.default.removeItem(at: file) } }
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        guard let file, (200..<300).contains(status) else {
            // 403/410: the stream URL expired → resolve again (counts as an attempt).
            retryOrFail(info.downloadId, ErrorKind.generic)
            return
        }
        if jobs[info.downloadId] == nil, let url = task.originalRequest?.url {
            jobs[info.downloadId] = Job(streamURL: url, total: info.total, ext: "m4a", format: "m4a")
        }
        let part = partURL(info.downloadId)
        do {
            if status == 200 {
                // Server ignored the range: the body is the whole file.
                try? FileManager.default.removeItem(at: part)
                try FileManager.default.moveItem(at: file, to: part)
                if var job = jobs[info.downloadId] {
                    job.total = partSize(info.downloadId)
                    jobs[info.downloadId] = job
                }
            } else {
                if !FileManager.default.fileExists(atPath: part.path) {
                    FileManager.default.createFile(atPath: part.path, contents: nil)
                }
                let out = try FileHandle(forWritingTo: part)
                defer { try? out.close() }
                try out.seekToEnd()
                let input = try FileHandle(forReadingFrom: file)
                defer { try? input.close() }
                while true {
                    let data = try input.read(upToCount: 1_048_576) ?? Data()
                    if data.isEmpty { break }
                    try out.write(contentsOf: data)
                }
                // Learn the total from Content-Range when `clen` was missing.
                if var job = jobs[info.downloadId], job.total <= 0,
                   let range = (task.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Range"),
                   let totalStr = range.split(separator: "/").last, let total = Int64(totalStr) {
                    job.total = total
                    jobs[info.downloadId] = job
                    updateRow(info.downloadId) { $0.totalBytes = total }
                }
            }
        } catch {
            fail(info.downloadId, error)
            return
        }
        let have = partSize(info.downloadId)
        let total = jobs[info.downloadId]?.total ?? 0
        let receivedChunk = Int64(info.end - info.start + 1)
        if total > 0 ? have >= total : (status == 200 || have < info.start + receivedChunk) {
            complete(info.downloadId)
        } else {
            scheduleNextChunk(info.downloadId)
        }
    }

    fileprivate func chunkProgress(_ info: ChunkInfo, written: Int64) {
        guard var job = jobs[info.downloadId] else { return }
        let downloaded = info.start + written
        let now = Date()
        let dt = now.timeIntervalSince(job.lastSampleTime)
        if dt >= 0.5 {
            let instant = Double(max(0, downloaded - job.lastSampleBytes)) / dt
            job.speed = job.speed == 0 ? instant : job.speed * 0.6 + instant * 0.4
            job.lastSampleBytes = downloaded
            job.lastSampleTime = now
            jobs[info.downloadId] = job
            progress[info.downloadId] = LiveProgress(downloadedBytes: downloaded, totalBytes: job.total, bytesPerSecond: job.speed)
        }
    }

    fileprivate func chunkFailed(_ info: ChunkInfo, error: Error) {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return } // paused
        retryOrFail(info.downloadId, error)
    }

    fileprivate func sessionFinishedEvents() {
        backgroundCompletionHandler?()
        backgroundCompletionHandler = nil
    }

    // MARK: completion / failure

    private func retryOrFail(_ id: Int64, _ error: Error) {
        jobs[id] = nil
        progress[id] = nil
        let kind = ErrorKind.from(error)
        let attempts = updateRow(id) { $0.attempts += 1 }?.attempts ?? Self.maxAttempts
        if attempts < Self.maxAttempts && kind.retryable {
            setStatus(id, .queued)
        } else {
            updateRow(id) { $0.status = .failed; $0.errorKey = kind.rawValue }
        }
        pump()
    }

    private func fail(_ id: Int64, _ error: Error) {
        retryOrFail(id, error)
    }

    private func complete(_ id: Int64) {
        guard let job = jobs[id] else { return }
        jobs[id] = nil
        progress[id] = nil
        let fetched: DownloadItem? = try? library.db.writer.read { db in try DownloadItem.fetchOne(db, key: id) }
        guard let row = fetched else {
            pump(); return
        }
        let part = partURL(id)
        Task {
            // Prefer the original (untranslated) title from oEmbed; keep queue data as fallback.
            let meta = try? await self.catalog.videoMetadata(row.videoId)
            let title = meta?.title ?? row.title
            let artist = (meta?.artist).flatMap { $0 == "YouTube" ? nil : $0 } ?? row.artist
            let artwork = await Artwork.download(videoId: row.videoId)
            await MainActor.run {
                self.finalize(row: row, job: job, part: part, title: title, artist: artist, artworkFile: artwork)
            }
        }
    }

    private func finalize(row: DownloadItem, job: Job, part: URL, title: String, artist: String, artworkFile: String?) {
        guard let id = row.id else { return }
        let fileName = Storage.audioFileName(title: title, videoId: row.videoId, ext: job.ext)
        let dest = Storage.musicDir.appendingPathComponent(fileName)
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: part, to: dest)
            let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.int64Value ?? 0
            var durationMs = row.durationMs
            if durationMs <= 0 {
                let asset = AVURLAsset(url: dest)
                let secs = CMTimeGetSeconds(asset.duration)
                if secs.isFinite && secs > 0 { durationMs = Int64(secs * 1000) }
            }
            let track = Track(
                id: row.videoId, title: title, artist: artist, durationMs: durationMs, fileName: fileName,
                artworkFile: artworkFile, sizeBytes: size, format: job.format, addedAt: Date(), isFavorite: false,
                sourceUrl: row.url, userEdited: false, searchKey: SearchKey.of(title, artist)
            )
            try library.insert(track)
            if let pid = row.playlistId {
                library.add(row.videoId, toPlaylist: pid, at: row.playlistPosition)
            }
            updateRow(id) { $0.status = .done; $0.errorKey = nil; $0.totalBytes = size }
        } catch {
            updateRow(id) { $0.status = .failed; $0.errorKey = ErrorKind.from(error).rawValue }
        }
        pump()
    }

    private func finishedEverything() {
        let recentDone = library.downloads.filter { $0.status == .done && Date().timeIntervalSince($0.createdAt) < 6 * 3600 }.count
        guard recentDone > 0, UserDefaults.standard.bool(forKey: "notifiedBatchDone") == false else { return }
        let title = L10n.t("downloads_finished_title")
        let body = L10n.p("downloaded_count", recentDone)
        Task { @MainActor in
            // Notify only when the batch finished while the app was in the background.
            guard UIApplication.shared.applicationState != .active else { return }
            UserDefaults.standard.set(true, forKey: "notifiedBatchDone")
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "downloads-done", content: content, trigger: nil))
        }
    }

    private func requestNotificationPermission() {
        UserDefaults.standard.set(false, forKey: "notifiedBatchDone")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: rows

    private func setStatus(_ id: Int64, _ status: DownloadStatus) {
        updateRow(id) { $0.status = status }
    }

    @discardableResult
    private func updateRow(_ id: Int64, _ change: (inout DownloadItem) -> Void) -> DownloadItem? {
        guard var row: DownloadItem = try? library.db.writer.read({ db in try DownloadItem.fetchOne(db, key: id) }) else {
            return nil
        }
        change(&row)
        let updated = row
        try? library.db.writer.write { db in try updated.update(db) }
        return updated
    }

    /// Size via a 1-byte range probe (when the URL has no `clen`).
    private static func probeLength(_ url: URL) async throws -> Int64 {
        var req = URLRequest(url: url)
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let range = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Range"),
              let total = range.split(separator: "/").last.flatMap({ Int64($0) }) else { return 0 }
        return total
    }
}

/// Encoded into `URLSessionTask.taskDescription` so chunks survive an app relaunch.
fileprivate struct ChunkInfo {
    let downloadId: Int64
    let start: Int64
    let end: Int64
    let total: Int64

    init(downloadId: Int64, start: Int64, end: Int64, total: Int64) {
        self.downloadId = downloadId; self.start = start; self.end = end; self.total = total
    }

    init?(task: URLSessionTask) {
        guard let parts = task.taskDescription?.split(separator: "|").compactMap({ Int64($0) }), parts.count == 4 else { return nil }
        self.init(downloadId: parts[0], start: parts[1], end: parts[2], total: parts[3])
    }

    var encoded: String { "\(downloadId)|\(start)|\(end)|\(total)" }
}

/// URLSession delegate (runs on the main queue — the session's delegate queue).
fileprivate final class SessionDelegate: NSObject, URLSessionDownloadDelegate {
    weak var owner: DownloadManager?
    /// Files already moved out of the system temp location, keyed by task id.
    private var finishedFiles: [Int: URL] = [:]

    init(owner: DownloadManager) { self.owner = owner }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temp file is deleted when this returns: move it now.
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent("chunk-\(UUID().uuidString)")
        if (try? FileManager.default.moveItem(at: location, to: keep)) != nil {
            finishedFiles[downloadTask.taskIdentifier] = keep
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let info = ChunkInfo(task: downloadTask) else { return }
        owner?.chunkProgress(info, written: totalBytesWritten)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let info = ChunkInfo(task: task) else { return }
        let file = finishedFiles.removeValue(forKey: task.taskIdentifier)
        if let error {
            if let file { try? FileManager.default.removeItem(at: file) }
            owner?.chunkFailed(info, error: error)
        } else {
            owner?.chunkFinished(info, task: task, file: file)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        owner?.sessionFinishedEvents()
    }
}
