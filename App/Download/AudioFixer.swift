import Foundation
import AVFoundation

/// YouTube's audio-only m4a streams are DASH-fragmented files whose header often reports about twice
/// the real length: iOS then shows a doubled duration and plays silence after the music ends.
/// Re-muxing the samples into a plain m4a (no re-encoding, same quality) gives a correct header.
enum AudioFixer {
    enum FixError: Error { case noAudioTrack, writerFailed }

    /// Copies the audio samples of `source` into a new standard m4a at `destination`, keeping only
    /// the first `limitSeconds` (the real song length from YouTube) so the bogus tail is dropped.
    static func remux(_ source: URL, to destination: URL, limitSeconds: Double = 0) async throws {
        try? FileManager.default.removeItem(at: destination)
        let asset = AVURLAsset(url: source)
        guard let track = asset.tracks(withMediaType: .audio).first else { throw FixError.noAudioTrack }

        let reader = try AVAssetReader(asset: asset)
        if limitSeconds > 1 {
            reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: limitSeconds + 0.3, preferredTimescale: 44100))
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw FixError.writerFailed }
        reader.add(output)

        let writer = try AVAssetWriter(outputURL: destination, fileType: .m4a)
        let hint = track.formatDescriptions.first.map { $0 as! CMFormatDescription }
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: hint)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw FixError.writerFailed }
        writer.add(input)

        guard reader.startReading(), writer.startWriting() else { throw FixError.writerFailed }
        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "nocturne.remux")
        let box = OnceBox()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if let buffer = output.copyNextSampleBuffer() {
                        if !input.append(buffer) {
                            input.markAsFinished()
                            if box.fire() { cont.resume() }
                            return
                        }
                    } else {
                        input.markAsFinished()
                        if box.fire() { cont.resume() }
                        return
                    }
                }
            }
        }
        await writer.finishWriting()
        if reader.status == .failed || writer.status != .completed {
            try? FileManager.default.removeItem(at: destination)
            throw FixError.writerFailed
        }
    }

    /// Real length of an audio file in milliseconds (0 when unknown).
    static func durationMs(_ url: URL) -> Int64 {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let secs = CMTimeGetSeconds(asset.duration)
        return secs.isFinite && secs > 0 ? Int64(secs * 1000) : 0
    }

    static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    // MARK: - Repair songs downloaded before the fix

    // v2: the first repair kept the wrong timing; everything is re-checked and trimmed.
    private static let fixedKey = "remuxedTrackIds.v2"

    /// Re-muxes every track that hasn't been fixed yet (skips the one currently playing).
    static func repairLibrary(skipping currentId: @escaping () -> String?) async {
        let tracks = await MainActor.run { Library.shared.tracks }
        var fixed = Set(UserDefaults.standard.stringArray(forKey: fixedKey) ?? [])
        for track in tracks where !fixed.contains(track.id) && track.fileExists {
            if await MainActor.run(body: { currentId() }) == track.id { continue }
            let src = track.fileURL
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("fix-\(track.id).m4a")
            // Ask YouTube for the real length; fall back to the stored one.
            let ytSeconds = await YouTubeCatalog.shared.videoLength(track.id)
            let real = ytSeconds > 0 ? Double(ytSeconds) : track.duration
            let current = Double(durationMs(src)) / 1000
            if real > 0 && current > 0 && current <= real + 2 {
                // Already correct: just make sure the stored length matches.
                if abs(track.duration - current) > 2 {
                    let size = fileSize(src)
                    await MainActor.run { Library.shared.updateFileInfo(track.id, durationMs: Int64(current * 1000), sizeBytes: size) }
                }
                fixed.insert(track.id)
                UserDefaults.standard.set(Array(fixed), forKey: fixedKey)
                continue
            }
            do {
                try await remux(src, to: tmp, limitSeconds: real)
                var ms = durationMs(tmp)
                if real > 0 && Double(ms) / 1000 > real + 2 { ms = Int64(real * 1000) }
                guard ms > 0 else { throw FixError.writerFailed }
                _ = try FileManager.default.replaceItemAt(src, withItemAt: tmp)
                let size = fileSize(src)
                await MainActor.run { Library.shared.updateFileInfo(track.id, durationMs: ms, sizeBytes: size) }
            } catch {
                try? FileManager.default.removeItem(at: tmp)
            }
            // Mark it either way so a file that can't be fixed isn't retried on every launch.
            fixed.insert(track.id)
            UserDefaults.standard.set(Array(fixed), forKey: fixedKey)
        }
    }

    static func markFixed(_ id: String) {
        var fixed = Set(UserDefaults.standard.stringArray(forKey: fixedKey) ?? [])
        fixed.insert(id)
        UserDefaults.standard.set(Array(fixed), forKey: fixedKey)
    }
}

/// Fires exactly once (guards the continuation against a second callback).
private final class OnceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func fire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
