import Foundation
import GRDB
import AVFoundation
import MediaPlayer
import Combine
import UIKit

enum RepeatMode: Int, Codable {
    case off = 0, all = 1, one = 2

    var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }

    var labelKey: String {
        switch self {
        case .off: return "repeat_off"
        case .all: return "repeat_all"
        case .one: return "repeat_one"
        }
    }
}

/// Where playback started ("SE REDĂ DIN PLAYLIST · Noaptea târziu").
struct PlaybackContext: Codable, Equatable {
    var playlistId: Int64?
    var label: String?

    var isPlaylist: Bool { playlistId != nil }
    static let library = PlaybackContext(playlistId: nil, label: nil)
}

/// Position / duration ticker, separate from the engine so only progress views redraw twice a second.
final class PlaybackClock: ObservableObject {
    @Published var position: Double = 0
    @Published var duration: Double = 0

    var fraction: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }
}

/// The player: AVQueuePlayer with the current + next item preloaded (gapless auto-advance, also in
/// the background), lock screen / Control Center / AirPods controls, interruption + route handling,
/// and the queue / last track / position restored after a restart.
final class PlayerEngine: NSObject, ObservableObject {
    static let shared = PlayerEngine()

    @Published private(set) var queue: [Track] = []
    @Published private(set) var index: Int = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var shuffle = false
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var context: PlaybackContext = .library

