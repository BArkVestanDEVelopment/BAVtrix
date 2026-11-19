import Foundation

public struct RGBA: Codable, Equatable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

/// All user settings. Names and meaning follow the Windows `default.cfg`.
public struct RainConfig: Codable, Equatable {
    public var maxStream = 2000
    public var speedVariance: Float = 8
    public var monotonousCleanup = false
    public var backTrace = 40
    public var randomizedCleanup = false
    public var leading = 10
    public var spacePad = 30
    /// Milliseconds a base-speed stream needs to move one row down.
    public var refreshMs: Float = 100
    public var specialProbability: Float = 0.1
    /// Share of time a column carries a stream (rain density), 0...1.
    public var spawnRate: Float = 0.8
    /// Shimmer strength of trail characters, 0...1.
    public var flicker: Float = 0.3
    /// Chance per frame that a head symbol changes, 0...1.
    public var headFlicker: Float = 1
    /// Brightness of heads and flashes, 0.5...2.
    public var headBrightness: Float = 1.3
    public var trailMin = 16
    /// 0 = automatic (grows with density).
    public var trailMax = 0
    public var charset = "1234567890ABCDEFGHIJKLMNOPQRSUTVWXYZabcd"
    public var specialStrings = ["The matrix has you"]
    public var fg = RGBA(187, 255, 187)
    public var fade = RGBA(0, 128, 0)
    public var bg = RGBA(0, 0, 0)
    public var specialFg = RGBA(251, 255, 251)
    public var specialFade = RGBA(208, 244, 208, 128)
    /// The chosen picture shows through the glyphs (the desktop version's wallpaper effect).
    public var usePicture = false
    /// Bumped whenever the picture file is replaced, so renderers reload it.
    public var pictureVersion = 0
    /// true = fill the whole screen (crop the picture), false = fit the whole picture.
    public var pictureCover = false
    /// How the picture is mixed with the glyph colour: 0 = Copy, 1 = OR (add), 2 = AND (multiply).
    public var pictureBlend = 0
    /// Glyph size in points (small glyphs = many columns, like on the desktop).
    public var glyphSize: Float = 9

    public init() {}

    /// Characters of the main character set.
    public var charsetChars: [Character] { Array(charset) }

    /// Unique characters used by the special strings, in order of first use.
    public var specialChars: [Character] {
        var out: [Character] = []
        for s in specialStrings {
            for c in s where !out.contains(c) { out.append(c) }
        }
        return out
    }

    /// Special strings as indices into `specialChars`.
    public var specialIndexStrings: [[UInt16]] {
        let chars = specialChars
        return specialStrings.map { s in
            s.compactMap { c in chars.firstIndex(of: c).map { UInt16($0) } }
        }.filter { !$0.isEmpty }
    }
}
