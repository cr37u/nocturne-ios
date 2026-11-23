import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Live Activity (lock screen on every model + Dynamic Island on island models).
@available(iOS 16.1, *)
struct NocturneActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var trackId: String
        var title: String
        var artist: String
        var playlist: String?
        var isPlaying: Bool
        /// Seconds into the track at `updatedAt`.
        var position: Double
        var duration: Double
        var updatedAt: Date
        /// File in the App Group `Artwork/` folder (nil → gradient + moon placeholder).
        var artworkFile: String?
        /// Tiny JPEG cover carried in the activity itself (used when there is no App Group).
        var artworkData: Data?
        /// UI language code at the time of the update (Live Activity strings follow the app).
        var language: String

        /// Start date of the track as if it had been playing continuously (for timer-driven progress).
        var trackStart: Date { updatedAt.addingTimeInterval(-position) }
        var trackEnd: Date { trackStart.addingTimeInterval(max(duration, 1)) }
        var progress: Double { duration > 0 ? max(0, min(1, position / duration)) : 0 }
    }

    var appName: String = "Nocturne"
}
#endif
