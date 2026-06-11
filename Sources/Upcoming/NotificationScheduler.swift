import Foundation
import UserNotifications
import UpcomingCore

/// Local notifications X minutes before events that have a video-call
/// link (spec: only those — meetings you must dial into, nothing else).
/// The notification carries a Join action and opens the call on tap.
///
/// Scheduling is wholesale: every reschedule clears all pending requests
/// and re-adds the upcoming ones. Triggered from AppDelegate on EventKit
/// changes and settings changes, so the pending set tracks reality.
@MainActor
final class NotificationScheduler: NSObject {
    private nonisolated static let joinActionID = "join"
    private nonisolated static let meetingCategoryID = "meeting"
    private nonisolated static let urlInfoKey = "videoCallURL"
    /// macOS caps pending local notifications at 64 per app; with a 48h
    /// scheduling horizon this limit is theoretical, but stay under it.
    private static let maxPending = 60

    func setUp() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let join = UNNotificationAction(
            identifier: Self.joinActionID,
            title: "Join",
            options: [.foreground]
        )
        let meeting = UNNotificationCategory(
            identifier: Self.meetingCategoryID,
            actions: [join],
            intentIdentifiers: []
        )
        center.setNotificationCategories([meeting])
    }

    /// Replaces all pending notifications with ones for `events` (the
    /// caller passes the next ~48h) firing `leadMinutes` before start.
    func schedule(events: [EventItem], leadMinutes: Int) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        // 0 = notifications off; the pending set is already cleared.
        guard leadMinutes > 0 else { return }

        let lead = TimeInterval(leadMinutes * 60)
        let now = Date()
        let upcoming = events
            .filter { $0.videoCallURL != nil && !$0.isAllDay }
            .filter { $0.start.addingTimeInterval(-lead) > now }
            .sorted { $0.start < $1.start }
            .prefix(Self.maxPending)

        for event in upcoming {
            guard let url = event.videoCallURL else { continue }
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = leadMinutes == 1
                ? "Starts in 1 minute"
                : "Starts in \(leadMinutes) minutes"
            content.sound = .default
            content.categoryIdentifier = Self.meetingCategoryID
            content.userInfo = [Self.urlInfoKey: url.absoluteString]

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, event.start.addingTimeInterval(-lead).timeIntervalSinceNow),
                repeats: false
            )
            center.add(UNNotificationRequest(
                identifier: event.id,
                content: content,
                trigger: trigger
            ))
        }
    }
}

extension NotificationScheduler: UNUserNotificationCenterDelegate {
    /// Show the banner even while the popup has focus.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Both the Join button and a plain tap on the banner open the call.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let urlString = info[Self.urlInfoKey] as? String,
           let url = URL(string: urlString) {
            Task { @MainActor in
                VideoCallOpener.open(url)
            }
        }
        completionHandler()
    }
}
