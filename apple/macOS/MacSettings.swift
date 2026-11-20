import AppKit
import SwiftUI
import ServiceManagement
import BAVtrixCore

/// Settings of the macOS app, saved to UserDefaults. The rain settings are the shared
/// `RainConfig`; the rest only exists on the Mac.
final class MacSettings: ObservableObject {
    static let shared = MacSettings()

    private static let configKey = "bavtrix.mac.config.v1"
    private static let coverKey = "bavtrix.mac.coverIcons"

    @Published var config: RainConfig {
        didSet { save() }
    }

    /// true = the rain covers the desktop icons (like on Windows), false = icons stay on top.
    @Published var coverIcons: Bool {
        didSet { UserDefaults.standard.set(coverIcons, forKey: Self.coverKey) }
    }

    @Published private(set) var launchAtLogin: Bool

    private init() {
        var loaded = RainConfig()
        if let data = UserDefaults.standard.data(forKey: Self.configKey),
           let saved = try? JSONDecoder().decode(RainConfig.self, from: data) {
            loaded = saved
        } else {
            loaded.usePicture = true // the desktop wallpaper shows through the glyphs by default
        }
        config = loaded
        coverIcons = UserDefaults.standard.object(forKey: Self.coverKey) as? Bool ?? false
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func reset() {
        var fresh = RainConfig()
        fresh.usePicture = true
        config = fresh
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("BAVtrix: launch at login failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.configKey)
        }
    }
}

extension RGBA {
    /// Bridge to SwiftUI's ColorPicker.
    var color: Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }

    init(_ color: Color, keepingAlphaOf old: RGBA) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
        func byte(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, v * 255))) }
        self.init(byte(ns.redComponent), byte(ns.greenComponent), byte(ns.blueComponent), old.a)
    }
}
