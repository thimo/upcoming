import AppKit
import UpcomingCore

/// Opens an event in Calendar.app via its ical://ekevent/ deep link —
/// the spec's MVP for clicking an event (a native detail popover may
/// come later).
///
/// Format verified empirically on this Mac (2026-06-11): identifier-only
/// with the identifier FULLY percent-encoded (RFC 3986 unreserved set).
/// Both matter: subscription-calendar identifiers embed a full URL
/// (`<uuid>:http://…/#fragment`) that wrecks the link unless everything
/// is encoded, and the MeetingBar-style occurrence-timestamp prefix
/// (`ical://ekevent/<yyyyMMdd'T'HHmmss'Z'>/<id>?…`) is a dead end:
/// with a true-UTC timestamp Calendar opens without navigating, with a
/// local-time timestamp it navigates to a wrong month entirely. Known
/// cost: occurrences of recurring events can't be targeted — Calendar
/// picks which occurrence to show.
@MainActor
enum CalendarAppOpener {
    /// RFC 3986 unreserved characters; everything else gets encoded,
    /// including `:`, `/` and `#`.
    private static let identifierAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func show(_ event: EventItem) {
        showEvent(identifier: event.eventIdentifier)
    }

    /// Navigates Calendar.app to `day`, keeping the user's current view
    /// mode (week/month/…) — `view calendar at` just scrolls. The `ical://`
    /// scheme has no reliable date-only form (see `showEvent`'s notes), so
    /// this drives Calendar over AppleScript instead. Building the target
    /// date from components — rather than a locale-formatted string — keeps
    /// it robust across regions; setting `day` to 1 before the month avoids
    /// an overflow when the current day-of-month exceeds the target month's
    /// length. Requires the apple-events automation entitlement plus a
    /// one-time TCC "control Calendar" grant; silently no-ops if denied.
    static func showDay(_ day: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        guard let year = c.year, let month = c.month, let dom = c.day else { return }
        let source = """
        set d to current date
        set day of d to 1
        set year of d to \(year)
        set month of d to \(month)
        set day of d to \(dom)
        set time of d to 0
        tell application "Calendar"
            view calendar at d
            activate
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
    }

    /// Opens an event by its raw EventKit identifier — used both for
    /// existing events (`show`) and for a freshly created one (the agenda's
    /// per-day "+", which finishes editing in Calendar).
    static func showEvent(identifier rawIdentifier: String) {
        guard !rawIdentifier.isEmpty,
              let identifier = rawIdentifier.addingPercentEncoding(
                withAllowedCharacters: identifierAllowed
              ),
              let url = URL(
                string: "ical://ekevent/\(identifier)?method=show&options=more"
              )
        else { return }
        NSWorkspace.shared.open(url)
    }
}
