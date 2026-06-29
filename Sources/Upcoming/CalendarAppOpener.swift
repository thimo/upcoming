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
