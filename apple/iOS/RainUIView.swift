import UIKit
import CoreText
import BAVtrixCore

/// Draws the rain with Core Text and advances the simulation from a display link.
final class RainUIView: UIView {
    var config = RainConfig() {
        didSet {
            if config == oldValue { return }
            let layoutChanged = oldValue.glyphSize != config.glyphSize
                || oldValue.charset != config.charset
                || oldValue.specialStrings != config.specialStrings
            if layoutChanged {
                rebuildFonts()
                rebuildSim()
            } else {
                sim?.config = config
            }
            if oldValue.usePicture != config.usePicture || oldValue.pictureVersion != config.pictureVersion {
                reloadPicture()
            }
            setNeedsDisplay()
        }
    }

    private var sim: RainSim?
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var font: CTFont = CTFontCreateWithName("Menlo-Bold" as CFString, 14, nil)
    private var specialFont: CTFont = CTFontCreateWithName("Menlo" as CFString, 14, nil)
    private var glyphs: [CGGlyph] = []
    private var specialGlyphs: [CGGlyph] = []
    private var cellW: CGFloat = 8
    private var cellH: CGFloat = 14
    private var ascent: CGFloat = 11
    private var laidOutSize = CGSize.zero
    private var ticks = 0

    // The picture that shows through the glyphs, and the two offscreen layers used to compose it.
    private var pictureImage: CGImage?
    private var glyphLayer: CGContext?
    private var pictureLayer: CGContext?
    private var layerPixels = (w: 0, h: 0)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = .black
        contentMode = .redraw
        rebuildFonts()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Fonts, layout and picture

    /// Loads the bundled Matrix Code Font (registered at runtime), falling back to Menlo.
    private static func matrixFont(size: CGFloat) -> CTFont {
        if let url = Bundle.main.url(forResource: "MatrixCodeFont", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
               let first = descriptors.first {
                return CTFontCreateWithFontDescriptor(first, size, nil)
            }
        }
        return CTFontCreateWithName("Menlo-Bold" as CFString, size, nil)
    }

    private static func glyphs(for chars: [Character], in font: CTFont) -> [CGGlyph] {
        chars.map { ch in
            var utf16 = Array(String(ch).utf16)
            var out = [CGGlyph](repeating: 0, count: utf16.count)
            let ok = CTFontGetGlyphsForCharacters(font, &utf16, &out, utf16.count)
            return ok ? out[0] : 0
        }
    }

    private func rebuildFonts() {
        let size = CGFloat(config.glyphSize)
        font = RainUIView.matrixFont(size: size)
        specialFont = CTFontCreateWithName("Menlo" as CFString, size, nil)
        glyphs = RainUIView.glyphs(for: config.charsetChars, in: font)
        specialGlyphs = RainUIView.glyphs(for: config.specialChars, in: specialFont)

        var widest: CGFloat = 1
        var g = glyphs
        if !g.isEmpty {
            var advances = [CGSize](repeating: .zero, count: g.count)
            CTFontGetAdvancesForGlyphs(font, .horizontal, &g, &advances, g.count)
            widest = advances.map { $0.width }.max() ?? 1
        }
        cellW = max(ceil(widest), 3)
        ascent = CTFontGetAscent(font)
        cellH = max(ceil(ascent + CTFontGetDescent(font)), 5)
    }

