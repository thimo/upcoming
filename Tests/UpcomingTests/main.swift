import Foundation
import UpcomingCore

// Plain-Swift test runner (XCTest doesn't ship with the Command Line
// Tools). Run via `.build/release/UpcomingTests` after a build.

var passed = 0
var failed = 0

func expect(_ condition: Bool, _ name: String) {
    if condition {
        passed += 1
    } else {
        failed += 1
        print("FAIL: \(name)")
    }
}

func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
    var components = DateComponents()
    components.year = y
    components.month = mo
    components.day = d
    components.hour = h
    components.minute = mi
    return Calendar.current.date(from: components)!
}

let gray = CalendarColor(red: 0.5, green: 0.5, blue: 0.5)
let blue = CalendarColor(red: 0, green: 0, blue: 1)

func event(
    id: String,
    cal calID: String = "cal1",
    color: CalendarColor = CalendarColor(red: 0.5, green: 0.5, blue: 0.5),
    start: Date,
    end: Date,
    allDay: Bool = false,
    location: String? = nil,
    url: URL? = nil,
    notes: String? = nil
) -> EventItem {
    EventItem(
        id: id,
        title: id,
        calendarID: calID,
        color: color,
        start: start,
        end: end,
        isAllDay: allDay,
        location: location,
        videoCallURL: VideoCallDetector.detect(url: url, location: location, notes: notes)
    )
}

// MARK: - VideoCallDetector

let teamsNotes = """
Agenda attached.
Join: https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%7d
"""
expect(
    VideoCallDetector.detect(url: nil, location: nil, notes: teamsNotes)?
        .absoluteString.contains("teams.microsoft.com") == true,
    "detects Teams link buried in notes"
)
expect(
    VideoCallDetector.detect(
        url: nil,
        location: "https://company.zoom.us/j/123456789",
        notes: nil
    ) != nil,
    "detects Zoom link in location"
)
expect(
    VideoCallDetector.detect(
        url: URL(string: "https://meet.google.com/abc-defg-hij"),
        location: nil,
        notes: nil
    ) != nil,
    "detects Meet link in URL field"
)
expect(
    VideoCallDetector.detect(
        url: URL(string: "https://example.com/agenda.pdf"),
        location: "Kantoor Arnhem",
        notes: "Geen call vandaag"
    ) == nil,
    "no false positive on plain links and text"
)
expect(
    VideoCallDetector.detect(
        url: URL(string: "https://zoom.us/j/111"),
        location: nil,
        notes: "https://meet.google.com/zzz-zzzz-zzz"
    )?.absoluteString.contains("zoom.us") == true,
    "URL field wins over notes"
)

