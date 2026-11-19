import UIKit

/// The picture that shows through the glyphs: a downscaled private copy of the user's choice.
enum PictureStore {
    private static let maxSide: CGFloat = 2400

    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("picture.jpg")
    }

    /// Re-renders the image upright and at most ~2400 px on the long side, then stores it.
    static func save(_ image: UIImage) -> Bool {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return false }
        let ratio = min(1, maxSide / longest)
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = normalized.jpegData(compressionQuality: 0.92) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func load() -> CGImage? {
        UIImage(contentsOfFile: url.path)?.cgImage
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }

    #if DEBUG
    /// A test picture for CI screenshots (launch with `-debugPicture YES`).
    static func makeDebugPicture() {
        let size = CGSize(width: 1200, height: 1200)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let green = UIColor(red: 0.2, green: 1, blue: 0.55, alpha: 1)
            green.setStroke()
            ctx.cgContext.setLineWidth(70)
            ctx.cgContext.strokeEllipse(in: CGRect(x: 160, y: 160, width: 880, height: 880))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 380),
                .foregroundColor: green,
            ]
            ("BAV" as NSString).draw(at: CGPoint(x: 215, y: 390), withAttributes: attrs)
        }
        _ = save(image)
    }
    #endif
}
