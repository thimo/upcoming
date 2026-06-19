import Foundation

/// AppKit-free colour so models stay framework-light and serializable.
public struct CalendarColor: Equatable, Hashable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Hue (0–1), saturation and brightness — the pill styling derives
    /// its fill/text colours by transforming these.
    public var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let mx = max(red, green, blue)
        let mn = min(red, green, blue)
        let delta = mx - mn
        guard mx > 0, delta > 0 else { return (0, 0, mx) }

        var hue: Double
        if mx == red {
            hue = (green - blue) / delta
        } else if mx == green {
            hue = 2 + (blue - red) / delta
        } else {
            hue = 4 + (red - green) / delta
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, delta / mx, mx)
    }
}

/// One calendar as shown in Settings (per-calendar on/off toggle).
public struct CalendarInfo: Identifiable, Equatable {
    public let id: String
    public let title: String
    /// Account/source name ("iCloud", "Exchange", …) for grouping in Settings.
    public let sourceTitle: String
    public let color: CalendarColor

    public init(id: String, title: String, sourceTitle: String, color: CalendarColor) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
        self.color = color
    }
}

/// One invitee on an event, for the Apple-Calendar-style detail popover.
/// Status mirrors EKParticipantStatus, collapsed to the cases the popover
/// renders (a glyph per attendee).
public struct EventAttendee: Identifiable, Equatable {
    public enum Status: Equatable {
        case accepted
        case declined
        case tentative
        /// Invited, no response yet (EventKit's pending/unknown).
        case noResponse
    }

    /// Display name, or the bare email when no name is available.
    public let name: String
    public let status: Status
    public let isOrganizer: Bool
    public let isOptional: Bool

    public var id: String { name }

    public init(name: String, status: Status, isOrganizer: Bool = false, isOptional: Bool = false) {
        self.name = name
        self.status = status
        self.isOrganizer = isOrganizer
        self.isOptional = isOptional
    }
}

/// A single event occurrence, mapped from EKEvent so views and tests
/// never touch EventKit types.
public struct EventItem: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let calendarID: String
    public let color: CalendarColor
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    /// From the system Birthdays calendar; rendered as a gift-icon row
    /// instead of an all-day pill (Fantastical's treatment).
    public let isBirthday: Bool
    /// Has a recurrence rule; rendered with Apple Calendar's ⟳ marker.
    public let isRecurring: Bool
    /// Invitation the user hasn't responded to yet; rendered like Apple
    /// Calendar's pending style (grey hatch).
    public let isPendingInvitation: Bool
    /// Invitation answered with Maybe; Apple Calendar hatches these in
    /// the calendar tint instead of grey.
    public let isTentative: Bool
    /// Raw EKEvent identifier (shared across occurrences of a recurring
    /// event, unlike `id`); needed for the ical://ekevent/ deep link
    /// that opens the event in Calendar.app.
    public let eventIdentifier: String
    public let location: String?
    public let videoCallURL: URL?
    /// Free-text notes / description (the EKEvent.notes body).
    public let notes: String?
    /// The event's own URL field (distinct from the derived videoCallURL);
    /// shown in the popover's notes/URL card.
    public let url: URL?
    /// Invitees, for the popover's attendee list.
    public let attendees: [EventAttendee]
    /// Pre-formatted alert line ("Alert 15 minutes before start"), if the
    /// event carries an alarm. nil = no alarm row.
    public let alertText: String?
    /// Pre-formatted recurrence line ("Repeats every week on Monday and
    /// Thursday"), if recurring. nil = not recurring / unparseable.
    public let recurrenceText: String?
    /// Structured-location coordinate, when EventKit provides one; lets the
    /// popover map skip geocoding. nil → the view geocodes `location`.
    public let latitude: Double?
    public let longitude: Double?

    public init(
        id: String,
        title: String,
        calendarID: String,
        color: CalendarColor,
        start: Date,
        end: Date,
        isAllDay: Bool,
        isBirthday: Bool = false,
        isRecurring: Bool = false,
        isPendingInvitation: Bool = false,
        isTentative: Bool = false,
        eventIdentifier: String = "",
        location: String? = nil,
        videoCallURL: URL? = nil,
        notes: String? = nil,
        url: URL? = nil,
        attendees: [EventAttendee] = [],
        alertText: String? = nil,
        recurrenceText: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.calendarID = calendarID
        self.color = color
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isBirthday = isBirthday
        self.isRecurring = isRecurring
        self.isPendingInvitation = isPendingInvitation
        self.isTentative = isTentative
        self.eventIdentifier = eventIdentifier
        self.location = location
        self.videoCallURL = videoCallURL
        self.notes = notes
        self.url = url
        self.attendees = attendees
        self.alertText = alertText
        self.recurrenceText = recurrenceText
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// One day in the agenda list: all-day pills first, then timed events.
public struct DaySection: Identifiable, Equatable {
    public var id: Date { day }
    public let day: Date
    public let allDay: [EventItem]
    public let timed: [EventItem]

    public init(day: Date, allDay: [EventItem], timed: [EventItem]) {
        self.day = day
        self.allDay = allDay
        self.timed = timed
    }
}
