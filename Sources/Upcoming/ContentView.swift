import SwiftUI
import UpcomingCore

/// Popup root: month grid on top, agenda list below.
struct ContentView: View {
    @EnvironmentObject private var calendarService: CalendarService
    @EnvironmentObject private var config: AppConfig
    @Environment(\.openSettings) private var openSettings

    /// Any date inside the month shown by the grid.
    @State private var displayedMonth = Date()
    @State private var dotColors: [Date: [CalendarColor]] = [:]
    @State private var sections: [DaySection] = []
    /// Set by a grid-day click; the agenda list scrolls there and clears it.
    @State private var scrollTarget: Date?
    /// Drops out-of-order results when reloads overlap (fetches are async).
    @State private var reloadGeneration = 0

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
                calendar: calendar,
                onSelectDay: { day in
                    scrollTarget = calendar.startOfDay(for: day)
                }
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if calendarService.authState == .denied {
                accessDeniedView
            } else {
                AgendaListView(
                    sections: sections,
                    calendar: calendar,
                    scrollTarget: $scrollTarget
                )
            }

            Divider()
            footer
        }
        .frame(width: Self.panelWidth, height: 760)
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

    /// Bottom bar: gear → Settings, Quit on the right (Uncommitted's footer).
    private var footer: some View {
        HStack {
            Button {
                // LSUIElement apps don't auto-activate when a SwiftUI
                // window opens; without this the Settings window comes up
                // with an inactive titlebar.
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
                AppDelegate.shared?.closePopup()
            } label: {
                Text(Image(systemName: "gearshape"))
            }
            .buttonStyle(GhostButtonStyle())
            .foregroundStyle(.primary.opacity(0.70))
            .font(.callout)
            .keyboardShortcut(",")
            .help("Settings")
            .pointingHandCursor()

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(GhostButtonStyle())
            .foregroundStyle(.primary.opacity(0.70))
            .font(.callout)
            .keyboardShortcut("q")
            .pointingHandCursor()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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

    /// Kicks off an async fetch; the popup never waits on EventKit. Stale
    /// data stays on screen for the few ms until fresh data lands.
    private func reload() {
        let cal = calendar
        let today = cal.startOfDay(for: Date())
        let hidden = config.hiddenCalendarIDs

        // Grid range: the 6 visible weeks of the displayed month.
        let monthStart = cal.date(
            from: cal.dateComponents([.year, .month], from: displayedMonth)
        ) ?? today
        let gridStart = cal.dateInterval(of: .weekOfYear, for: monthStart)?.start ?? monthStart
        let gridEnd = cal.date(byAdding: .day, value: 42, to: gridStart) ?? monthStart

        // Agenda range: today onward. Bidirectional infinite scroll is on
        // the roadmap; this fixed forward window is the v0 placeholder.
        let agendaEnd = cal.date(byAdding: .day, value: Self.agendaDaysAhead, to: today) ?? today

        reloadGeneration += 1
        let generation = reloadGeneration

        Task {
            async let gridFetch = calendarService.events(
                from: gridStart, to: gridEnd, hiddenCalendarIDs: hidden
            )
            async let agendaFetch = calendarService.events(
                from: today, to: agendaEnd, hiddenCalendarIDs: hidden
            )
            let (gridEvents, agendaEvents) = await (gridFetch, agendaFetch)

            guard generation == reloadGeneration else { return }
            dotColors = EventGrouping.dotColors(events: gridEvents, calendar: cal)
            sections = EventGrouping.sections(
                events: agendaEvents,
                from: today,
                to: agendaEnd,
                calendar: cal
            )
        }
    }
}
