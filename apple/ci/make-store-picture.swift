// Generates a neutral abstract gradient picture (1600 x 2400 PNG) for the App Store screenshots.
// Our own artwork, no photos and no third-party material.
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

// Deep vertical base: night blue, teal, violet.
let base = CGGradient(
    colorsSpace: space,
    colors: [color(0.02, 0.03, 0.14), color(0.04, 0.26, 0.36), color(0.34, 0.10, 0.46)] as CFArray,
    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: CGFloat(height)), end: .zero, options: [])

// Soft glowing blobs.
let blobs: [(x: CGFloat, y: CGFloat, r: CGFloat, c: (CGFloat, CGFloat, CGFloat))] = [
    (380, 1950, 900, (0.00, 0.90, 0.80)),
    (1280, 1520, 820, (1.00, 0.35, 0.60)),
    (520, 940, 880, (1.00, 0.75, 0.20)),
    (1180, 460, 920, (0.30, 0.50, 1.00)),
    (800, 1230, 520, (0.90, 1.00, 0.92)),
]
for blob in blobs {
    let glow = CGGradient(
        colorsSpace: space,
        colors: [color(blob.c.0, blob.c.1, blob.c.2, 0.95), color(blob.c.0, blob.c.1, blob.c.2, 0)] as CFArray,
        locations: [0, 1])!
    let centre = CGPoint(x: blob.x, y: blob.y)
    ctx.drawRadialGradient(glow, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: blob.r, options: [])
}

// A few faint diagonal bands give the picture some structure.
ctx.saveGState()
ctx.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
ctx.rotate(by: -0.45)
for i in -4...4 {
    let y = CGFloat(i) * 330
    ctx.setFillColor(color(1, 1, 1, i % 2 == 0 ? 0.10 : 0.05))
    ctx.fill(CGRect(x: -2400, y: y, width: 4800, height: 120))
}
ctx.restoreGState()

guard let image = ctx.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
print("wrote \(CommandLine.arguments[1]) (\(width)x\(height))")