    let clock = PlaybackClock()

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }
    var upNext: Track? { nextIndex(userAction: false).map { queue[$0] } }
    var hasTrack: Bool { current != nil }

    /// Notified on track change, play/pause, seek, metadata edit (Live Activity, widgets).
    let stateChanged = PassthroughSubject<Void, Never>()

    private let player = AVQueuePlayer()
    private var currentItem: AVPlayerItem?
    private var nextItem: AVPlayerItem?
    private var originalQueue: [Track]?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var wasPlayingBeforeInterruption = false
    private var lastSavedPosition: Double = 0
    private var demoMode: Bool { ProcessInfo.processInfo.arguments.contains("-demoData") }
    private let db = AppDatabase.shared

    private override init() {
        super.init()
        player.automaticallyWaitsToMinimizeStalling = false
        observePlayer()
        Library.shared.tracksChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tracks in self?.libraryChanged(tracks) }
            .store(in: &cancellables)
    }

    // MARK: - setup

    func configureAudioSession() {
        let s = AVAudioSession.sharedInstance()
        applyCategory()
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleInterruption(_:)), name: AVAudioSession.interruptionNotification, object: s)
        nc.addObserver(self, selector: #selector(handleRouteChange(_:)), name: AVAudioSession.routeChangeNotification, object: s)
        nc.addObserver(self, selector: #selector(handleMediaReset(_:)), name: AVAudioSession.mediaServicesWereResetNotification, object: s)
        setupRemoteCommands()
    }

    private func applyCategory() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
    }

    private func observePlayer() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            self?.tick(time)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(itemDidEnd(_:)), name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(itemFailed(_:)), name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, !self.demoMode else { return }
                let playing = status != .paused
                if playing != self.isPlaying {
                    self.isPlaying = playing
                    self.updateNowPlayingInfo()
                    self.stateChanged.send()
                }
            }
            .store(in: &cancellables)
    }

    private func tick(_ time: CMTime) {
        let pos = CMTimeGetSeconds(time)
        if pos.isFinite { clock.position = pos }
        if let item = currentItem {
            let d = CMTimeGetSeconds(item.duration)
            if d.isFinite && d > 0 && abs(d - clock.duration) > 0.5 { clock.duration = d; updateNowPlayingInfo() }
        }
        if abs(clock.position - lastSavedPosition) >= 5 {
            lastSavedPosition = clock.position
            db.setSetting("player.position", String(clock.position))
        }
    }

    // MARK: - public API

    /// Plays `tracks` starting at `startIndex`.
    func play(_ tracks: [Track], startAt startIndex: Int = 0, context: PlaybackContext = .library, shuffled: Bool = false) {
        guard !tracks.isEmpty else { return }
        self.context = context
        originalQueue = nil
        if shuffled {
            var list = tracks
            list.shuffle()
            originalQueue = tracks
            queue = list
            index = 0
            shuffle = true
        } else {
            queue = tracks
            index = max(0, min(startIndex, tracks.count - 1))
            shuffle = false
        }
        loadCurrent(autoplay: true)
        saveQueue()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    func resume() {
        guard current != nil else { return }
        if currentItem == nil { loadCurrent(autoplay: true, seekTo: clock.position); return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
        stateChanged.send()
    }

    func pause() {
        player.pause()
        isPlaying = false
        db.setSetting("player.position", String(clock.position))
        updateNowPlayingInfo()
        stateChanged.send()
    }

    func next() {
        guard let n = nextIndex(userAction: true) else { return }
        index = n
        loadCurrent(autoplay: isPlaying)
        saveIndex()
    }

    /// Restarts the track when more than 3 s in, otherwise goes to the previous one.
    func previous() {
        if clock.position > 3 || queue.count <= 1 {
            seek(to: 0)
            return
        }
        if index > 0 {
            index -= 1
        } else if repeatMode == .all {
            index = queue.count - 1
        } else {
            seek(to: 0)
            return
        }
        loadCurrent(autoplay: true)
        saveIndex()
    }

    func seek(to seconds: Double) {
        let target = max(0, seconds)
        clock.position = target
        if currentItem == nil {
            db.setSetting("player.position", String(target))
        } else {
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateNowPlayingInfo()
                    self?.stateChanged.send()
                }
            }
        }
        updateNowPlayingInfo()
        stateChanged.send()
    }

    func playAt(_ i: Int) {
        guard queue.indices.contains(i) else { return }
        index = i
        loadCurrent(autoplay: true)
        saveIndex()
    }

    func toggleShuffle() {
        guard let cur = current else { shuffle.toggle(); return }
        if shuffle {
            // Back to the original order, keeping the current track.
            let base = (originalQueue ?? queue).filter { t in queue.contains(where: { $0.id == t.id }) }
            queue = base
            index = queue.firstIndex(where: { $0.id == cur.id }) ?? 0
            originalQueue = nil
            shuffle = false
        } else {
            originalQueue = queue
            var rest = queue
            rest.remove(at: index)
            rest.shuffle()
            queue = [cur] + rest
            index = 0
            shuffle = true
        }
        rebuildNextItem()
        saveQueue()
        updateRemoteCommandState()
        stateChanged.send()
    }

    func cycleRepeat() {
        repeatMode = repeatMode.next
        rebuildNextItem()
        db.setSetting("player.repeat", String(repeatMode.rawValue))
        updateRemoteCommandState()
        stateChanged.send()
    }

    func setRepeat(_ mode: RepeatMode) {
        repeatMode = mode
        rebuildNextItem()
        db.setSetting("player.repeat", String(mode.rawValue))
        updateRemoteCommandState()
        stateChanged.send()
    }

    func playNext(_ track: Track) {
        if queue.isEmpty { play([track]); return }
        queue.removeAll { $0.id == track.id && $0.id != current?.id }
        let insertAt = min(index + 1, queue.count)
        queue.insert(track, at: insertAt)
        originalQueue?.append(track)
        rebuildNextItem()
        saveQueue()
    }

    func addToQueue(_ track: Track) {
        if queue.isEmpty { play([track]); return }
        guard !queue.contains(where: { $0.id == track.id }) else { return }
        queue.append(track)
        originalQueue?.append(track)
        rebuildNextItem()
        saveQueue()
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        let currentId = current?.id
        queue.move(fromOffsets: source, toOffset: destination)
        index = queue.firstIndex(where: { $0.id == currentId }) ?? 0
        rebuildNextItem()
        saveQueue()
    }

    func removeFromQueue(at offsets: IndexSet) {
        let currentId = current?.id
        let removingCurrent = offsets.contains(index)
        queue.remove(atOffsets: offsets)
        if queue.isEmpty { stop(); return }
        if removingCurrent {
            index = min(offsets.first ?? 0, queue.count - 1)
            loadCurrent(autoplay: isPlaying)
        } else {
            index = queue.firstIndex(where: { $0.id == currentId }) ?? 0
            rebuildNextItem()
        }
        saveQueue()
    }

    func stop() {
        player.pause()
        player.removeAllItems()
        currentItem = nil
        nextItem = nil
        queue = []
        index = 0
        isPlaying = false
        clock.position = 0
        clock.duration = 0
        saveQueue()
        updateNowPlayingInfo()
        stateChanged.send()
    }

    func handle(_ command: PlayerCommand) {
        switch command {
        case .toggle: togglePlayPause()
        case .next: next()
        case .previous: previous()
        case .shuffle: toggleShuffle()
        case .cycleRepeat: cycleRepeat()
        }
    }

    // MARK: - queue mechanics

    private func nextIndex(userAction: Bool) -> Int? {
        guard !queue.isEmpty else { return nil }
        if index + 1 < queue.count { return index + 1 }
        if repeatMode == .all || (userAction && repeatMode == .one) { return 0 }
        return nil
    }

    private func makeItem(_ track: Track) -> AVPlayerItem? {
        guard track.fileExists else { return nil }
        let item = AVPlayerItem(url: track.fileURL)
        item.preferredForwardBufferDuration = 0
        return item
    }

    private func loadCurrent(autoplay: Bool, seekTo: Double = 0) {
        player.pause()
        player.removeAllItems()
        currentItem = nil
        nextItem = nil
        clock.position = seekTo
        guard let track = current else {
            isPlaying = false
            updateNowPlayingInfo()
            stateChanged.send()
            return
        }
        clock.duration = track.duration
        guard let item = makeItem(track) else {
            // Missing file (deleted from Files): skip to the next playable track.
            if !demoMode, let n = nextIndex(userAction: false), n != index, queue.contains(where: { $0.fileExists }) {
                index = n
                loadCurrent(autoplay: autoplay)
            } else {
                isPlaying = false
                updateNowPlayingInfo()
                stateChanged.send()
            }
            return
        }
        currentItem = item
        player.insert(item, after: nil)
        if seekTo > 0 {
            player.seek(to: CMTime(seconds: seekTo, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        rebuildNextItem()
        if autoplay {
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
        } else {
            isPlaying = false
        }
        updateNowPlayingInfo()
        stateChanged.send()
    }

    /// Keeps exactly [current, next] in the AVQueuePlayer so the next track starts gaplessly.
    private func rebuildNextItem() {
        if let n = nextItem {
            player.remove(n)
            nextItem = nil
        }
        player.actionAtItemEnd = repeatMode == .one ? .none : .advance
        guard repeatMode != .one, let cur = currentItem, let n = nextIndex(userAction: false), n != index,
              let item = makeItem(queue[n]) else { return }
        if player.canInsert(item, after: cur) {
            player.insert(item, after: cur)
            nextItem = item
        }
    }

    @objc private func itemDidEnd(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let ended = note.object as? AVPlayerItem, ended === self.currentItem else { return }
            if self.repeatMode == .one {
                self.player.seek(to: .zero)
                self.player.play()
                return
            }
            if let n = self.nextIndex(userAction: false), let upcoming = self.nextItem {
                // AVQueuePlayer already moved on to the preloaded item (gapless).
                self.index = n
                self.currentItem = upcoming
                self.nextItem = nil
                self.clock.position = 0
                self.clock.duration = self.queue[n].duration
                if self.player.currentItem !== upcoming {
                    self.player.removeAllItems()
                    self.player.insert(upcoming, after: nil)
                    self.player.play()
                }
                self.rebuildNextItem()
                self.saveIndex()
                self.updateNowPlayingInfo()
                self.stateChanged.send()
            } else if let n = self.nextIndex(userAction: false) {
                self.index = n
                self.loadCurrent(autoplay: true)
                self.saveIndex()
            } else {
                // End of the queue: stop on the last track, rewound.
                self.player.pause()
                self.isPlaying = false
                self.currentItem = nil
                self.player.removeAllItems()
                self.clock.position = 0
                self.db.setSetting("player.position", "0")
                self.updateNowPlayingInfo()
                self.stateChanged.send()
                NotificationCenter.default.post(name: .nocturneQueueEnded, object: nil)
            }
        }
    }

    @objc private func itemFailed(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let failed = note.object as? AVPlayerItem, failed === self.currentItem else { return }
            if let n = self.nextIndex(userAction: false) {
                self.index = n
                self.loadCurrent(autoplay: true)
            }
        }
    }

    // MARK: - library changes (edit details / delete)

    private func libraryChanged(_ tracks: [Track]) {
        guard !queue.isEmpty else { return }
        let byId = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let currentId = current?.id
        let updated = queue.compactMap { byId[$0.id] }
        let metadataChanged = updated != queue
        if updated.count != queue.count {
            // Some tracks were deleted.
            let currentRemoved = currentId.map { byId[$0] == nil } ?? false
            queue = updated
            originalQueue = originalQueue?.compactMap { byId[$0.id] }
            if queue.isEmpty { stop(); return }
            if currentRemoved {
                index = min(index, queue.count - 1)
                loadCurrent(autoplay: isPlaying)
            } else {
                index = queue.firstIndex(where: { $0.id == currentId }) ?? 0
                rebuildNextItem()
            }
            saveQueue()
        } else if metadataChanged {
            queue = updated
            originalQueue = originalQueue?.compactMap { byId[$0.id] }
            updateNowPlayingInfo()
            stateChanged.send()
        }
    }

    // MARK: - persistence

    private func saveQueue() {
        let ids = queue.map(\.id)
        let original = originalQueue?.map(\.id)
        let idx = index
        let ctx = context
        let shuffleOn = shuffle
        try? db.writer.write { db in
            try db.execute(sql: "DELETE FROM queue_items")
            for (i, id) in ids.enumerated() {
                try QueueEntry(position: i, trackId: id).insert(db)
            }
            try SettingRow(key: "player.index", value: String(idx)).save(db)
            try SettingRow(key: "player.shuffle", value: shuffleOn ? "1" : "0").save(db)
            if let data = try? JSONEncoder().encode(ctx), let json = String(data: data, encoding: .utf8) {
                try SettingRow(key: "player.context", value: json).save(db)
            }
            try SettingRow(key: "player.original", value: (original ?? []).joined(separator: ",")).save(db)
        }
        db.setSetting("player.position", String(clock.position))
    }

    private func saveIndex() {
        db.setSetting("player.index", String(index))
        db.setSetting("player.position", "0")
    }

    func savePosition() {
        db.setSetting("player.position", String(clock.position))
    }

    /// Restores the last queue, track and position (paused).
    func restore() {
        let ids: [String] = (try? db.writer.read { db in
            try String.fetchAll(db, sql: "SELECT trackId FROM queue_items ORDER BY position")
        }) ?? []
        let tracks = Library.shared.tracks(ids: ids)
        repeatMode = RepeatMode(rawValue: Int(db.setting("player.repeat") ?? "0") ?? 0) ?? .off
        guard !tracks.isEmpty else { return }
        queue = tracks
        index = min(Int(db.setting("player.index") ?? "0") ?? 0, tracks.count - 1)
        shuffle = db.setting("player.shuffle") == "1"
        if let original = db.setting("player.original"), !original.isEmpty {
            originalQueue = Library.shared.tracks(ids: original.split(separator: ",").map(String.init))
        }
        if let json = db.setting("player.context"), let data = json.data(using: .utf8),
           let ctx = try? JSONDecoder().decode(PlaybackContext.self, from: data) {
            context = ctx
        }
        let position = Double(db.setting("player.position") ?? "0") ?? 0
        loadCurrent(autoplay: false, seekTo: position)
        lastSavedPosition = position
        updateRemoteCommandState()
    }

    /// Demo state for CI screenshots: a queue that is "paused" at 1:42 without audio files.
    func loadDemo(_ tracks: [Track], context: PlaybackContext, position: Double, playing: Bool) {
        queue = tracks
        index = 0
        self.context = context
        clock.duration = tracks.first?.duration ?? 0
        clock.position = position
        isPlaying = playing
        repeatMode = .all
        stateChanged.send()
    }

    // MARK: - interruptions & routes

    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo, let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch type {
            case .began:
                self.wasPlayingBeforeInterruption = self.isPlaying
                self.isPlaying = false
                self.updateNowPlayingInfo()
                self.stateChanged.send()
            case .ended:
                let optRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                if AVAudioSession.InterruptionOptions(rawValue: optRaw).contains(.shouldResume) && self.wasPlayingBeforeInterruption {
                    self.resume()
                }
                self.wasPlayingBeforeInterruption = false
            @unknown default:
                break
            }
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        if reason == .oldDeviceUnavailable {
            // Headphones unplugged / Bluetooth disconnected → pause (Apple HIG).
            DispatchQueue.main.async { [weak self] in self?.pause() }
        }
    }

    @objc private func handleMediaReset(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyCategory()
            self.loadCurrent(autoplay: false, seekTo: self.clock.position)
        }
    }

    // MARK: - lock screen / Control Center / AirPods

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.resume() }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.pause() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.togglePlayPause() }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.next() }
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.previous() }
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let t = e.positionTime
            DispatchQueue.main.async { self?.seek(to: t) }
            return .success
        }
        c.changeShuffleModeCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangeShuffleModeCommandEvent else { return .commandFailed }
            let on = e.shuffleType != .off
            DispatchQueue.main.async {
                guard let self else { return }
                if on != self.shuffle { self.toggleShuffle() }
            }
            return .success
        }
        c.changeRepeatModeCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
            let mode: RepeatMode
            switch e.repeatType {
            case .one: mode = .one
            case .all: mode = .all
            default: mode = .off
            }
            DispatchQueue.main.async { self?.setRepeat(mode) }
            return .success
        }
        c.skipForwardCommand.isEnabled = false
        c.skipBackwardCommand.isEnabled = false
        c.seekForwardCommand.isEnabled = false
        c.seekBackwardCommand.isEnabled = false
        updateRemoteCommandState()
    }

    private func updateRemoteCommandState() {
        let c = MPRemoteCommandCenter.shared()
        c.changeShuffleModeCommand.currentShuffleType = shuffle ? .items : .off
        switch repeatMode {
        case .off: c.changeRepeatModeCommand.currentRepeatType = .off
        case .all: c.changeRepeatModeCommand.currentRepeatType = .all
        case .one: c.changeRepeatModeCommand.currentRepeatType = .one
        }
    }

    private var artworkCache: (id: String, file: String?, art: MPMediaItemArtwork?)?

    func updateNowPlayingInfo() {
        let center = MPNowPlayingInfoCenter.default()
        guard let track = current else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: clock.duration > 0 ? clock.duration : track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: clock.position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: index,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count,
        ]
        if let label = context.label { info[MPMediaItemPropertyAlbumTitle] = label }
        if artworkCache?.id != track.id || artworkCache?.file != track.artworkFile {
            let art = Artwork.load(track.artworkFile) ?? PlaceholderArt.image(seed: track.id)
            artworkCache = (track.id, track.artworkFile, Self.makeArtwork(art))
        }
        if let art = artworkCache?.art { info[MPMediaItemPropertyArtwork] = art }
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
    }

    /// Built outside any actor context: the request handler is called on a background queue.
    private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}

extension Notification.Name {
    static let nocturneQueueEnded = Notification.Name("nocturneQueueEnded")
}
