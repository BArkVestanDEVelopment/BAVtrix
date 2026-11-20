import AppKit
import ScreenSaver
import SwiftUI
import BAVtrixCore

/// The screen saver: the same rain view as the menu bar app, driven by `animateOneFrame`.
@objc(BAVtrixSaverView)
final class BAVtrixSaverView: ScreenSaverView {
    private var rain: RainNSView?
    private let previewMode: Bool
    private var sheet: NSWindow?

    override init?(frame: NSRect, isPreview: Bool) {
        previewMode = isPreview
        super.init(frame: frame, isPreview: isPreview)
        setUp()
    }

    required init?(coder: NSCoder) {
        previewMode = false
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        animationTimeInterval = 1.0 / 30.0
        let view = RainNSView(frame: bounds)
        view.autoresizingMask = [.width, .height]
        view.drivesItself = false
        view.config = SaverSettings.load(isPreview: previewMode)
        addSubview(view)
        rain = view
    }

    override func startAnimation() {
        super.startAnimation()
        rain?.config = SaverSettings.load(isPreview: previewMode)
        rain?.reloadPicture()
    }

    override func animateOneFrame() {
        rain?.advanceFrame()
    }

    /// Fixed-step advance for the snapshot tool.
    func advance(byMs ms: Float) {
        rain?.advance(byMs: ms)
    }

    // MARK: Options sheet

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        let model = SaverConfigModel()
        let host = NSHostingController(rootView: SaverConfigView(model: model) { [weak self] save in
            if save { SaverSettings.save(model.config) }
            if let window = self?.sheet {
                if let parent = window.sheetParent { parent.endSheet(window) } else { window.close() }
            }
        })
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled]
        sheet = window
        return window
    }
}