    private func rebuildSim() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let cols = Int(bounds.width / cellW)
        let rows = Int(bounds.height / cellH)
        sim = RainSim(cols: cols, rows: rows, config: config, seed: UInt64(Date().timeIntervalSince1970 * 1000))
        laidOutSize = bounds.size
    }

    private func reloadPicture() {
        pictureImage = config.usePicture ? PictureStore.load() : nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != laidOutSize { rebuildSim() }
    }

    // MARK: Display link

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
            l.preferredFramesPerSecond = 30
            l.add(to: .main, forMode: .common)
            link = l
            lastTimestamp = 0
            UIApplication.shared.isIdleTimerDisabled = true
            reloadPicture()
        } else {
            link?.invalidate()
            link = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    @objc private func tick(_ l: CADisplayLink) {
        if lastTimestamp == 0 { lastTimestamp = l.timestamp }
        let dt = min(max((l.timestamp - lastTimestamp) * 1000, 1), 250)
        lastTimestamp = l.timestamp
        ticks += 1
        sim?.advance(dtMs: Float(dt))
        setNeedsDisplay()
    }

    // MARK: Drawing

    /// Draws every lit cell into `ctx`, which must use Core Graphics' usual y-up coordinates
    /// for a surface that is `height` points tall.
    @discardableResult
    private func drawGlyphs(_ ctx: CGContext, sim: RainSim, height: CGFloat, depthOnly: Bool = false) -> (lit: Int, drawn: Int) {
        let x0 = (bounds.width - CGFloat(sim.cols) * cellW) / 2
        let y0 = (bounds.height - CGFloat(sim.rows) * cellH) / 2
        var lit = 0
        var drawn = 0
        for row in 0..<sim.rows {
            for col in 0..<sim.cols {
                let cell = sim.cells[row * sim.cols + col]
                guard var c = Palette.color(cell: cell, row: row, sim: sim) else { continue }
                if depthOnly {
                    // Copy mode: only the depth matters, the glyph shows the picture dimmed by it.
                    let v = UInt8(Palette.depthLevel(cell: cell, row: row, sim: sim) * 255)
                    c = RGBA(v, v, v, c.a)
                }
                lit += 1
                let isSpecialGlyph = cell.flags & CellFlag.specialGlyph != 0
                let table = isSpecialGlyph ? specialGlyphs : glyphs
                let index = Int(cell.glyph)
                guard index < table.count, table[index] != 0 else { continue }

                ctx.setFillColor(red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255,
                                 blue: CGFloat(c.b) / 255, alpha: CGFloat(c.a) / 255)
                var glyph = table[index]
                // Baseline in y-up coordinates.
                let baselineFromTop = y0 + CGFloat(row) * cellH + ascent
                var position = CGPoint(x: x0 + CGFloat(col) * cellW, y: height - baselineFromTop)
                CTFontDrawGlyphs(isSpecialGlyph ? specialFont : font, &glyph, &position, 1, ctx)
                drawn += 1
            }
        }
        return (lit, drawn)
    }

    private func makeLayer(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    }

    /// Where the picture goes (y-up point coordinates): fitted whole, or covering the surface.
    private func pictureRect(for image: CGImage) -> CGRect {
        let pw = CGFloat(image.width), ph = CGFloat(image.height)
        let fitW = bounds.width / pw, fitH = bounds.height / ph
        let scale = config.pictureCover ? max(fitW, fitH) : min(fitW, fitH)
        let w = pw * scale, h = ph * scale
        return CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }

    /// Picture effect: the glyphs are drawn into a layer, the picture is kept only where they are
    /// (`destinationIn`) and the two are composed on the screen according to the blend mode.
    private func drawWithPicture(_ ctx: CGContext, sim: RainSim, picture: CGImage) -> (lit: Int, drawn: Int)? {
        let scale = max(contentScaleFactor, 1)
        let pw = Int(bounds.width * scale), ph = Int(bounds.height * scale)
        guard pw > 0, ph > 0 else { return nil }
        if layerPixels.w != pw || layerPixels.h != ph || glyphLayer == nil || pictureLayer == nil {
            glyphLayer = makeLayer(width: pw, height: ph)
            pictureLayer = makeLayer(width: pw, height: ph)
            layerPixels = (pw, ph)
        }
        guard let gctx = glyphLayer, let pctx = pictureLayer else { return nil }
        let full = CGRect(x: 0, y: 0, width: pw, height: ph)

        // 1. Coloured glyphs.
        gctx.clear(full)
        gctx.saveGState()
        gctx.scaleBy(x: scale, y: scale)
        gctx.textMatrix = .identity
        let stats = drawGlyphs(gctx, sim: sim, height: bounds.height, depthOnly: config.pictureBlend == 0)
        gctx.restoreGState()
        guard let glyphImage = gctx.makeImage() else { return nil }

        // 2. The picture, kept only where glyphs are.
        pctx.clear(full)
        pctx.saveGState()
        pctx.scaleBy(x: scale, y: scale)
        pctx.draw(picture, in: pictureRect(for: picture))
        pctx.restoreGState()
        pctx.setBlendMode(.destinationIn)
        pctx.draw(glyphImage, in: full)
        if config.pictureBlend == 0 {
            // Copy: dim the picture by the glyph's depth (the glyph layer holds grey levels here).
            pctx.setBlendMode(.multiply)
            pctx.draw(glyphImage, in: full)
        }
        pctx.setBlendMode(.normal)
        guard let pictureImage = pctx.makeImage() else { return nil }

        // 3. Compose on the screen (UIKit's context is y-down, so flip it).
        let area = CGRect(origin: .zero, size: bounds.size)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        switch config.pictureBlend {
        case 1: // OR: the picture, plus the glyph colour added on top
            ctx.draw(pictureImage, in: area)
            ctx.setBlendMode(.plusLighter)
            ctx.draw(glyphImage, in: area)
        case 2: // AND: the glyph colour multiplied by the picture
            ctx.draw(glyphImage, in: area)
            ctx.setBlendMode(.multiply)
            ctx.draw(pictureImage, in: area)
        default: // Copy: the glyphs show the picture itself
            ctx.draw(pictureImage, in: area)
        }
        ctx.restoreGState()
        return stats
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let bg = config.bg
        ctx.setFillColor(red: CGFloat(bg.r) / 255, green: CGFloat(bg.g) / 255, blue: CGFloat(bg.b) / 255, alpha: 1)
        ctx.fill(bounds)
        guard let sim = sim else { return }

        var stats: (lit: Int, drawn: Int)?
        if config.usePicture, let picture = pictureImage {
            stats = drawWithPicture(ctx, sim: sim, picture: picture)
        }
        if stats == nil {
            // UIKit's context has its origin at the top left, Core Text expects the opposite. Flip
            // the whole context once (the text matrix would also move the glyph positions).
            ctx.saveGState()
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.textMatrix = .identity
            stats = drawGlyphs(ctx, sim: sim, height: bounds.height)
            ctx.restoreGState()
        }

        if UserDefaults.standard.bool(forKey: "debugOverlay") {
            let fontName = CTFontCopyPostScriptName(font) as String
            let usable = glyphs.filter { $0 != 0 }.count
            let text = "\(sim.cols)x\(sim.rows) cell \(cellW)x\(cellH) streams \(sim.streamCount) "
                + "lit \(stats?.lit ?? 0) drawn \(stats?.drawn ?? 0) glyphs \(usable)/\(glyphs.count) "
                + "font \(fontName) ticks \(ticks) picture \(pictureImage != nil) blend \(config.pictureBlend)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: UIColor.yellow,
                .backgroundColor: UIColor.black,
            ]
            (text as NSString).draw(in: CGRect(x: 4, y: 40, width: bounds.width - 8, height: 120), withAttributes: attrs)
        }
    }
}
