import CoreGraphics
import Foundation

/// The rain glyphs, drawn from strokes (see `GlyphData`) into small alpha masks once, so that
/// the rain only has to stamp the masks with a colour on every frame. No font file is involved.
///
/// Sizes: `cellWidth` / `cellHeight` are in points; the masks themselves have `scale` pixels per
/// point so that they stay sharp on Retina screens.
public final class GlyphAtlas {
    public let scale: CGFloat
    /// Size of one cell in whole points (does not depend on the screen scale).
    public let cellWidth: CGFloat
    public let cellHeight: CGFloat
    public let masks: [CGImage]

    public var count: Int { masks.count }

    /// Cell size in points for a nominal glyph height.
    public static func cellSize(glyphSize: CGFloat) -> (width: CGFloat, height: CGFloat) {
        let h = max((max(glyphSize, 2) * 1.15).rounded(.up), 6)
        let w = max((h * 0.62).rounded(.up), 4)
        return (w, h)
    }

    /// - Parameters:
    ///   - glyphSize: the nominal glyph height in points (the "size of symbols" setting).
    ///   - scale: pixels per point of the display.
    public init(glyphSize: CGFloat, scale: CGFloat) {
        let s = max(scale, 1)
        self.scale = s
        let size = GlyphAtlas.cellSize(glyphSize: glyphSize)
        cellWidth = size.width
        cellHeight = size.height
        let w = Int((size.width * s).rounded())
        let h = Int((size.height * s).rounded())
        masks = GlyphData.shapes.compactMap { GlyphAtlas.renderMask($0, width: w, height: h) }
    }

    /// The mask of glyph `index` (nil if the index is out of range).
    public func mask(_ index: Int) -> CGImage? {
        index >= 0 && index < masks.count ? masks[index] : nil
    }

    /// Draws one glyph as white strokes on black into an 8-bit gray bitmap and turns it into an
    /// image mask (sample 1 paints), which paints with the context's fill colour when drawn.
    static func renderMask(_ shape: GlyphShape, width w: Int, height h: Int) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }

        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setStrokeColor(gray: 1, alpha: 1)
        let lineWidth = max(1, CGFloat(h) * 0.13)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.square)
        ctx.setLineJoin(.miter)
        ctx.setMiterLimit(4)
        ctx.setShouldAntialias(true)

        // The glyph box inside the cell; the margins keep the square line caps inside the bitmap.
        let marginX = max(CGFloat(w) * 0.12, lineWidth / 2 + 0.5)
        let marginY = max(CGFloat(h) * 0.09, lineWidth / 2 + 0.5)
        let boxW = CGFloat(w) - 2 * marginX
        let boxH = CGFloat(h) - 2 * marginY
        let stepX = boxW / CGFloat(GlyphData.cols - 1)
        let stepY = boxH / CGFloat(GlyphData.rows - 1)

        func point(_ gx: Int, _ gy: Int) -> CGPoint {
            let x = shape.mirror ? GlyphData.cols - 1 - gx : gx
            // Grid rows grow downwards; the bitmap context's y axis points up.
            return CGPoint(x: marginX + CGFloat(x) * stepX, y: CGFloat(h) - (marginY + CGFloat(gy) * stepY))
        }

        for stroke in shape.strokes where stroke.count >= 4 {
            ctx.beginPath()
            ctx.move(to: point(stroke[0], stroke[1]))
            var i = 2
            while i + 1 < stroke.count {
                ctx.addLine(to: point(stroke[i], stroke[i + 1]))
                i += 2
            }
            ctx.strokePath()
        }

        guard let data = ctx.data,
              let provider = CGDataProvider(data: Data(bytes: data, count: w * h) as CFData)
        else { return nil }
        var decode: [CGFloat] = [1, 0]
        return CGImage(
            maskWidth: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
            provider: provider, decode: &decode, shouldInterpolate: true)
    }
}
