import AppKit
import CoreText
import BAVtrixCore

/// The desktop wallpaper of a screen, used as the picture that shows through the glyphs.
enum WallpaperLoader {
    static func image(for screen: NSScreen?) -> CGImage? {
        guard let screen = screen ?? NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let image = NSImage(contentsOf: url) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

/// Draws the rain with Core Text and advances the simulation from a timer.
final class RainNSView: NSView {
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
            needsDisplay = true
        }
    }

    /// Where the bundled font is looked up. A screen saver runs inside another host process and
    /// must point this at its own bundle.
    static var resourceBundle: Bundle = .main
    /// Overrides the font lookup completely (used by the command-line snapshot tool).
    static var fontURLOverride: URL?

    /// false when a host (the screen saver) calls `advanceFrame()` itself.
    var drivesItself = true

    private var sim: RainSim?
    private var timer: Timer?
    private var lastTime: CFTimeInterval = 0
    private var font: CTFont = CTFontCreateWithName("Menlo-Bold" as CFString, 9, nil)
    private var specialFont: CTFont = CTFontCreateWithName("Menlo" as CFString, 9, nil)
    private var glyphs: [CGGlyph] = []
    private var specialGlyphs: [CGGlyph] = []
    private var cellW: CGFloat = 6
    private var cellH: CGFloat = 10
    private var ascent: CGFloat = 8
    private var laidOutSize = CGSize.zero

    private var pictureImage: CGImage?
    private var glyphLayer: CGContext?
    private var pictureLayer: CGContext?
    private var layerPixels = (w: 0, h: 0)

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        rebuildFonts()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Fonts, layout and picture

    /// Loads the bundled Matrix Code Font (registered at runtime), falling back to Menlo.
    private static func matrixFont(size: CGFloat) -> CTFont {
        let found = RainNSView.fontURLOverride
            ?? RainNSView.resourceBundle.url(forResource: "MatrixCodeFont", withExtension: "ttf")
        if let url = found {
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
        font = RainNSView.matrixFont(size: size)
        specialFont = CTFontCreateWithName("Menlo" as CFString, size, nil)
        glyphs = RainNSView.glyphs(for: config.charsetChars, in: font)
        specialGlyphs = RainNSView.glyphs(for: config.specialChars, in: specialFont)

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

    /// Reloads the wallpaper (called when the config, the screen or the Space changes).
    func reloadPicture() {
        pictureImage = config.usePicture ? WallpaperLoader.image(for: window?.screen) : nil
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        if bounds.size != laidOutSize { rebuildSim() }
    }

    // MARK: Timer

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        timer = nil
        guard window != nil else { return }
        reloadPicture()
        guard drivesItself else { return }
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.advanceFrame() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        lastTime = 0
    }

    /// Advances the rain by the real time since the previous call and redraws.
    func advanceFrame() {
        let now = CACurrentMediaTime()
        if lastTime == 0 { lastTime = now }
        let dt = min(max((now - lastTime) * 1000, 1), 250)
        lastTime = now
        advance(byMs: Float(dt))
    }

    /// Advances the rain by a fixed time (tests and the snapshot tool use this).
    func advance(byMs ms: Float) {
        sim?.advance(dtMs: ms)
        needsDisplay = true
    }

    // MARK: Drawing

    /// Draws every lit cell into `ctx`, which must use Core Graphics' usual y-up coordinates
    /// for a surface that is `height` points tall.
    private func drawGlyphs(_ ctx: CGContext, sim: RainSim, height: CGFloat, depthOnly: Bool = false) {
        let x0 = (bounds.width - CGFloat(sim.cols) * cellW) / 2
        let y0 = (bounds.height - CGFloat(sim.rows) * cellH) / 2
        for row in 0..<sim.rows {
            for col in 0..<sim.cols {
                let cell = sim.cells[row * sim.cols + col]
                guard var c = Palette.color(cell: cell, row: row, sim: sim) else { continue }
                if depthOnly {
                    // Copy mode: only the depth matters, the glyph shows the picture dimmed by it.
                    let v = UInt8(Palette.depthLevel(cell: cell, row: row, sim: sim) * 255)
                    c = RGBA(v, v, v, c.a)
                }
                let isSpecialGlyph = cell.flags & CellFlag.specialGlyph != 0
                let table = isSpecialGlyph ? specialGlyphs : glyphs
                let index = Int(cell.glyph)
                guard index < table.count, table[index] != 0 else { continue }

                ctx.setFillColor(red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255,
                                 blue: CGFloat(c.b) / 255, alpha: CGFloat(c.a) / 255)
                var glyph = table[index]
                let baselineFromTop = y0 + CGFloat(row) * cellH + ascent
                var position = CGPoint(x: x0 + CGFloat(col) * cellW, y: height - baselineFromTop)
                CTFontDrawGlyphs(isSpecialGlyph ? specialFont : font, &glyph, &position, 1, ctx)
            }
        }
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
    private func drawWithPicture(_ ctx: CGContext, sim: RainSim, picture: CGImage) -> Bool {
        let scale = max(window?.backingScaleFactor ?? 2, 1)
        let pw = Int(bounds.width * scale), ph = Int(bounds.height * scale)
        guard pw > 0, ph > 0 else { return false }
        if layerPixels.w != pw || layerPixels.h != ph || glyphLayer == nil || pictureLayer == nil {
            glyphLayer = makeLayer(width: pw, height: ph)
            pictureLayer = makeLayer(width: pw, height: ph)
            layerPixels = (pw, ph)
        }
        guard let gctx = glyphLayer, let pctx = pictureLayer else { return false }
        let full = CGRect(x: 0, y: 0, width: pw, height: ph)

        // 1. Coloured glyphs.
        gctx.clear(full)
        gctx.saveGState()
        gctx.scaleBy(x: scale, y: scale)
        gctx.textMatrix = .identity
        drawGlyphs(gctx, sim: sim, height: bounds.height, depthOnly: config.pictureBlend == 0)
        gctx.restoreGState()
        guard let glyphImage = gctx.makeImage() else { return false }

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
        guard let composed = pctx.makeImage() else { return false }

        // 3. Compose on the screen (a flipped view's context is y-down, so flip it back).
        let area = CGRect(origin: .zero, size: bounds.size)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        switch config.pictureBlend {
        case 1: // OR: the picture, plus the glyph colour added on top
            ctx.draw(composed, in: area)
            ctx.setBlendMode(.plusLighter)
            ctx.draw(glyphImage, in: area)
        case 2: // AND: the glyph colour multiplied by the picture
            ctx.draw(glyphImage, in: area)
            ctx.setBlendMode(.multiply)
            ctx.draw(composed, in: area)
        default: // Copy: the glyphs show the picture itself
            ctx.draw(composed, in: area)
        }
        ctx.restoreGState()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let bg = config.bg
        ctx.setFillColor(red: CGFloat(bg.r) / 255, green: CGFloat(bg.g) / 255, blue: CGFloat(bg.b) / 255, alpha: 1)
        ctx.fill(bounds)
        guard let sim = sim else { return }

        var done = false
        if config.usePicture, let picture = pictureImage {
            done = drawWithPicture(ctx, sim: sim, picture: picture)
        }
        if !done {
            // The flipped view's context has its origin at the top left, Core Text expects the
            // opposite. Flip the whole context once (the text matrix would move the positions too).
            ctx.saveGState()
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.textMatrix = .identity
            drawGlyphs(ctx, sim: sim, height: bounds.height)
            ctx.restoreGState()
        }
    }
}
