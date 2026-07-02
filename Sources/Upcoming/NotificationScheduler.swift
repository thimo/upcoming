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

    /// One-shot notice when the join hotkey finds nothing ongoing or
    /// imminent — silence would read as a dead hotkey. When a later call
    /// exists (`next`), the notice says when it is and carries the usual
    /// Join action, so deliberately going in early stays one tap away.
    func notifyNothingToJoin(next: EventItem?) {
        let content = UNMutableNotificationContent()
        if let next, let url = next.videoCallURL {
            content.title = "No meeting to join right now"
            content.body = "Next: \(next.title), \(Self.startPhrase(next.start))"
            content.categoryIdentifier = Self.meetingCategoryID
            content.userInfo = [Self.urlInfoKey: url.absoluteString]
        } else {
            content.title = "No upcoming video calls"
            content.body = "None of your upcoming events has a video-call link."
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "nothing-to-join",
            content: content,
            trigger: nil
        ))
    }

    /// "at 11:00" (today), "tomorrow at 11:00", else "Friday at 11:00" —
    /// the join fetch spans 7 days, so a weekday never ambiguates.
    private static func startPhrase(_ start: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let time = formatter.string(from: start)
        let cal = Calendar.current
        if cal.isDateInToday(start) { return "at \(time)" }
        if cal.isDateInTomorrow(start) { return "tomorrow at \(time)" }
        let weekday = DateFormatter()
        weekday.dateFormat = "EEEE"
        return "\(weekday.string(from: start)) at \(time)"
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
