import SwiftUI
import UIKit

/// Classifies the device from its safe-area insets and screen width (never from hard-coded
/// notch / island sizes), with the `utsname` model identifier only as extra information.
/// Unknown future models fall into the closest class automatically.
enum DeviceProfile: String {
    /// iPhone SE 2/3, 8: top inset ~20 pt, no bottom inset.
    case homeButton
    /// iPhone X – 14, 12/13 mini: top inset 44–50 pt, bottom 34 pt.
    case notch
    /// iPhone 14 Pro, 15, 16, 17 series: top inset ≥ 51 pt.
    case dynamicIsland
    /// Plus / Pro Max: width ≥ 428 pt.
    case large

    static func classify(safeTop: CGFloat, safeBottom: CGFloat, width: CGFloat) -> DeviceProfile {
        if width >= 428 { return .large }
        if safeBottom < 1 && safeTop <= 24 { return .homeButton }
        if safeTop >= 51 { return .dynamicIsland }
        return .notch
    }

    /// True when the top inset is the island's (also for Pro Max models in the `.large` class).
    static func hasDynamicIsland(safeTop: CGFloat) -> Bool { safeTop >= 51 }

    static var modelIdentifier: String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return sim }
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        return mirror.children.reduce(into: "") { acc, el in
            if let v = el.value as? Int8, v != 0 { acc.append(Character(UnicodeScalar(UInt8(v)))) }
        }
    }

    var label: String {
        switch self {
        case .homeButton: return "Home button"
        case .notch: return "Notch"
        case .dynamicIsland: return "Dynamic Island"
        case .large: return "Plus / Pro Max"
        }
    }
}

/// Layout metrics derived from the profile + screen width (paddings, artwork and fonts scale with
/// the width, so new models work without changes). Values match the iOS design boards.
struct Metrics: Equatable {
    var profile: DeviceProfile
    var width: CGFloat
    var safeTop: CGFloat
    var safeBottom: CGFloat

    static let fallback = Metrics(profile: .notch, width: 390, safeTop: 47, safeBottom: 34)

    /// 375 → 1.0, 430 → 1.147
    var scale: CGFloat { max(0.85, min(1.25, width / 375)) }

    // MARK: Library (boards 01 / 04)

    /// 16 pt on 375, 22 pt on 430.
    var hPad: CGFloat { (16 + (width - 375) * (6.0 / 55.0)).clamped(14, 24) }
    /// Extra top padding below the status bar / notch / island.
    var topPad: CGFloat { profile == .homeButton ? 12 : 9 }
    var brandFont: CGFloat {
        switch profile {
        case .homeButton: return 20
        case .large: return 24
        default: return 22
        }
    }
    var thumb: CGFloat {
        switch profile {
        case .homeButton: return 46
        case .large: return 56
        default: return 50
        }
    }
    var thumbRadius: CGFloat { (thumb * 0.28).rounded() }
    var rowPad: CGFloat { profile == .large ? 8 : (profile == .homeButton ? 6 : 7) }
    var rowRadius: CGFloat { profile == .large ? 18 : 16 }
    var rowTitle: CGFloat {
        switch profile {
        case .homeButton: return 14
        case .large: return 16
        default: return 15
        }
    }
    var rowSubtitle: CGFloat { profile == .homeButton ? 12 : 13 }

    // MARK: Mini-player

    var miniSide: CGFloat { profile == .large ? 14 : 10 }
    /// Distance from the bottom of the screen: 12 pt (SE), 40 pt (Pro Max / Face ID: safe area + 6).
    var miniBottomFromScreen: CGFloat { max(12, safeBottom + 6) }
    var fadeHeight: CGFloat { profile == .large ? 200 : 130 }
    /// Space the floating mini-player covers above the safe area (8 top + 75 player + bottom gap + 14).
    var miniPlayerClearance: CGFloat { 8 + 75 + max(0, miniBottomFromScreen - safeBottom) + 14 }

    // MARK: Now Playing (boards 02 / 03)

    var npPad: CGFloat { 24 * min(1, scale) }
    /// Artwork = width − 48 (342 on 390, 345 on 393), shrunk when the height is short (SE).
    func npArtwork(availableHeight: CGFloat) -> CGFloat {
        let byWidth = width - 2 * npPad
        // Everything else on the screen needs ~ 390 pt (top bar, title, seek bar, controls, volume).
        let byHeight = availableHeight - (profile == .homeButton ? 360 : 400)
        return max(180, min(byWidth, byHeight))
    }
    var npBottomPad: CGFloat { safeBottom > 0 ? 10 : 16 }
    var npGap: CGFloat { profile == .homeButton ? 18 : 28 }
}

extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(hi, Swift.max(lo, self)) }
}

private struct MetricsKey: EnvironmentKey {
    static let defaultValue = Metrics.fallback
}

extension EnvironmentValues {
    var metrics: Metrics {
        get { self[MetricsKey.self] }
        set { self[MetricsKey.self] = newValue }
    }
}
