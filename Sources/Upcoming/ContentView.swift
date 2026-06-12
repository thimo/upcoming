import SwiftUI
import UpcomingCore

/// Popup root: month grid on top, agenda list below.
struct ContentView: View {
    @EnvironmentObject private var calendarService: CalendarService
    @EnvironmentObject private var config: AppConfig
    @Environment(\.openSettings) private var openSettings

    /// Any date inside the month shown by the grid.
    @State private var displayedMonth = Date()
    /// Merged dot data handed to the grid: the agenda window's dots are a
    /// free byproduct of the agenda fetch (month navigation inside the
    /// window never touches EventKit — that's what makes the dots
    /// Fantastical-fast); months outside it are fetched on demand and
    /// cached per grid start.
    @State private var dotColors: [Date: [CalendarColor]] = [:]
    @State private var windowDotColors: [Date: [CalendarColor]] = [:]
    @State private var extraDotColors: [Date: [CalendarColor]] = [:]
    @State private var fetchedGridStarts: Set<Date> = []
    @State private var sections: [DaySection] = []
    /// All events in the loaded window; window extensions fetch only the
    /// new 180-day slice and merge into this (a full-window refetch per
    /// extension gets seconds-slow once heavy scrolling has grown the
    /// window to years).
    @State private var windowEvents: [EventItem] = []
    /// One-shot scroll command for the agenda list (grid clicks, the
    /// jump-to-today on open, prepend re-anchoring).
    @State private var scrollRequest: ScrollRequest?
    /// Drops out-of-order results when reloads overlap (fetches are async).
    @State private var reloadGeneration = 0
    /// Loaded agenda window; extended when scrolling near its edges.
    @State private var agendaStart: Date?
    @State private var agendaEnd: Date?
    /// Edge triggers stay disarmed until the list is positioned on today:
    /// the initial render starts at the oldest loaded day, and its
    /// onAppears would otherwise fire a spurious past-extension.
    @State private var agendaArmed = false
    @State private var extendingWindow = false
    /// Day the current sections were loaded for; lets a re-open skip the
    /// refetch when nothing changed (EventKit changes reload on their own).
    @State private var lastLoadedDay: Date?
    /// Render clock for "already happened today" dimming; bumped on open
    /// so rows re-dim even when the data didn't change.
    @State private var now = Date()
    /// Day section at the top of the agenda viewport; highlighted in the
    /// grid, and the grid follows it into other months.
    @State private var topVisibleDay: Date?
    /// calendarID → title, for the combined all-day count pills.
    @State private var calendarNames: [String: String] = [:]

