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

    // MARK: Fonts and layout

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
        cellW = max(ceil(widest), 4)
        ascent = CTFontGetAscent(font)
        cellH = max(ceil(ascent + CTFontGetDescent(font)), 6)
    }

    private func rebuildSim() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let cols = Int(bounds.width / cellW)
        let rows = Int(bounds.height / cellH)
        sim = RainSim(cols: cols, rows: rows, config: config, seed: UInt64(Date().timeIntervalSince1970 * 1000))
        laidOutSize = bounds.size
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

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let bg = config.bg
        ctx.setFillColor(red: CGFloat(bg.r) / 255, green: CGFloat(bg.g) / 255, blue: CGFloat(bg.b) / 255, alpha: 1)
        ctx.fill(bounds)
        guard let sim = sim else { return }

        // UIKit's context has its origin at the top left, Core Text expects the opposite. Flip the
        // whole context once (the text matrix would also move the glyph positions off screen).
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        let x0 = (bounds.width - CGFloat(sim.cols) * cellW) / 2
        let y0 = (bounds.height - CGFloat(sim.rows) * cellH) / 2
        var lit = 0
        var drawn = 0

        for row in 0..<sim.rows {
            for col in 0..<sim.cols {
                let cell = sim.cells[row * sim.cols + col]
                guard let c = Palette.color(cell: cell, row: row, sim: sim) else { continue }
                lit += 1
                let isSpecialGlyph = cell.flags & CellFlag.specialGlyph != 0
                let table = isSpecialGlyph ? specialGlyphs : glyphs
                let index = Int(cell.glyph)
                guard index < table.count, table[index] != 0 else { continue }

                ctx.setFillColor(red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255,
                                 blue: CGFloat(c.b) / 255, alpha: CGFloat(c.a) / 255)
                var glyph = table[index]
                // Baseline in the flipped (y up) coordinates.
                let baselineFromTop = y0 + CGFloat(row) * cellH + ascent
                var position = CGPoint(x: x0 + CGFloat(col) * cellW, y: bounds.height - baselineFromTop)
                CTFontDrawGlyphs(isSpecialGlyph ? specialFont : font, &glyph, &position, 1, ctx)
                drawn += 1
            }
        }

        ctx.restoreGState()

        if UserDefaults.standard.bool(forKey: "debugOverlay") {
            let fontName = CTFontCopyPostScriptName(font) as String
            let fileFound = Bundle.main.url(forResource: "MatrixCodeFont", withExtension: "ttf") != nil
            let usable = glyphs.filter { $0 != 0 }.count
            let text = "\(sim.cols)x\(sim.rows) cell \(cellW)x\(cellH) streams \(sim.streamCount) "
                + "lit \(lit) drawn \(drawn) glyphs \(usable)/\(glyphs.count) "
                + "font \(fontName) file \(fileFound) ticks \(ticks) bounds \(Int(bounds.width))x\(Int(bounds.height))"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: UIColor.yellow,
                .backgroundColor: UIColor.black,
            ]
            (text as NSString).draw(in: CGRect(x: 4, y: 40, width: bounds.width - 8, height: 120), withAttributes: attrs)
        }
    }
}
