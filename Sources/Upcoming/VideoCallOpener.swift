import AppKit
import UpcomingCore

/// Opens a video-call link the right way: Teams join links go straight
/// to the Teams app when something handles the msteams: scheme;
/// everything else (and Teams-less Macs) opens in the default browser.
/// Shared by the agenda row video button and the notification join action.
@MainActor
enum VideoCallOpener {
    static func open(_ url: URL) {
        if let appURL = VideoCallDetector.teamsAppURL(for: url),
           NSWorkspace.shared.urlForApplication(toOpen: appURL) != nil {
            NSWorkspace.shared.open(appURL)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
