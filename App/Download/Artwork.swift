import UIKit

/// Cover art: YouTube thumbnail, center-cropped to a square, stored in Application Support/Artwork.
enum Artwork {
    /// Downloads the best thumbnail for `videoId`; returns the stored file name or nil.
    static func download(videoId: String) async -> String? {
        let candidates = ["maxresdefault", "sddefault", "hqdefault"].map {
            URL(string: "https://i.ytimg.com/vi/\(videoId)/\($0).jpg")!
        }
        for url in candidates {
            guard let result = try? await URLSession.shared.data(from: url),
                  (result.1 as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: result.0), image.size.width > 130 else { continue }
            guard let square = squareCrop(image, maxSide: 720), let jpeg = square.jpegData(compressionQuality: 0.85) else { continue }
            let name = "\(videoId).jpg"
            do {
                try jpeg.write(to: Storage.artworkDir.appendingPathComponent(name), options: .atomic)
                return name
            } catch {
                return nil
            }
        }
        return nil
    }

    /// Crops the 16:9 picture area (thumbnails are letterboxed to 4:3) to a centered square.
    static func squareCrop(_ image: UIImage, maxSide: CGFloat) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        // Visible 16:9 region inside the frame.
        let contentH = min(h, w * 9 / 16)
        let side = min(w, contentH)
        let rect = CGRect(x: (w - side) / 2, y: (h - side) / 2, width: side, height: side).integral
        guard let cropped = cg.cropping(to: rect) else { return nil }
        let out = min(maxSide, side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: format).image { _ in
            UIImage(cgImage: cropped).draw(in: CGRect(x: 0, y: 0, width: out, height: out))
        }
    }

    static func load(_ file: String?) -> UIImage? {
        guard let file else { return nil }
        return UIImage(contentsOfFile: Storage.artworkDir.appendingPathComponent(file).path)
    }

    static func resized(_ image: UIImage, side: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
    }
}

/// Small in-memory cache for list thumbnails.
final class ArtworkCache {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSString, UIImage>()

    init() { cache.countLimit = 300 }

    func image(_ file: String?) -> UIImage? {
        guard let file else { return nil }
        if let hit = cache.object(forKey: file as NSString) { return hit }
        guard let img = Artwork.load(file) else { return nil }
        cache.setObject(img, forKey: file as NSString)
        return img
    }

    func invalidate(_ file: String?) {
        guard let file else { return }
        cache.removeObject(forKey: file as NSString)
    }
}
