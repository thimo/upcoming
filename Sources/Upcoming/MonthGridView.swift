import SwiftUI
import UpcomingCore

/// Fantastical-style month grid: CW column, Monday-first weeks, per-day
/// calendar dots, filled circle on today, subtle highlight on the current
/// week row, ‹ › month navigation.
struct MonthGridView: View {
    @Binding var displayedMonth: Date
    let dotColors: [Date: [CalendarColor]]
    let calendar: Calendar
    @Environment(\.colorScheme) private var colorScheme
    /// Day at the top of the agenda list (grid-follows-list highlight);
    /// rendered as a grey circle, distinct from the blue today circle.
    let highlightedDay: Date?
    /// Called when the user clicks a day cell (agenda jumps there).
    let onSelectDay: (Date) -> Void

    private static let maxDots = 4

    var body: some View {
        VStack(spacing: 3) {
            header
            weekdayRow
            ForEach(weeks, id: \.first) { week in
                weekRow(week)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        // Title texts share a baseline; the chevrons centre on the whole
        // title block instead of hanging off that (low) baseline.
        HStack {
            // Apple Calendar styling: month bold, year light, one colour.
            // Single concatenated Text so the scale-factor safety net for
            // long month names shrinks month and year together (separate
            // Texts scale independently — the year ends up bigger).
            // Explicit solid colour on purpose — `.primary` gets washed
            // out by the panel's vibrancy.
            (Text(monthName).fontWeight(.bold)
                + Text(" ")
                + Text(yearName).fontWeight(.light))
                .font(.system(size: 26))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            // Apple Calendar's ‹ Today › cluster: circular chevron
            // buttons flanking a capsule Today button.
            HStack(spacing: 4) {
                navButton("chevron.left") { step(by: -1) }
                todayButton
                navButton("chevron.right") { step(by: 1) }
            }
        }
        .padding(.bottom, 12)
    }

    /// Month-nav chevron in a circular grey button (Apple Calendar).
    private func navButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(CalendarNavButtonStyle(shape: Circle()))
        .pointingHandCursor()
    }

    /// Capsule Today button between the chevrons: snaps the grid back to
    /// the current month and scrolls the agenda to today.
    private var todayButton: some View {
        Button {
            let today = calendar.startOfDay(for: Date())
            displayedMonth = today
            onSelectDay(today)
        } label: {
            Text("Today")
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .frame(height: 22)
        }
        .buttonStyle(CalendarNavButtonStyle(shape: Capsule()))
        .pointingHandCursor()
    }

    private func step(by months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: displayedMonth) {
            displayedMonth = next
        }
    }

    private var monthName: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter.string(from: displayedMonth)
    }

    private var yearName: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("y")
        return formatter.string(from: displayedMonth)
    }

    // MARK: - Grid

    private var weekdayRow: some View {
        // Apple Calendar's mini-month style: single letters, quiet grey,
        // no highlight on the current weekday (the today marker in the
        // grid already does that job).
        HStack(spacing: 0) {
            // Week-number column keeps its width; the "CW" label proved
            // more cryptic than helpful.
            Color.clear
                .frame(width: 24, height: 1)
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
    }

    private var weekdaySymbols: [String] {
        // Single letters (M T W T F S S), Apple Calendar's mini-month.
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        // Symbols start at Sunday; rotate to the calendar's firstWeekday
        // (Monday).
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private var weeks: [[Date]] {
        guard let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: displayedMonth)
        ), let gridStart = calendar.dateInterval(of: .weekOfYear, for: monthStart)?.start else {
            return []
        }
        return (0..<6).map { row in
            (0..<7).compactMap { col in
                calendar.date(byAdding: .day, value: row * 7 + col, to: gridStart)
            }
        }
    }

    private func weekRow(_ week: [Date]) -> some View {
        // The row highlight follows the list position (like the day ring),
        // not today — "where am I looking", consistent with
        // grid-follows-list. Falls back to today before the first scroll.
        let anchor = highlightedDay ?? Date()
        let containsAnchor = week.contains { calendar.isDate($0, inSameDayAs: anchor) }
        return HStack(spacing: 0) {
            Text("\(calendar.component(.weekOfYear, from: week.first ?? Date()))")
                .font(.system(size: 9))
                .foregroundStyle(containsAnchor ? Color.accentColor : Color.secondary)
                .frame(width: 24)
            ForEach(week, id: \.self) { day in
                dayCell(day)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(
            // Negative padding: the highlight extends 1pt above/below and
            // 2pt left/right of the row content without affecting layout.
            RoundedRectangle(cornerRadius: 6)
                .fill(containsAnchor ? Color.primary.opacity(0.07) : Color.clear)
                .padding(.vertical, -1)
                .padding(.horizontal, -2)
        )
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let inMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let dots = dotColors[calendar.startOfDay(for: day)] ?? []
        // Today's blue circle wins over the list-position highlight.
        let isHighlighted = !isToday && highlightedDay.map {
            calendar.isDate(day, inSameDayAs: $0)
        } == true

        // Both markers are rounded squares (one shape family; circles'
        // bottoms land on the dot row): filled red = today (Apple
        // Calendar), blue ring = where the list is. They coincide when
        // the list sits on today. 2pt air between cell and dots.
        return VStack(spacing: 2) {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 12, weight: isToday ? .bold : .regular))
                .foregroundStyle(
                    isToday ? Color.white : (inMonth ? Color.primary : Color.secondary.opacity(0.6))
                )
                .frame(width: 24, height: 21)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isToday ? Color.todayRed : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                        .opacity(isHighlighted ? 1 : 0)
                )
            HStack(spacing: 2) {
                ForEach(Array(dots.prefix(Self.maxDots).enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(Color(calendarColor: color))
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelectDay(day) }
    }
}

extension Color {
    init(calendarColor: CalendarColor) {
        self.init(
            red: calendarColor.red,
            green: calendarColor.green,
            blue: calendarColor.blue
        )
    }
}