expect(
    VideoCallDetector.teamsAppURL(
        for: URL(string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%7d")!
    )?.absoluteString == "msteams://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%7d",
    "rewrites Teams join link to msteams: scheme, query intact"
)
expect(
    VideoCallDetector.teamsAppURL(for: URL(string: "https://zoom.us/j/123")!) == nil,
    "no msteams rewrite for non-Teams links"
)
expect(
    VideoCallDetector.teamsAppURL(for: URL(string: "https://teams.live.com/meet/123")!) == nil,
    "no msteams rewrite for personal teams.live.com links"
)

// MARK: - EventGrouping.sections

let from = date(2026, 6, 11)
let to = date(2026, 6, 25)

let single = event(id: "single", start: date(2026, 6, 12, 10), end: date(2026, 6, 12, 11))
let multiDay = event(
    id: "multi",
    start: date(2026, 6, 13),
    end: date(2026, 6, 16), // EventKit-style: all-day end at next midnight
    allDay: true
)
let sections = EventGrouping.sections(
    events: [single, multiDay],
    from: from,
    to: to
)

expect(sections.count == 4, "one section for the single day + three for the span")
expect(
    sections.filter { $0.allDay.contains(where: { $0.id == "multi" }) }.count == 3,
    "multi-day all-day event appears on each of its 3 days"
)
expect(
    sections.first(where: { $0.day == date(2026, 6, 16) }) == nil,
    "all-day event ending at midnight does not leak into the next day"
)

let early = event(id: "early", start: date(2026, 6, 12, 9), end: date(2026, 6, 12, 9, 30))
let pill = event(id: "pill", start: date(2026, 6, 12), end: date(2026, 6, 13), allDay: true)
let ordered = EventGrouping.sections(events: [single, early, pill], from: from, to: to)
expect(
    ordered.first?.allDay.map(\.id) == ["pill"] &&
    ordered.first?.timed.map(\.id) == ["early", "single"],
    "all-day pills separated, timed sorted by start"
)

let outside = event(id: "outside", start: date(2026, 6, 9, 10), end: date(2026, 6, 9, 11))
expect(
    EventGrouping.sections(events: [outside], from: from, to: to).isEmpty,
    "events before the range produce no sections"
)

// MARK: - EventGrouping.dotColors

let sameCalA = event(id: "a", cal: "work", color: blue, start: date(2026, 6, 12, 9), end: date(2026, 6, 12, 10))
let sameCalB = event(id: "b", cal: "work", color: blue, start: date(2026, 6, 12, 11), end: date(2026, 6, 12, 12))
let otherCal = event(id: "c", cal: "home", color: gray, start: date(2026, 6, 12, 13), end: date(2026, 6, 12, 14))
let dots = EventGrouping.dotColors(events: [sameCalA, sameCalB, otherCal])
expect(
    dots[date(2026, 6, 12)]?.count == 2,
    "one dot per calendar, not per event"
)

let spanDots = EventGrouping.dotColors(events: [multiDay])
expect(
    spanDots[date(2026, 6, 13)] != nil &&
    spanDots[date(2026, 6, 15)] != nil &&
    spanDots[date(2026, 6, 16)] == nil,
    "multi-day event dots every spanned day, midnight end excluded"
)

// MARK: - ParticipantStatus (declined filter family)

expect(ParticipantStatus.isDeclined(.declined), "declined status is declined")
expect(!ParticipantStatus.isDeclined(.accepted), "accepted is not declined")
expect(!ParticipantStatus.isDeclined(nil), "non-attendee (own event) is not declined")

expect(ParticipantStatus.isPending(.pending), "pending invitation is pending")
expect(
    ParticipantStatus.isPending(.unknown),
    "unknown counts as pending — Exchange/Google deliver needs-action as unknown"
)
expect(!ParticipantStatus.isPending(.accepted), "accepted is not pending")
expect(!ParticipantStatus.isPending(nil), "non-attendee is not a pending invitation")

expect(ParticipantStatus.isTentative(.tentative), "tentative status is tentative")
expect(!ParticipantStatus.isTentative(.accepted), "accepted is not tentative")

expect(ParticipantStatus.accepted.attendeeStatus == .accepted, "accepted → accepted glyph")
expect(ParticipantStatus.declined.attendeeStatus == .declined, "declined → declined glyph")
expect(ParticipantStatus.tentative.attendeeStatus == .tentative, "tentative → tentative glyph")
expect(ParticipantStatus.pending.attendeeStatus == .noResponse, "pending → no-response glyph")
expect(ParticipantStatus.unknown.attendeeStatus == .noResponse, "unknown → no-response glyph")
expect(ParticipantStatus.delegated.attendeeStatus == .noResponse, "delegated → no-response glyph")
expect(ParticipantStatus.other.attendeeStatus == .noResponse, "other → no-response glyph")

// MARK: - AgendaWindow (infinite-scroll window math)

let winStart = date(2026, 1, 1)
let winEnd = date(2026, 12, 31)

expect(
    AgendaWindow.edge(for: date(2026, 1, 5), windowStart: winStart, windowEnd: winEnd, thresholdDays: 30) == .past,
    "day within threshold of the start extends into the past"
)
expect(
    AgendaWindow.edge(for: date(2026, 12, 20), windowStart: winStart, windowEnd: winEnd, thresholdDays: 30) == .future,
    "day within threshold of the end extends into the future"
)
expect(
    AgendaWindow.edge(for: date(2026, 6, 15), windowStart: winStart, windowEnd: winEnd, thresholdDays: 30) == .none,
    "day in the middle does not extend the window"
)
expect(
    AgendaWindow.edge(for: winStart, windowStart: winStart, windowEnd: winEnd, thresholdDays: 0) == .none,
    "zero threshold: a day exactly on the edge does not trigger an extension"
)

let pastSlice = AgendaWindow.slice(intoPast: true, windowStart: winStart, windowEnd: winEnd, extendByDays: 180)
expect(
    pastSlice?.newStart == date(2025, 7, 5) && pastSlice?.newEnd == winEnd,
    "past extension grows the start back by 180 days, end unchanged"
)
expect(
    pastSlice?.fetchFrom == date(2025, 7, 5) && pastSlice?.fetchTo == winStart,
    "past extension fetches only the new leading slice, up to the old start"
)

let futureSlice = AgendaWindow.slice(intoPast: false, windowStart: winStart, windowEnd: winEnd, extendByDays: 180)
expect(
    futureSlice?.newStart == winStart && futureSlice?.newEnd == date(2027, 6, 29),
    "future extension grows the end forward by 180 days, start unchanged"
)
expect(
    futureSlice?.fetchFrom == winEnd && futureSlice?.fetchTo == date(2027, 6, 29),
    "future extension fetches only the new trailing slice, from the old end"
)

let known = event(id: "known", start: date(2026, 6, 1, 9), end: date(2026, 6, 1, 10))
let boundary = event(id: "boundary", start: date(2026, 6, 2, 9), end: date(2026, 6, 2, 10))
let fresh = event(id: "fresh", start: date(2026, 6, 3, 9), end: date(2026, 6, 3, 10))
let merged = AgendaWindow.merge(existing: [known, boundary], delta: [boundary, fresh])
expect(
    merged.map(\.id) == ["known", "boundary", "fresh"],
    "merge appends new events and drops boundary-spanning duplicates, order preserved"
)

// MARK: - Result

print("\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
