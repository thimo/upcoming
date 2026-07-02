import Foundation

/// Picks "the next joinable meeting" — one selection rule shared by the
/// join hotkey, the status-menu Join item and the agenda row's Join
/// capsule, so they always agree on which call they mean.
public enum NextMeeting {
    /// An upcoming call starting within this window wins over an ongoing
    /// one — the back-to-back case: at 10:58 you want the 11:00 call, not
    /// the 10:00 one you're still in. Fixed at 10 minutes on purpose; a
    /// setting isn't worth it until practice says otherwise.
    public static let joinWindow: TimeInterval = 10 * 60

    /// The event a "join now" action should open. In order: an upcoming
    /// call starting within `joinWindow`; else the ongoing one (rejoining
    /// after a drop, or being late, is the common reason to hit the
    /// hotkey — the most recently started wins when they overlap); else
    /// simply the next call in the future. Only events with a video-call
    /// link qualify; all-day and already-finished events never do.
    public static func nextJoinable(in events: [EventItem], now: Date) -> EventItem? {
        let candidates = events.filter {
            $0.videoCallURL != nil && !$0.isAllDay && $0.end > now
        }
        let upcoming = candidates
            .filter { $0.start > now }
            .min { $0.start < $1.start }
        if let upcoming, upcoming.start.timeIntervalSince(now) <= joinWindow {
            return upcoming
        }
        let ongoing = candidates
            .filter { $0.start <= now }
            .max { $0.start < $1.start }
        return ongoing ?? upcoming
    }

    /// True while the event is ongoing or starts within `joinWindow` —
    /// the period the agenda row swells its video icon into the filled
    /// Join capsule.
    public static func isImminent(_ event: EventItem, now: Date) -> Bool {
        event.end > now && event.start.timeIntervalSince(now) <= joinWindow
    }
}
