import Foundation
import ScreenSaver
import BAVtrixCore

/// The screen saver keeps its own settings: it runs in a separate host process, so it cannot read
/// the menu bar app's preferences. They live in the saver's `ScreenSaverDefaults` module.
enum SaverSettings {
    private static let module = "dev.barkvestan.bavtrix.saver"
    private static let key = "config.v1"

    private static var defaults: UserDefaults {
        ScreenSaverDefaults(forModuleWithName: module) ?? UserDefaults.standard
    }

    static func load(isPreview: Bool) -> RainConfig {
        var config = RainConfig()
        config.usePicture = true // the wallpaper shows through the glyphs by default
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode(RainConfig.self, from: data) {
            config = saved
        }
        // The preview thumbnail in System Settings is tiny: small glyphs keep it readable.
        if isPreview { config.glyphSize = min(config.glyphSize, 4) }
        return config
    }

    static func save(_ config: RainConfig) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: key)
            defaults.synchronize()
        }
    }
}
