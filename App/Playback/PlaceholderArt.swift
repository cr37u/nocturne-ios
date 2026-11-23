import UIKit

/// Artwork-less cover (lock screen / Control Center): gradient + white moon with sound wave,
/// like the Now Playing placeholder on the boards.
enum PlaceholderArt {
    private static var cache: [Int: UIImage] = [:]
    private static let lock = NSLock()

    private static let pairs: [(UInt32, UInt32)] = [
        (0x2B4FD0, 0x5B21B6), (0x312E81, 0x6D28D9), (0x1D4ED8, 0x4C1D95), (0x0F172A, 0x4338CA),
        (0x3730A3, 0x581C87), (0x1E3A8A, 0x7E22CE), (0x172554, 0x5B21B6),
    ]

    static func image(seed: String, side: CGFloat = 512) -> UIImage {
        let idx = NC.stableHash(seed) % pairs.count
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[idx] { return hit }
        let img = render(pair: pairs[idx], side: side)
        cache[idx] = img
        return img
    }

    private static func color(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private static func render(pair: (UInt32, UInt32), side: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            let cg = ctx.cgContext
            let colors = [color(pair.0).cgColor, color(pair.1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
            }
            // Moon + wave from the Lucide path data, 37.5% of the side, centered.
            let iconSide = side * 0.375
            let scale = iconSide / 24
            let origin = (side - iconSide) / 2
            let transform = CGAffineTransform(translationX: origin, y: origin).scaledBy(x: scale, y: scale)
            let path = SVGPath.parse("M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z").applying(transform).cgPath
            let wave = SVGPath.parse("M8 13v2M11 11v6M14 12.5v3").applying(transform).cgPath
            cg.setStrokeColor(UIColor(white: 0.95, alpha: 0.85).cgColor)
            cg.setLineWidth(1.2 * scale)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.addPath(path)
            cg.addPath(wave)
            cg.strokePath()
        }
    }
}
