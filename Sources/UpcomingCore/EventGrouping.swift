import Foundation

public enum EventGrouping {
    /// Groups events into per-day sections for the agenda list.
    ///
    /// Multi-day events appear as a section entry on *every* day they
    /// span (clamped to [from, to]). All-day events sort before timed
    /// ones; timed events sort by start time.
    public static func sections(
        events: [EventItem],
        from: Date,
        to: Date,
        calendar: Calendar = .current
    ) -> [DaySection] {
        let rangeStart = calendar.startOfDay(for: from)
        let rangeEnd = calendar.startOfDay(for: to)
        var byDay: [Date: (allDay: [EventItem], timed: [EventItem])] = [:]

        for event in events {
            // Last day the event touches. The -1s nudge keeps an event
            // ending exactly at midnight from leaking into the next day
            // (EventKit all-day events end at the following midnight).
            let lastInstant = max(event.start, event.end.addingTimeInterval(-1))
            var day = calendar.startOfDay(for: event.start)
            let lastDay = calendar.startOfDay(for: lastInstant)

            while day <= min(lastDay, rangeEnd) {
                if day >= rangeStart {
                    var bucket = byDay[day] ?? ([], [])
                    if event.isAllDay {
                        bucket.allDay.append(event)
                    } else {
                        bucket.timed.append(event)
                    }
                    byDay[day] = bucket
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }

        return byDay.keys.sorted().map { day in
            let bucket = byDay[day]!
            return DaySection(
                day: day,
                allDay: bucket.allDay.sorted { $0.title < $1.title },
                timed: bucket.timed.sorted { $0.start < $1.start }
            )
        }
    }

    /// Per-day calendar dot colours for the month grid: the distinct
    /// calendars (in first-appearance order) that have events that day.
    public static func dotColors(
        events: [EventItem],
        calendar: Calendar = .current
    ) -> [Date: [CalendarColor]] {
        var seen: [Date: [String]] = [:]
        var colors: [Date: [CalendarColor]] = [:]

        for event in events.sorted(by: { $0.start < $1.start }) {
            let lastInstant = max(event.start, event.end.addingTimeInterval(-1))
            var day = calendar.startOfDay(for: event.start)
            let lastDay = calendar.startOfDay(for: lastInstant)
            while day <= lastDay {
                if seen[day, default: []].contains(event.calendarID) == false {
                    seen[day, default: []].append(event.calendarID)
                    colors[day, default: []].append(event.color)
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return colors
    }
}
