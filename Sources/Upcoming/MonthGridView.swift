import SwiftUI
import UpcomingCore

/// Fantastical-style month grid: CW column, Monday-first weeks, per-day
/// calendar dots, filled circle on today, subtle highlight on the current
/// week row, ‹ › month navigation.
struct MonthGridView: View {
    @Binding var displayedMonth: Date
    let dotColors: [Date: [CalendarColor]]
    let calendar: Calendar

    private static let maxDots = 4

    var body: some View {
        VStack(spacing: 6) {
            header
            weekdayRow
            ForEach(weeks, id: \.first) { week in
                weekRow(week)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(monthName)
                .font(.system(size: 24, weight: .bold))
            Text(yearName)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.red)
            Spacer()
            Button(action: { step(by: -1) }) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            Button(action: { step(by: 1) }) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
        }
        .padding(.bottom, 2)
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
        HStack(spacing: 0) {
            Text("CW")
                .frame(width: 24)
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol.uppercased())
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.secondary)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        // veryShortStandaloneWeekdaySymbols starts at Sunday; rotate to
        // the calendar's firstWeekday (Monday).
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
                .foregroundStyle(.secondary)
                .frame(width: 24)
            ForEach(week, id: \.self) { day in
                dayCell(day)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(containsToday ? Color.primary.opacity(0.07) : Color.clear)
        )
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let inMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let dots = dotColors[calendar.startOfDay(for: day)] ?? []

        return VStack(spacing: 2) {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 12, weight: isToday ? .bold : .regular))
                .foregroundStyle(
                    isToday ? Color.white : (inMonth ? Color.primary : Color.secondary.opacity(0.6))
                )
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(isToday ? Color.accentColor : Color.clear)
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
