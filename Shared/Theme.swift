import SwiftUI
import UIKit
import CoreText

// MARK: - Colors (same tokens as the Android app and the iOS boards)

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum NC {
    static let bg = Color(hex: 0x0A0A14)
    static let surface = Color(hex: 0x141426)
    static let elevated = Color(hex: 0x1C1C33)
    static let miniPlayer = Color(hex: 0x161630)
    static let progressTrack = Color(hex: 0x2A2A48)
    static let text = Color(hex: 0xF1F1F7)
    static let text2 = Color(hex: 0x9A9AB8)
    static let onGradient = Color(hex: 0xD4D4EA)
    static let onDark2 = Color(hex: 0xB8B8D4)
    static let placeholder = Color(hex: 0x8A8AA8)
    static let gradStart = Color(hex: 0x1E40AF)
    static let gradEnd = Color(hex: 0x3B0764)
    static let brightStart = Color(hex: 0x3B6CF6)
    static let brightEnd = Color(hex: 0x7C3AED)
    static let artStart = Color(hex: 0x2B4FD0)
    static let artEnd = Color(hex: 0x5B21B6)
    /// Amber is used ONLY for active states.
    static let amber = Color(hex: 0xF5B942)
    static let amberBg = Color(hex: 0xF5B942, alpha: 0.16)
    static let error = Color(hex: 0xF87171)
    static let onGradientButton = Color(hex: 0xF1F1F7, alpha: 0.12)
    static let playIcon = Color(hex: 0x3B0764)
    static let glow = Color(hex: 0x7C3AED, alpha: 0.7)
    static let shadow = Color(hex: 0x0A0A14, alpha: 0.55)

    /// Primary gradient (135°) for buttons, logo, covers.
    static var primary: LinearGradient {
        LinearGradient(colors: [gradStart, gradEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Bright gradient for thin bars (90°).
    static var brightHorizontal: LinearGradient {
        LinearGradient(colors: [brightStart, brightEnd], startPoint: .leading, endPoint: .trailing)
    }

    /// Bright gradient for borders (135°).
    static var brightDiagonal: LinearGradient {
        LinearGradient(colors: [brightStart, brightEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Now Playing artwork placeholder (135°, #2B4FD0 → #5B21B6).
    static var artwork: LinearGradient {
        LinearGradient(colors: [artStart, artEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private static let coverPairs: [(UInt32, UInt32)] = [
        (0x1E40AF, 0x3B0764), (0x312E81, 0x6D28D9), (0x1D4ED8, 0x4C1D95), (0x0F172A, 0x4338CA),
        (0x3730A3, 0x581C87), (0x1E3A8A, 0x7E22CE), (0x172554, 0x5B21B6),
    ]

    /// Deterministic artwork-less cover gradient for a track / playlist id (stable across launches).
    static func cover(_ seed: String?) -> LinearGradient {
        let pair = coverPairs[stableHash(seed ?? "") % coverPairs.count]
        return LinearGradient(colors: [Color(hex: pair.0), Color(hex: pair.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func stableHash(_ s: String) -> Int {
        var h: UInt32 = 5381
        for b in s.utf8 { h = (h &* 33) &+ UInt32(b) }
        return Int(h & 0x7FFF_FFFF)
    }
}

/// CSS-style `linear-gradient(<angle>deg, …)` that matches the boards for any aspect ratio
/// (0° points up, 90° to the right; the gradient line spans the corners like CSS).
struct CSSLinearGradient: View {
    let angle: Double
    let stops: [Gradient.Stop]

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1), h = max(geo.size.height, 1)
            let rad = angle * .pi / 180
            let dx = sin(rad), dy = -cos(rad)
            let half = (abs(w * dx) + abs(h * dy)) / 2
            let start = UnitPoint(x: (w / 2 - dx * half) / w, y: (h / 2 - dy * half) / h)
            let end = UnitPoint(x: (w / 2 + dx * half) / w, y: (h / 2 + dy * half) / h)
            LinearGradient(stops: stops, startPoint: start, endPoint: end)
        }
    }

    /// Now Playing background: 170°, #1E40AF 0% → #3B0764 55% → #0A0A14 100%.
    static var nowPlaying: CSSLinearGradient {
        CSSLinearGradient(angle: 170, stops: [
            .init(color: NC.gradStart, location: 0),
            .init(color: NC.gradEnd, location: 0.55),
            .init(color: NC.bg, location: 1),
        ])
    }
}

// MARK: - Typography (Manrope, bundled as static weights)

enum ManropeWeight: String, CaseIterable {
    case extraLight = "Manrope-ExtraLight"
    case regular = "Manrope-Regular"
    case medium = "Manrope-Medium"
    case semibold = "Manrope-SemiBold"
    case bold = "Manrope-Bold"
    case extraBold = "Manrope-ExtraBold"
}

extension Font {
    /// Manrope that scales with Dynamic Type relative to `style`.
    static func manrope(_ size: CGFloat, _ weight: ManropeWeight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: style)
    }

    /// Manrope at a fixed size (for places where scaling would break the layout: widgets, Live Activity, tab pills).
    static func manropeFixed(_ size: CGFloat, _ weight: ManropeWeight = .regular) -> Font {
        .custom(weight.rawValue, fixedSize: size)
    }
}

enum FontRegistry {
    private static var done = false

    /// Registers the bundled fonts at runtime too (UIAppFonts covers it normally; this is a safety net for extensions).
    static func registerIfNeeded() {
        guard !done else { return }
        done = true
        for weight in ManropeWeight.allCases {
            guard let url = Bundle.main.url(forResource: weight.rawValue, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

// MARK: - Radii

enum Radius {
    static let iconButton: CGFloat = 14
    static let input: CGFloat = 18
    static let card: CGFloat = 20
    static let cardLarge: CGFloat = 22
    static let miniPlayer: CGFloat = 22
    static let nowPlayingArtwork: CGFloat = 28
    static let sheet: CGFloat = 28
}
