import Foundation
import UIKit
import Combine
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Keeps the widgets (App Group snapshot + timeline reloads) and the Live Activity in sync with the
/// player: track change, play/pause, seek (debounced), metadata edits and language changes.
final class SystemSurfaces {
    static let shared = SystemSurfaces()

    private var cancellables = Set<AnyCancellable>()
    private let engine = PlayerEngine.shared
    private var lastSnapshot: NowPlayingSnapshot?
    private var lastTrackId: String?
    private var lastReload = Date.distantPast
    private var pendingReload = false

    func start() {
        engine.stateChanged
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.sync(force: false) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .nocturneQueueEnded)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.endLiveActivity() }
            .store(in: &cancellables)
        if #available(iOS 16.1, *) {
            LiveActivityController.shared.adoptExisting()
        }
        sync(force: true)
    }

    /// Language switched / app foregrounded: push everything again.
    func refreshAll() { sync(force: true) }

    private func sync(force: Bool) {
        let snapshot = makeSnapshot()
        let trackChanged = snapshot.trackId != lastTrackId
        lastTrackId = snapshot.trackId
        if force || snapshot != lastSnapshot {
            lastSnapshot = snapshot
            snapshot.save()
            reloadWidgets(immediately: force || trackChanged)
        }
        if #available(iOS 16.1, *) {
            LiveActivityController.shared.update(with: snapshot, engine: engine)
        }
    }

    private func makeSnapshot() -> NowPlayingSnapshot {
        guard let t = engine.current else { return .empty }
        let next = engine.upNext
        return NowPlayingSnapshot(
            trackId: t.id, title: t.title, artist: t.artist, playlist: engine.context.label,
            isPlaying: engine.isPlaying, position: engine.clock.position,
            duration: engine.clock.duration > 0 ? engine.clock.duration : t.duration, updatedAt: Date(),
            shuffle: engine.shuffle, repeatMode: engine.repeatMode.rawValue,
            nextTitle: next?.title, nextArtist: next?.artist,
            artworkFile: SharedArtwork.export(t)
        )
    }

    private func reloadWidgets(immediately: Bool) {
        let gap = Date().timeIntervalSince(lastReload)
        if immediately || gap > 2 {
            lastReload = Date()
            WidgetCenter.shared.reloadAllTimelines()
        } else if !pendingReload {
            pendingReload = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.pendingReload = false
                self?.lastReload = Date()
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    private func endLiveActivity() {
        if #available(iOS 16.1, *) {
            LiveActivityController.shared.end()
        }
    }
}

