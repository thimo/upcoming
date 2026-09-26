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
        // macOS 27 brings the Settings window back on the next launch when
        // it was open at quit, and shows it on a launch that opens nothing
        // else. Neither is wanted for a menu bar app. Both modifiers need
        // macOS 15, which is why the deployment target is 15.
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
    }
}
