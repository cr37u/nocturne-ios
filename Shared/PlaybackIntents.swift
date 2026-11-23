import Foundation
import AppIntents

/// Commands the widgets / Live Activity can send to the player.
enum PlayerCommand: String {
    case toggle, next, previous, shuffle, cycleRepeat
}

/// The app installs `handler` at launch. Audio-playback intents run inside the app process
/// (iOS launches it in the background if needed), so the handler is present when `perform()` runs.
enum IntentBridge {
    static var handler: (@MainActor (PlayerCommand) -> Void)?

    @MainActor
    static func send(_ command: PlayerCommand) {
        handler?(command)
    }
}

@available(iOS 17.0, *)
struct TogglePlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play / Pause"
    static let isDiscoverable: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        await IntentBridge.send(.toggle)
        return .result()
    }
}

@available(iOS 17.0, *)
struct NextTrackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Next"
    static let isDiscoverable: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        await IntentBridge.send(.next)
        return .result()
    }
}

@available(iOS 17.0, *)
struct PreviousTrackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Previous"
    static let isDiscoverable: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        await IntentBridge.send(.previous)
        return .result()
    }
}

@available(iOS 17.0, *)
struct ToggleShuffleIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Shuffle"
    static let isDiscoverable: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        await IntentBridge.send(.shuffle)
        return .result()
    }
}

@available(iOS 17.0, *)
struct CycleRepeatIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Repeat"
    static let isDiscoverable: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        await IntentBridge.send(.cycleRepeat)
        return .result()
    }
}
