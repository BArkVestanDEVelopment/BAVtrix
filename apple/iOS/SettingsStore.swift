import Foundation
import SwiftUI
import BAVtrixCore

/// Settings shared by the views, saved to UserDefaults as JSON.
final class SettingsStore: ObservableObject {
    // Versioned: bumping it makes everybody start from the new defaults.
    private static let key = "bavtrix.config.v2"

    @Published var config: RainConfig {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(RainConfig.self, from: data) {
            config = saved
        } else {
            config = RainConfig()
        }
        #if DEBUG
        // Debug-only launch arguments for the App Store screenshots (not present in Release builds):
        //   -debugReset YES            start from the defaults and drop the stored picture
        //   -debugTheme <Green|Blue|Red|Amber|Violet|White>
        //   -debugBlend <0|1|2>        picture blending: Copy, OR, AND
        //   -debugPictureFile <path>   use this image as the picture and switch the effect on
        let args = UserDefaults.standard
        if args.bool(forKey: "debugReset") {
            PictureStore.delete()
            config = RainConfig()
        }
        if let name = args.string(forKey: "debugTheme"),
           let preset = presets.first(where: { $0.name.lowercased() == name.lowercased() }) {
            config.fg = preset.fg
            config.fade = preset.fade
        }
        if args.object(forKey: "debugBlend") != nil {
            config.pictureBlend = args.integer(forKey: "debugBlend")
        }
        if let path = args.string(forKey: "debugPictureFile"),
           let image = UIImage(contentsOfFile: path), PictureStore.save(image) {
            config.usePicture = true
            config.pictureVersion += 1
        }
        // CI screenshots: `-debugPicture YES` turns the picture effect on with a generated picture.
        if UserDefaults.standard.bool(forKey: "debugPicture") {
            PictureStore.makeDebugPicture()
            config.usePicture = true
            config.pictureVersion += 1
        }
        #endif
    }

    func reset() {
        config = RainConfig()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

extension RGBA {
    /// Bridge to SwiftUI's ColorPicker.
    var color: Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }

    init(_ color: Color, keepingAlphaOf old: RGBA) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(UInt8(max(0, min(255, r * 255))), UInt8(max(0, min(255, g * 255))),
                  UInt8(max(0, min(255, b * 255))), old.a)
    }
}
