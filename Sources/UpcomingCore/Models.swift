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
    /// Calendar's pending style (striped pill / hollow dot).
    public let isPendingInvitation: Bool
    /// Raw EKEvent identifier (shared across occurrences of a recurring
    /// event, unlike `id`); needed for the ical://ekevent/ deep link
    /// that opens the event in Calendar.app.
    public let eventIdentifier: String
    public let location: String?
    public let videoCallURL: URL?

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
        eventIdentifier: String = "",
        location: String? = nil,
        videoCallURL: URL? = nil
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
        self.eventIdentifier = eventIdentifier
        self.location = location
        self.videoCallURL = videoCallURL
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
