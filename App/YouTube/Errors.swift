import Foundation

/// Friendly, user-facing error categories (same keys as Android's `ErrorKind`).
enum ErrorKind: String, Error, CaseIterable {
    case invalidLink = "INVALID_LINK"
    case noInternet = "NO_INTERNET"
    case unavailable = "UNAVAILABLE"
    case ageRestricted = "AGE_RESTRICTED"
    case geoRestricted = "GEO_RESTRICTED"
    case privateVideo = "PRIVATE"
    case paid = "PAID"
    case captcha = "CAPTCHA"
    case bot = "BOT"
    case noAudio = "NO_AUDIO"
    case storage = "STORAGE"
    case generic = "GENERIC"

    var messageKey: String {
        switch self {
        case .invalidLink: return "error_invalid_link"
        case .noInternet: return "error_no_internet"
        case .unavailable: return "error_unavailable"
        case .ageRestricted: return "error_age_restricted"
        case .geoRestricted: return "error_geo_restricted"
        case .privateVideo: return "error_private"
        case .paid: return "error_paid"
        case .captcha: return "error_captcha"
        case .bot: return "error_bot"
        case .noAudio: return "error_no_audio"
        case .storage: return "error_storage"
        case .generic: return "error_generic"
        }
    }

    var message: String { L10n.t(messageKey) }

    var retryable: Bool {
        switch self {
        case .invalidLink, .ageRestricted, .geoRestricted, .privateVideo, .paid, .storage: return false
        default: return true
        }
    }

    static func from(key: String?) -> ErrorKind { key.flatMap(ErrorKind.init(rawValue:)) ?? .generic }

    /// Maps any error (URLSession, YouTubeKit, file system) to a friendly category.
    /// YouTubeKit errors are matched by description so extractor updates don't break the mapping.
    static func from(_ error: Error) -> ErrorKind {
        if let kind = error as? ErrorKind { return kind }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
                 NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed,
                 NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff, NSURLErrorSecureConnectionFailed:
                return .noInternet
            default:
                return .generic
            }
        }
        if ns.domain == NSCocoaErrorDomain && (ns.code == NSFileWriteOutOfSpaceError) { return .storage }
        if ns.domain == NSPOSIXErrorDomain && ns.code == 28 { return .storage } // ENOSPC
        let text = (String(describing: error) + " " + ns.localizedDescription).lowercased()
        if text.contains("age") && text.contains("restrict") { return .ageRestricted }
        if text.contains("private") { return .privateVideo }
        if text.contains("region") || text.contains("country") || text.contains("geo") { return .geoRestricted }
        if text.contains("member") || text.contains("paid") || text.contains("premium") { return .paid }
        if text.contains("bot") || text.contains("sign in") || text.contains("login") { return .bot }
        if text.contains("captcha") { return .captcha }
        if text.contains("unavailable") || text.contains("not available") || text.contains("removed") { return .unavailable }
        return .generic
    }
}