/// Copies the current cover (small) into the App Group so widgets and the Live Activity can show it.
enum SharedArtwork {
    static func export(_ track: Track) -> String? {
        guard let dir = AppGroup.container?.appendingPathComponent("Artwork", isDirectory: true),
              let file = track.artworkFile else { return nil }
        let name = "\(track.id).jpg"
        let dest = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) { return name }
        guard let image = Artwork.load(file) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let small = Artwork.resized(image, side: 240)
        guard let data = small.jpegData(compressionQuality: 0.8) else { return nil }
        do {
            try data.write(to: dest, options: .atomic)
            prune(dir, keep: name)
            return name
        } catch {
            return nil
        }
    }

    /// Keeps the shared folder small (the Live Activity only needs the current cover).
    private static func prune(_ dir: URL, keep: String) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let sorted = files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
        for url in sorted.dropFirst(8) where url.lastPathComponent != keep {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

#if canImport(ActivityKit)
/// Live Activity: started when playback starts (app in the foreground), updated on track change /
/// play-pause / seek, ended when playback stops or the queue ends. Devices without a Dynamic Island
/// show the lock-screen presentation only.
@available(iOS 16.1, *)
final class LiveActivityController {
    static let shared = LiveActivityController()

    private var activity: Activity<NocturneActivityAttributes>?
    private var lastState: NocturneActivityAttributes.ContentState?
    private var lastPush = Date.distantPast

    func adoptExisting() {
        let existing = Activity<NocturneActivityAttributes>.activities
        activity = existing.first
        for extra in existing.dropFirst() {
            Task { await Self.endNow(extra) }
        }
    }

    /// Off by default: iOS already shows its own Now Playing player on the Lock Screen and in the
    /// Dynamic Island, so the Live Activity would be a second, duplicate player.
    static let enabledKey = "liveActivityEnabled"
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    func update(with snap: NowPlayingSnapshot, engine: PlayerEngine) {
        guard Self.isEnabled else { end(); return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let trackId = snap.trackId else { end(); return }
        let state = NocturneActivityAttributes.ContentState(
            trackId: trackId, title: snap.title, artist: snap.artist, playlist: snap.playlist,
            isPlaying: snap.isPlaying, position: snap.position, duration: snap.duration, updatedAt: snap.updatedAt,
            artworkFile: snap.artworkFile, artworkData: snap.artworkFile == nil ? Self.tinyArtwork(engine.current) : nil,
            language: L10n.current.code
        )
        if let activity, activity.activityState != .ended && activity.activityState != .dismissed {
            if let last = lastState, Self.equivalent(last, state) { return }
            // Seek-only changes are throttled to one push per second.
            if let last = lastState, last.trackId == state.trackId, last.isPlaying == state.isPlaying,
               Date().timeIntervalSince(lastPush) < 1 {
                return
            }
            lastState = state
            lastPush = Date()
            Task { await Self.push(state, to: activity) }
        } else if snap.isPlaying {
            start(state)
        }
    }

    private func start(_ state: NocturneActivityAttributes.ContentState) {
        do {
            if #available(iOS 16.2, *) {
                activity = try Activity.request(
                    attributes: NocturneActivityAttributes(),
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
            } else {
                activity = try Activity.request(attributes: NocturneActivityAttributes(), contentState: state, pushType: nil)
            }
            lastState = state
            lastPush = Date()
        } catch {
            // Not allowed right now (e.g. started from the background): the lock screen still has the
            // system Now Playing controls; the activity starts next time playback starts in the app.
        }
    }

    func end() {
        if activity == nil {
            // Also clear cards left from an earlier run.
            for a in Activity<NocturneActivityAttributes>.activities { Task { await Self.endNow(a) } }
            return
        }
        guard let activity else { return }
        self.activity = nil
        lastState = nil
        Task { await Self.endNow(activity) }
    }

    private static var tinyCache: (id: String, data: Data?)?

    /// ~48 px JPEG that fits in the activity payload (ActivityKit allows ~4 KB in total).
    private static func tinyArtwork(_ track: Track?) -> Data? {
        guard let track else { return nil }
        if let c = tinyCache, c.id == track.id { return c.data }
        var result: Data?
        if let image = Artwork.load(track.artworkFile) {
            for (side, quality) in [(56.0, 0.55), (44.0, 0.45), (36.0, 0.4)] {
                if let data = Artwork.resized(image, side: CGFloat(side)).jpegData(compressionQuality: CGFloat(quality)), data.count <= 1700 {
                    result = data
                    break
                }
            }
        }
        tinyCache = (track.id, result)
        return result
    }

    private static func equivalent(_ a: NocturneActivityAttributes.ContentState, _ b: NocturneActivityAttributes.ContentState) -> Bool {
        a.trackId == b.trackId && a.title == b.title && a.artist == b.artist && a.playlist == b.playlist &&
            a.isPlaying == b.isPlaying && a.artworkFile == b.artworkFile && a.language == b.language &&
            abs(a.trackStart.timeIntervalSince(b.trackStart)) < 1.5 && abs(a.duration - b.duration) < 1
    }

    private static func push(_ state: NocturneActivityAttributes.ContentState, to activity: Activity<NocturneActivityAttributes>) async {
        if #available(iOS 16.2, *) {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        } else {
            await activity.update(using: state)
        }
    }

    private static func endNow(_ activity: Activity<NocturneActivityAttributes>) async {
        if #available(iOS 16.2, *) {
            await activity.end(nil, dismissalPolicy: .immediate)
        } else {
            await activity.end(using: nil, dismissalPolicy: .immediate)
        }
    }
}
#endif
