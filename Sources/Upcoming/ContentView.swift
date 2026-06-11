import SwiftUI
import UpcomingCore

/// Popup root: month grid on top, agenda list below.
struct ContentView: View {
    @EnvironmentObject private var calendarService: CalendarService
    @EnvironmentObject private var config: AppConfig

    /// Any date inside the month shown by the grid.
    @State private var displayedMonth = Date()
    @State private var dotColors: [Date: [CalendarColor]] = [:]
    @State private var sections: [DaySection] = []

    static let panelWidth: CGFloat = 320
    private static let agendaDaysAhead = 60

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday, per spec
        return cal
    }

    var body: some View {
        VStack(spacing: 0) {
            MonthGridView(
                displayedMonth: $displayedMonth,
                dotColors: dotColors,
                calendar: calendar
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if calendarService.authState == .denied {
                accessDeniedView
            } else {
                AgendaListView(sections: sections, calendar: calendar)
            }
        }
        .frame(width: Self.panelWidth, height: 560)
        .onAppear(perform: reload)
        .onChange(of: displayedMonth) { reload() }
        .onChange(of: calendarService.changeToken) { reload() }
        .onChange(of: config.hiddenCalendarIDs) { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .popupDidOpen)) { _ in
            // Re-open resets to the current month and fresh data.
            displayedMonth = Date()
            reload()
        }
    }

    private var accessDeniedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No calendar access")
                .font(.headline)
            Text("Grant access in System Settings → Privacy & Security → Calendars.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxHeight: .infinity)
    }

    private func reload() {
        let cal = calendar
        let today = cal.startOfDay(for: Date())

        // Grid range: the 6 visible weeks of the displayed month.
        let monthStart = cal.date(
            from: cal.dateComponents([.year, .month], from: displayedMonth)
        ) ?? today
        let gridStart = cal.dateInterval(of: .weekOfYear, for: monthStart)?.start ?? monthStart
        let gridEnd = cal.date(byAdding: .day, value: 42, to: gridStart) ?? monthStart

        let gridEvents = calendarService.events(
            from: gridStart,
            to: gridEnd,
            hiddenCalendarIDs: config.hiddenCalendarIDs
        )
        dotColors = EventGrouping.dotColors(events: gridEvents, calendar: cal)

        // Agenda range: today onward. Bidirectional infinite scroll is on
        // the roadmap; this fixed forward window is the v0 placeholder.
        let agendaEnd = cal.date(byAdding: .day, value: Self.agendaDaysAhead, to: today) ?? today
        let agendaEvents = calendarService.events(
            from: today,
            to: agendaEnd,
            hiddenCalendarIDs: config.hiddenCalendarIDs
        )
        sections = EventGrouping.sections(
            events: agendaEvents,
            from: today,
            to: agendaEnd,
            calendar: cal
        )
    }
}
