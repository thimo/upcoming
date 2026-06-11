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

// MARK: - Result

print("\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
