import SwiftUI
import UpcomingCore

/// Fantastical-style month grid: CW column, Monday-first weeks, per-day
/// calendar dots, filled circle on today, subtle highlight on the current
/// week row, ‹ › month navigation.
struct MonthGridView: View {
    @Binding var displayedMonth: Date
    let dotColors: [Date: [CalendarColor]]
    let calendar: Calendar
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
            HStack(alignment: .firstTextBaseline) {
                // Solid black on purpose: `.primary` gets washed grey by
                // the panel's vibrancy. Spec: month black, year red
                // (Fantastical).
                Text(monthName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.black)
                Text(yearName)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.red)
            }
            Spacer()
            // Zero spacing: the ghost-button hover padding already
            // separates the chevrons visually.
            HStack(spacing: 0) {
                navButton("chevron.left") { step(by: -1) }
                navButton("chevron.right") { step(by: 1) }
            }
        }
        .padding(.bottom, 9)
    }

    /// Month-nav chevron with a comfortably clickable target and the
    /// footer's hover treatment.
    private func navButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 16, height: 20)
        }
        .buttonStyle(GhostButtonStyle())
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
        // Fantastical highlights the current weekday in the header row.
        let todayIndex = (calendar.component(.weekday, from: Date()) - calendar.firstWeekday + 7) % 7
        return HStack(spacing: 0) {
            // Week-number column keeps its width; the "CW" label proved
            // more cryptic than helpful.
            Color.clear
                .frame(width: 24, height: 1)
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                Text(symbol.uppercased())
                    .foregroundStyle(index == todayIndex ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.secondary)
    }

    private var weekdaySymbols: [String] {
        // Three-letter day names ("MON"), not single letters.
        let symbols = calendar.shortStandaloneWeekdaySymbols
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
        let containsToday = week.contains { calendar.isDateInToday($0) }
        return HStack(spacing: 0) {
            Text("\(calendar.component(.weekOfYear, from: week.first ?? Date()))")
                .font(.system(size: 9))
                .foregroundStyle(containsToday ? Color.accentColor : Color.secondary)
                .frame(width: 24)
            ForEach(week, id: \.self) { day in
                dayCell(day)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(containsToday ? Color.primary.opacity(0.07) : Color.clear)
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

        // Dots sit tight under the number (Fantastical): no cell-internal
        // spacing, compact circle.
        return VStack(spacing: 0) {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 12, weight: isToday ? .bold : .regular))
                .foregroundStyle(
                    isToday ? Color.white : (inMonth ? Color.primary : Color.secondary.opacity(0.6))
                )
                .frame(width: 20, height: 20)
                .background(
                    Circle().fill(
                        isToday
                            ? Color.accentColor
                            : isHighlighted ? Color.primary.opacity(0.12) : Color.clear
                    )
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
