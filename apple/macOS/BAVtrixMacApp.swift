import SwiftUI

/// The app has no main window: the rain lives in desktop-level windows created by the delegate,
/// and the menu bar item opens the settings.
@main
struct BAVtrixMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
