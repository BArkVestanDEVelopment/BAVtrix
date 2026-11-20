import AppKit
import ScreenSaver
import BAVtrixCore

// Command-line check of the screen saver view: renders frames into PNG files without a screen.
//   saver-snapshot <output-folder> <path to MatrixCodeFont.ttf>

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: saver-snapshot <output-folder> <font.ttf>\n".utf8))
    exit(2)
}
let outputFolder = URL(fileURLWithPath: arguments[1])
RainNSView.fontURLOverride = URL(fileURLWithPath: arguments[2])
try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

_ = NSApplication.shared

func snapshot(named name: String, usePicture: Bool) {
    var config = RainConfig()
    config.usePicture = usePicture
    config.glyphSize = 12
    config.spawnRate = 0.7
    SaverSettings.save(config)

    guard let saver = BAVtrixSaverView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720), isPreview: false) else {
        FileHandle.standardError.write(Data("could not create the saver view\n".utf8))
        exit(1)
    }
    saver.layoutSubtreeIfNeeded()
    for _ in 0..<500 { saver.advance(byMs: 33) }
    saver.startAnimation()
    for _ in 0..<60 { saver.advance(byMs: 33) }

    guard let rep = saver.bitmapImageRepForCachingDisplay(in: saver.bounds) else {
        FileHandle.standardError.write(Data("no bitmap for the saver view\n".utf8))
        exit(1)
    }
    saver.cacheDisplay(in: saver.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    let url = outputFolder.appendingPathComponent(name)
    do {
        try png.write(to: url)
        print("wrote \(url.path) (\(png.count) bytes)")
    } catch {
        FileHandle.standardError.write(Data("could not write \(url.path): \(error)\n".utf8))
        exit(1)
    }
}

snapshot(named: "saver-plain.png", usePicture: false)
snapshot(named: "saver-picture.png", usePicture: true)
