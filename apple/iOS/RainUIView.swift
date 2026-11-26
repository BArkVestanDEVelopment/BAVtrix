import UIKit
import CoreText
import BAVtrixCore

/// Draws the rain (own stroke-drawn glyphs, see GlyphAtlas) and advances the simulation from a display link.
final class RainUIView: UIView {
    var config = RainConfig() {
        didSet {
            if config == oldValue { return }
            let layoutChanged = oldValue.glyphSize != config.glyphSize
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
    private var atlas: GlyphAtlas?
    private var specialFont: CTFont = CTFontCreateWithName("Menlo" as CFString, 14, nil)
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
    // The picture already scaled and placed at screen resolution, so that no frame has to resample it.
    private var scaledPicture: CGImage?
    private var scaledPictureKey = ""
    /// How many times the scaled picture was rebuilt (debug overlay: must stay put while running).
    private var pictureBuilds = 0
    /// Smoothed duration of `draw(_:)` in milliseconds (shown by the debug overlay).
    private var drawMs: Double = 0

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

    private static func glyphs(for chars: [Character], in font: CTFont) -> [CGGlyph] {
        chars.map { ch in
            var utf16 = Array(String(ch).utf16)
            var out = [CGGlyph](repeating: 0, count: utf16.count)
            let ok = CTFontGetGlyphsForCharacters(font, &utf16, &out, utf16.count)
            return ok ? out[0] : 0
        }
    }

    /// The cell size comes from the glyph size alone; the masks are redrawn for the screen scale.
    private func rebuildFonts() {
        let size = CGFloat(config.glyphSize)
        let scale = max(window?.screen.scale ?? contentScaleFactor, 1)
        let cell = GlyphAtlas.cellSize(glyphSize: size)
        cellW = cell.width
        cellH = cell.height
        atlas = GlyphAtlas(glyphSize: size, scale: scale)
        // The few special glyphs (the greeting text) use the system monospaced font.
        specialFont = CTFontCreateWithName("Menlo" as CFString, size, nil)
        specialGlyphs = RainUIView.glyphs(for: config.specialChars, in: specialFont)
        ascent = CTFontGetAscent(specialFont)
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
        scaledPicture = nil
        scaledPictureKey = ""
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
            rebuildFonts()
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
        // The masks have exactly the screen's pixel size: put the grid on whole pixels and stamp
        // them without resampling (cells are whole points, so every cell stays aligned).
        let pixel = max(atlas?.scale ?? 1, 1)
        let x0 = ((bounds.width - CGFloat(sim.cols) * cellW) / 2 * pixel).rounded(.down) / pixel
        let y0 = ((bounds.height - CGFloat(sim.rows) * cellH) / 2 * pixel).rounded(.down) / pixel
        ctx.interpolationQuality = .none
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
                let index = Int(cell.glyph)
                ctx.setFillColor(red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255,
                                 blue: CGFloat(c.b) / 255, alpha: CGFloat(c.a) / 255)
                if isSpecialGlyph {
                    guard index < specialGlyphs.count, specialGlyphs[index] != 0 else { continue }
                    var glyph = specialGlyphs[index]
                    // Baseline in y-up coordinates.
                    let baselineFromTop = y0 + CGFloat(row) * cellH + ascent
                    var position = CGPoint(x: x0 + CGFloat(col) * cellW, y: height - baselineFromTop)
                    CTFontDrawGlyphs(specialFont, &glyph, &position, 1, ctx)
                } else {
                    guard let mask = atlas?.mask(index) else { continue }
                    // y-up: the cell's bottom edge.
                    let bottom = height - (y0 + CGFloat(row + 1) * cellH)
                    ctx.draw(mask, in: CGRect(x: x0 + CGFloat(col) * cellW, y: bottom, width: cellW, height: cellH))
                }
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

    private var hasBlackBackground: Bool {
        config.bg.r == 0 && config.bg.g == 0 && config.bg.b == 0
    }

    /// The picture rendered once at screen resolution. Over a black background it is made opaque
    /// (black outside the picture), otherwise it stays transparent there.
    private func screenPicture(_ picture: CGImage, width: Int, height: Int, scale: CGFloat) -> CGImage? {
        let key = "\(width)x\(height) \(config.pictureCover) \(config.pictureVersion) \(hasBlackBackground)"
        if key == scaledPictureKey, let cached = scaledPicture { return cached }
        guard let layer = makeLayer(width: width, height: height) else { return nil }
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        layer.clear(full)
        if hasBlackBackground {
            layer.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            layer.fill(full)
        }
        layer.interpolationQuality = .high
        layer.scaleBy(x: scale, y: scale)
        layer.draw(picture, in: pictureRect(for: picture))
        scaledPicture = layer.makeImage()
        scaledPictureKey = key
        pictureBuilds += 1
        return scaledPicture
    }

    /// Picture effect, Copy and AND over a black background: the glyphs are drawn straight onto
    /// the screen and the ready picture is multiplied over them in one pass (no offscreen layers).
    private func drawWithPictureDirect(_ ctx: CGContext, sim: RainSim, picture: CGImage) -> (lit: Int, drawn: Int)? {
        let scale = max(contentScaleFactor, 1)
        let pw = Int(bounds.width * scale), ph = Int(bounds.height * scale)
        guard pw > 0, ph > 0, let ready = screenPicture(picture, width: pw, height: ph, scale: scale) else { return nil }
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        let stats = drawGlyphs(ctx, sim: sim, height: bounds.height, depthOnly: config.pictureBlend == 0)
        ctx.setBlendMode(.multiply)
        ctx.draw(ready, in: CGRect(origin: .zero, size: bounds.size))
        ctx.restoreGState()
        return stats
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
        guard let gctx = glyphLayer, let pctx = pictureLayer,
              let ready = screenPicture(picture, width: pw, height: ph, scale: scale) else { return nil }
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
        pctx.interpolationQuality = .none
        pctx.draw(ready, in: full)
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
        let started = CACurrentMediaTime()
        let bg = config.bg
        ctx.setFillColor(red: CGFloat(bg.r) / 255, green: CGFloat(bg.g) / 255, blue: CGFloat(bg.b) / 255, alpha: 1)
        ctx.fill(bounds)
        guard let sim = sim else { return }

        var stats: (lit: Int, drawn: Int)?
        if config.usePicture, let picture = pictureImage {
            if hasBlackBackground && config.pictureBlend != 1 {
                stats = drawWithPictureDirect(ctx, sim: sim, picture: picture)
            } else {
                stats = drawWithPicture(ctx, sim: sim, picture: picture)
            }
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

        let elapsed = (CACurrentMediaTime() - started) * 1000
        drawMs = drawMs == 0 ? elapsed : drawMs * 0.9 + elapsed * 0.1

        if UserDefaults.standard.bool(forKey: "debugOverlay") {
            let usable = atlas?.count ?? 0
            let timing = String(format: "draw %.1f ms", drawMs)
            let text = "\(sim.cols)x\(sim.rows) cell \(cellW)x\(cellH) streams \(sim.streamCount) "
                + "lit \(stats?.lit ?? 0) drawn \(stats?.drawn ?? 0) glyphs \(usable) "
                + "ticks \(ticks) picture \(pictureImage != nil) blend \(config.pictureBlend) \(timing) builds \(pictureBuilds)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: UIColor.yellow,
                .backgroundColor: UIColor.black,
            ]
            (text as NSString).draw(in: CGRect(x: 4, y: 40, width: bounds.width - 8, height: 120), withAttributes: attrs)
        }
    }
}
