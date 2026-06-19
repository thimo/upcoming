import SwiftUI
import UpcomingCore

/// Hover preview for a month-grid day: the same day rendering as the agenda
/// list below (header + all-day pills + birthdays + timed rows), on the
/// shared preview chrome. Display-only — all-day events show individually
/// (no count-pill collapsing, which is a list-interaction feature).
struct DayPopoverView: View {
    let section: DaySection
    let calendar: Calendar
    let now: Date
    @Environment(\.colorScheme) private var colorScheme

    /// Matches the agenda list's content width (popup 320 − 24 padding).
    static let contentWidth: CGFloat = 296

    private var palette: PillPalette { PillPalette(colorScheme: colorScheme) }

    var body: some View {
        let pills = section.allDay.filter { !$0.isBirthday }
        let birthdays = section.allDay.filter(\.isBirthday)

        VStack(alignment: .leading, spacing: 6) {
            DayHeaderView(day: section.day, calendar: calendar)
            if !pills.isEmpty {
                FlowLayout(spacing: 3) {
                    ForEach(pills) { event in
                        AllDayPillView(event: event, palette: palette)
                    }
                }
            }
            ForEach(birthdays) { event in
                BirthdayRowView(event: event)
            }
            ForEach(section.timed) { event in
                EventRowView(
                    event: event, day: section.day,
                    now: now, calendar: calendar, palette: palette
                )
            }
        }
    }
}
