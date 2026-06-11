import SwiftUI

/// SwiftUI App lifecycle (Uncommitted's setup): the only scene is the
/// native Settings window, which brings the toolbar-style tab bar for
/// free. The menu bar presence itself stays pure AppKit in AppDelegate.
@main
struct UpcomingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.calendarService)
                .environmentObject(appDelegate.config)
        }
        .windowResizability(.contentSize)
    }
}
