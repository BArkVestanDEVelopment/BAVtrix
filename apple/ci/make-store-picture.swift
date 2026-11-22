// Generates the picture for the App Store screenshots (1600 x 2400 PNG): a large glowing moon over
// three layered mountain ridges, bright shapes on pure black. Black stays free of rain, so the
// shapes must be bright and high-contrast to read through the glyphs. Our own artwork: no photos,
// no text, no third-party material.
//   swift apple/ci/make-store-picture.swift out.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let width = 1600
let height = 2400
let space = CGColorSpaceCreateDeviceRGB()

guard CommandLine.arguments.count >= 2,
      let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else {
    FileHandle.standardError.write(Data("usage: make-store-picture <out.png>\n".utf8))
    exit(2)
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

/// y measured from the top of the picture (Core Graphics itself counts from the bottom).
func flipped(_ y: CGFloat) -> CGFloat { CGFloat(height) - y }

// Pure black background.
ctx.setFillColor(color(0, 0, 0))
ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

// The moon: a soft halo, then a bright disc with a warm rim.
let moon = CGPoint(x: 800, y: flipped(860))
let halo = CGGradient(
    colorsSpace: space,
    colors: [color(1.0, 0.95, 0.75, 0.55), color(1.0, 0.85, 0.45, 0.22), color(1.0, 0.7, 0.3, 0)] as CFArray,
    locations: [0, 0.45, 1])!
ctx.drawRadialGradient(halo, startCenter: moon, startRadius: 380, endCenter: moon, endRadius: 820, options: [])
let disc = CGGradient(
    colorsSpace: space,
    colors: [color(1.0, 1.0, 0.96), color(1.0, 0.97, 0.82), color(1.0, 0.82, 0.45)] as CFArray,
    locations: [0, 0.7, 1])!
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: moon.x - 470, y: moon.y - 470, width: 940, height: 940))
ctx.clip()
ctx.drawRadialGradient(disc, startCenter: moon, startRadius: 0, endCenter: moon, endRadius: 470, options: [])
ctx.restoreGState()

/// One mountain layer: the ridge line (x, y from the top), filled from a bright top to a dark base.
func ridge(_ points: [(CGFloat, CGFloat)], top: CGColor, bottom: CGColor, from: CGFloat, to: CGFloat) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: 0))
    for p in points { path.addLine(to: CGPoint(x: p.0, y: flipped(p.1))) }
    path.addLine(to: CGPoint(x: CGFloat(width), y: 0))
    path.closeSubpath()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let fill = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(fill, start: CGPoint(x: 0, y: flipped(from)), end: CGPoint(x: 0, y: flipped(to)), options: [])
    ctx.restoreGState()
    // A black outline separates the layers.
    ctx.addPath(path)
    ctx.setStrokeColor(color(0, 0, 0))
    ctx.setLineWidth(14)
    ctx.strokePath()
}

ridge([(0, 1560), (240, 1400), (520, 1620), (800, 1330), (1100, 1600), (1350, 1450), (1600, 1640)],
      top: color(0.82, 0.55, 1.0), bottom: color(0.30, 0.10, 0.55), from: 1330, to: 2400)
ridge([(0, 1880), (300, 1720), (620, 1940), (960, 1690), (1260, 1920), (1600, 1760)],
      top: color(1.0, 0.55, 0.45), bottom: color(0.55, 0.15, 0.30), from: 1690, to: 2400)
ridge([(0, 2160), (360, 2000), (720, 2220), (1060, 1980), (1400, 2200), (1600, 2090)],
      top: color(0.25, 1.0, 0.85), bottom: color(0.05, 0.35, 0.35), from: 1980, to: 2400)

guard let image = ctx.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
print("wrote \(CommandLine.arguments[1]) (\(width)x\(height))")
