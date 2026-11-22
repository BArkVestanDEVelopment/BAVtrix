import AppKit
import SwiftUI
import Combine
import BAVtrixCore

/// A borderless window that sits on the desktop, below all normal windows.
final class DesktopRainWindow: NSWindow {
    let rain: RainNSView

    init(screen: NSScreen, coverIcons: Bool, config: RainConfig) {
        rain = RainNSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        rain.config = config
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        // Above the wallpaper but below the icons, or above the icons (they are then hidden).
        let key: CGWindowLevelKey = coverIcons ? .desktopIconWindow : .desktopWindow
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(key)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        contentView = rain
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = MacSettings.shared
    private var windows: [DesktopRainWindow] = []
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var coverItem: NSMenuItem?
    private var loginItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        rebuildWindows()
        buildStatusItem()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(wallpaperMayHaveChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        settings.$config
            .receive(on: RunLoop.main)
            .sink { [weak self] cfg in self?.windows.forEach { $0.rain.config = cfg } }
            .store(in: &cancellables)
        settings.$coverIcons
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildWindows() }
            .store(in: &cancellables)

        // CI: launch with `-showSettings` to open the settings window straight away.
        if CommandLine.arguments.contains("-showSettings") { openSettings() }
    }

    // MARK: Windows

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map {
            DesktopRainWindow(screen: $0, coverIcons: settings.coverIcons, config: settings.config)
        }
        windows.forEach { $0.orderBack(nil) }
    }

    @objc private func screensChanged() {
        rebuildWindows()
    }

    @objc private func wallpaperMayHaveChanged() {
        windows.forEach { $0.rain.reloadPicture() }
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "B"
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        let cover = menu.addItem(withTitle: "Hide desktop icons", action: #selector(toggleCover), keyEquivalent: "")
        cover.target = self
        let login = menu.addItem(withTitle: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
        coverItem = cover
        loginItem = login
    }

    func menuWillOpen(_ menu: NSMenu) {
        coverItem?.state = settings.coverIcons ? .on : .off
        loginItem?.state = settings.launchAtLogin ? .on : .off
    }

    @objc private func toggleCover() {
        settings.coverIcons.toggle()
    }

    @objc private func toggleLogin() {
        settings.setLaunchAtLogin(!settings.launchAtLogin)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: MacSettingsView(store: settings))
            let window = NSWindow(contentViewController: host)
            window.title = "BAVtrix Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