    static let panelWidth: CGFloat = 320
    /// Initial window around today, and how it grows at the edges. A year
    /// back / ~13 months ahead means the prepend re-anchor jump is rare.
    private static let initialPastDays = 365
    private static let initialFutureDays = 395
    private static let extendByDays = 180
    private static let edgeThresholdDays = 21

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
                highlightedDay: topVisibleDay,
                onSelectDay: { day in
                    scrollRequest = ScrollRequest(
                        day: calendar.startOfDay(for: day),
                        animated: true
                    )
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
                    now: now,
                    combinePills: config.combineAllDayPills,
                    calendarNames: calendarNames,
                    scrollRequest: $scrollRequest,
                    onSectionAppear: sectionAppeared,
                    onTopDayChange: topDayChanged
                )
            }

            Divider()
            footer
        }
        // Width is fixed; height comes from the panel (AppDelegate clamps
        // the ideal height to the screen), with the agenda list flexing.
        .frame(width: Self.panelWidth)
        .onAppear { reloadAgenda(resetWindow: true, scrollToDay: Date()) }
        .onChange(of: displayedMonth) { reloadGridDots() }
        .onChange(of: calendarService.changeToken) { reloadAgenda() }
        .onChange(of: config.hiddenCalendarIDs) { reloadAgenda() }
        .onChange(of: scrollRequest) {
            // Request cleared = list positioned; only now arm the edge
            // triggers (and allow the next window extension).
            if scrollRequest == nil {
                agendaArmed = !sections.isEmpty
                extendingWindow = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .popupDidOpen)) { _ in
            displayedMonth = Date()
            now = Date()
            let today = calendar.startOfDay(for: Date())
            let windowIsInitial = initialWindow(around: today).map {
                $0.start == agendaStart && $0.end == agendaEnd
            } == true
            if today == lastLoadedDay, windowIsInitial {
                // Same day, initial window, and EventKit changes trigger
                // their own reload — the data is still valid. Just jump.
                scrollRequest = ScrollRequest(day: today, animated: false)
            } else {
                // Also lands here when heavy scrolling grew the window:
                // reopening resets to the normal size, which keeps
                // scrollTo (lazy height estimation) accurate.
                reloadAgenda(resetWindow: true, scrollToDay: today)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateAgendaDay)) { note in
            if let delta = note.userInfo?["delta"] as? Int {
                navigateDay(by: delta)
            }
        }
    }

    /// Arrow-key navigation: scroll the agenda one day forward/backward
    /// from the current view position. Empty days have no section, so
    /// land on the nearest section in the travel direction (the generic
    /// scroll handler only searches forward — backwards would stick).
    private func navigateDay(by delta: Int) {
        let anchor = topVisibleDay ?? calendar.startOfDay(for: Date())
        guard let target = calendar.date(byAdding: .day, value: delta, to: anchor) else { return }
        let destination = delta > 0
            ? sections.first(where: { $0.day >= target })?.day
            : sections.last(where: { $0.day <= target })?.day
        if let destination, destination != anchor {
            scrollRequest = ScrollRequest(day: destination, animated: true)
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

    /// Kicks off an async fetch of the agenda window; the popup never
    /// waits on EventKit. Stale data stays on screen for the few ms until
    /// fresh data lands. `scrollToDay` positions the list (without
    /// animation) once the new sections are in — used for the
    /// jump-to-today on open and for re-anchoring after a past-extension
    /// prepend.
    private func reloadAgenda(resetWindow: Bool = false, scrollToDay: Date? = nil) {
        let cal = calendar
        let today = cal.startOfDay(for: Date())
        let hidden = config.hiddenCalendarIDs

        if resetWindow || agendaStart == nil || agendaEnd == nil {
            let initial = initialWindow(around: today)
            agendaStart = initial?.start
            agendaEnd = initial?.end
            agendaArmed = false
        }
        guard let windowStart = agendaStart, let windowEnd = agendaEnd else { return }

        reloadGeneration += 1
        let generation = reloadGeneration

        Task {
            let agendaEvents = await calendarService.events(
                from: windowStart, to: windowEnd, hiddenCalendarIDs: hidden
            )

            guard generation == reloadGeneration else { return }
            calendarNames = Dictionary(
                uniqueKeysWithValues: calendarService.calendars().map { ($0.id, $0.title) }
            )
            windowEvents = agendaEvents
            sections = EventGrouping.sections(
                events: agendaEvents,
                from: windowStart,
                to: windowEnd,
                calendar: cal
            )
            // Dots for the whole window come free with this fetch.
            // Out-of-window extras are stale now (data changed); refill
            // below if the displayed month needs them.
            windowDotColors = EventGrouping.dotColors(events: agendaEvents, calendar: cal)
            extraDotColors = [:]
            fetchedGridStarts = []
            dotColors = windowDotColors
            lastLoadedDay = today
            if let scrollToDay {
                scrollRequest = ScrollRequest(
                    day: cal.startOfDay(for: scrollToDay),
                    animated: false
                )
            } else {
                extendingWindow = false
            }
            reloadGridDots()
        }
    }

    /// Fetches dot data only when the displayed month falls (partly)
    /// outside the agenda window; everything inside is already in memory
    /// and needs no fetch at all.
    private func reloadGridDots() {
        let cal = calendar
        let today = cal.startOfDay(for: Date())

        // Grid range: the 6 visible weeks of the displayed month.
        let monthStart = cal.date(
            from: cal.dateComponents([.year, .month], from: displayedMonth)
        ) ?? today
        let gridStart = cal.dateInterval(of: .weekOfYear, for: monthStart)?.start ?? monthStart
        guard let gridEnd = cal.date(byAdding: .day, value: 42, to: gridStart) else { return }

        if let windowStart = agendaStart, let windowEnd = agendaEnd,
           gridStart >= windowStart, gridEnd <= windowEnd {
            return // covered by the agenda window
        }
        guard !fetchedGridStarts.contains(gridStart) else { return }
        fetchedGridStarts.insert(gridStart)

        let hidden = config.hiddenCalendarIDs
        let generation = reloadGeneration

        Task {
            let gridEvents = await calendarService.events(
                from: gridStart, to: gridEnd, hiddenCalendarIDs: hidden
            )
            // A newer agenda reload invalidates this fetch (it cleared
            // the extras and will refill for the current month itself).
            guard generation == reloadGeneration else { return }
            extraDotColors.merge(
                EventGrouping.dotColors(events: gridEvents, calendar: cal)
            ) { _, new in new }
            dotColors = windowDotColors.merging(extraDotColors) { inWindow, _ in inWindow }
        }
    }

    /// Grid-follows-list: highlight the day at the top of the agenda and
    /// page the grid along when the list scrolls into another month.
    /// (Manual ‹ › navigation stays independent until the next scroll.)
    private func topDayChanged(_ day: Date) {
        guard day != topVisibleDay else { return }
        topVisibleDay = day
        if !calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month) {
            displayedMonth = day
        }
    }

    /// The window an open/reset starts from.
    private func initialWindow(around today: Date) -> (start: Date, end: Date)? {
        guard let start = calendar.date(byAdding: .day, value: -Self.initialPastDays, to: today),
              let end = calendar.date(byAdding: .day, value: Self.initialFutureDays, to: today)
        else { return nil }
        return (start, end)
    }

    /// Called for every day-section scrolling into view. Near the loaded
    /// window's edges this extends the window — that's the "infinite" in
    /// the infinite scroll.
    private func sectionAppeared(_ day: Date) {
        guard agendaArmed, !extendingWindow,
              let windowStart = agendaStart, let windowEnd = agendaEnd else { return }
        let cal = calendar

        if let pastEdge = cal.date(byAdding: .day, value: Self.edgeThresholdDays, to: windowStart),
           day < pastEdge {
            // Prepending grows the content above the viewport, which would
            // visually teleport the list; re-anchor on the day that
            // triggered the load to keep the jump within a section.
            extendWindow(intoPast: true, reanchorOn: day)
        } else if let futureEdge = cal.date(byAdding: .day, value: -Self.edgeThresholdDays, to: windowEnd),
                  day > futureEdge {
            // Appending doesn't move existing content; no re-anchor needed.
            extendWindow(intoPast: false, reanchorOn: nil)
        }
    }

    /// Grows the loaded window by `extendByDays`, fetching only the new
    /// slice and merging it into `windowEvents` — never the whole window,
    /// which gets seconds-slow after sustained scrolling.
    private func extendWindow(intoPast: Bool, reanchorOn anchor: Date?) {
        guard let windowStart = agendaStart, let windowEnd = agendaEnd else { return }
        let cal = calendar
        let hidden = config.hiddenCalendarIDs

        let newStart: Date
        let newEnd: Date
        if intoPast {
            guard let extended = cal.date(byAdding: .day, value: -Self.extendByDays, to: windowStart)
            else { return }
            newStart = extended
            newEnd = windowEnd
        } else {
            guard let extended = cal.date(byAdding: .day, value: Self.extendByDays, to: windowEnd)
            else { return }
            newStart = windowStart
            newEnd = extended
        }

        extendingWindow = true
        agendaStart = newStart
        agendaEnd = newEnd
        let generation = reloadGeneration

        Task {
            let delta = await calendarService.events(
                from: intoPast ? newStart : windowEnd,
                to: intoPast ? windowStart : newEnd,
                hiddenCalendarIDs: hidden
            )
            // A full reload (EventKit change, settings, re-open) started
            // meanwhile and supersedes this slice.
            guard generation == reloadGeneration else { return }

            // Events spanning the old boundary arrive in both fetches.
            let known = Set(windowEvents.map(\.id))
            windowEvents.append(contentsOf: delta.filter { !known.contains($0.id) })

            sections = EventGrouping.sections(
                events: windowEvents,
                from: newStart,
                to: newEnd,
                calendar: cal
            )
            windowDotColors = EventGrouping.dotColors(events: windowEvents, calendar: cal)
            dotColors = windowDotColors.merging(extraDotColors) { inWindow, _ in inWindow }

            if let anchor {
                scrollRequest = ScrollRequest(day: anchor, animated: false)
            } else {
                extendingWindow = false
            }
        }
    }
}
