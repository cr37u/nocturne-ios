import Foundation
import YouTubeKit

/// A direct, downloadable audio stream.
struct ResolvedStream {
    let url: URL
    /// File extension to save with ("m4a").
    let fileExtension: String
    /// Human format name ("m4a").
    let format: String
    /// Size in bytes when known (googlevideo `clen`), else nil.
    let contentLength: Int64?
}

/// Swappable YouTube stream extractor. When YouTube changes, update / replace the implementation
/// (or the YouTubeKit package version) without touching the rest of the app.
protocol StreamResolver {
    var name: String { get }
    var version: String { get }
    func resolveAudio(videoId: String) async throws -> ResolvedStream
}

/// YouTubeKit-backed resolver: best audio-only m4a/AAC stream (plays natively, no ffmpeg).
struct YouTubeKitResolver: StreamResolver {
    var name: String { "YouTubeKit" }

    var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "NCYouTubeKitVersion") as? String) ?? "?"
    }

    func resolveAudio(videoId: String) async throws -> ResolvedStream {
        let video = YouTube(videoID: videoId)
        do {
            let streams = try await video.streams
            let m4a = streams.filterAudioOnly().filter { $0.fileExtension == .m4a }
            guard let best = m4a.highestAudioBitrateStream() else {
                throw ErrorKind.noAudio
            }
            return ResolvedStream(
                url: best.url,
                fileExtension: "m4a",
                format: "m4a",
                contentLength: Self.clen(best.url)
            )
        } catch let kind as ErrorKind {
            throw kind
        } catch {
            throw ErrorKind.from(error)
        }
    }

    static func clen(_ url: URL) -> Int64? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "clen" })?.value.flatMap(Int64.init)
    }
}
