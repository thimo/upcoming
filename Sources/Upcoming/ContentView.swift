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
    /// Day → section lookup for the grid's day-hover preview. The agenda
    /// window's sections come free with the fetch; out-of-window grid
    /// months get theirs from the on-demand grid fetch (`extraSections`).
    @State private var windowSectionsByDay: [Date: DaySection] = [:]
    @State private var extraSectionsByDay: [Date: DaySection] = [:]
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
    /// Agenda search query; when non-empty the list shows matching events
    /// from the loaded window instead of the live day-by-day agenda.
    @State private var searchQuery = ""
    /// Matching day-sections (chronological), computed on each query change
    /// and held in state — set together with the scroll request so the list
    /// lands on the next match reliably (mirrors the agenda's own reload).
    @State private var searchSections: [DaySection] = []
    /// A wide event corpus (±5y) fetched once per search session, so search
    /// reaches well beyond the loaded agenda window. Until it loads, search
    /// falls back to the in-memory window for instant (partial) results.
    @State private var searchEvents: [EventItem] = []
    @State private var searchCorpusLoaded = false
    /// Focus for the search field — taken on open so you can type straight away.
    @FocusState private var searchFocused: Bool

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

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !trimmedQuery.isEmpty }

    /// Events in the loaded window whose title or location matches the query,
    /// in plain chronological order (past above, future below), capped near
    /// today so the non-lazy search render stays snappy. The list is parked
    /// on the next match, so scroll up = past, scroll down = future.
    private func computeSearchSections() -> [DaySection] {
        let query = trimmedQuery
        guard !query.isEmpty else { return [] }
        // The wide corpus once it's fetched; the loaded window meanwhile.
        let source = searchCorpusLoaded ? searchEvents : windowEvents
        let matches = source.filter { event in
            event.title.localizedCaseInsensitiveContains(query)
                || (event.location?.localizedCaseInsensitiveContains(query) ?? false)
        }
        let cal = calendar
        guard let start = matches.map(\.start).min().map({ cal.startOfDay(for: $0) }),
              let end = matches.map(\.end).max().map({ cal.startOfDay(for: $0) }) else { return [] }
        let all = EventGrouping.sections(events: matches, from: start, to: end, calendar: cal)
        // Chronological, capped to the ~200 most-recent past + ~200 soonest
        // future day-sections so the non-lazy render can't blow up.
        let today = cal.startOfDay(for: Date())
        let past = all.filter { $0.day < today }.suffix(200)
        let future = all.filter { $0.day >= today }.prefix(200)
        return Array(past) + Array(future)
    }

    /// Fetches a wide ±5-year event corpus for search, once per session.
    private func loadSearchCorpus() {
        let cal = calendar
        let today = cal.startOfDay(for: Date())
        guard let from = cal.date(byAdding: .year, value: -5, to: today),
              let to = cal.date(byAdding: .year, value: 5, to: today) else { return }
        let hidden = config.hiddenCalendarIDs
        Task {
            let events = await calendarService.events(
                from: from, to: to, hiddenCalendarIDs: hidden
            )
            searchEvents = events
            searchCorpusLoaded = true
        }
    }

    /// Recompute results + park on the next upcoming match (the today
    /// boundary), so past sits above (scroll up) and future below (scroll
    /// down). Reliable because search renders non-lazily. Called when the
    /// query changes and when the corpus finishes loading.
    private func refreshSearch() {
        searchSections = computeSearchSections()
        let today = calendar.startOfDay(for: Date())
        let target = searchSections.first(where: { $0.day >= today })?.day
            ?? searchSections.last?.day
        if let target {
            scrollRequest = ScrollRequest(day: target, animated: false)
        }
    }

    /// Search box above the agenda; filters within the loaded window.
    /// Styled after Apple Calendar's search field — a capsule with a soft
    /// fill and a hairline border.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            TextField("Search", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
            if !searchQuery.isEmpty {
                Button { searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search at the very top (Fantastical-style), above the grid.
            searchField

            MonthGridView(
                displayedMonth: $displayedMonth,
                dotColors: dotColors,
                daySections: extraSectionsByDay.merging(windowSectionsByDay) { _, inWindow in inWindow },
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
            .padding(.bottom, 8)

            Divider()

            if calendarService.authState == .denied {
                accessDeniedView
            } else {
                let searching = isSearching
                // The TODAY divider sits before the first future match, but
                // only when there are past matches above it to separate from.
                let todayMarker: Date? = {
                    guard searching else { return nil }
                    let today = calendar.startOfDay(for: Date())
                    guard searchSections.contains(where: { $0.day < today }) else { return nil }
                    return searchSections.first(where: { $0.day >= today })?.day
                }()
                AgendaListView(
                    sections: searching ? searchSections : sections,
                    calendar: calendar,
                    now: now,
                    // Never collapse into "<calendar> · N" count pills while
                    // searching — the matching titles must stay visible.
                    combinePills: searching ? false : config.combineAllDayPills,
                    calendarNames: calendarNames,
                    emptyMessage: searching ? "No matching events" : "No upcoming events",
                    useLazyRows: !searching,
                    todayMarkerDay: todayMarker,
                    scrollRequest: $scrollRequest,
                    // While searching, freeze the infinite-scroll edge
                    // triggers and grid-follow (the result set is a flat
                    // filter of the loaded window, not the live agenda).
                    onSectionAppear: searching ? { _ in } : sectionAppeared,
                    onTopDayChange: searching ? { _ in } : topDayChanged,
                    onAddEvent: addEvent
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
        .onChange(of: searchQuery) {
            if isSearching {
                if !searchCorpusLoaded { loadSearchCorpus() }
                refreshSearch()
            } else {
                searchSections = []
                scrollRequest = ScrollRequest(day: calendar.startOfDay(for: Date()), animated: false)
            }
        }
        .onChange(of: searchEvents) {
            // Corpus arrived — refresh the (currently partial) results.
            if isSearching { refreshSearch() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .popupDidOpen)) { _ in
            displayedMonth = Date()
            now = Date()
            let wasSearching = isSearching
            searchQuery = ""
            searchSections = []
            searchEvents = []
            searchCorpusLoaded = false
            // Take focus so you can type a search immediately (next runloop,
            // once the reused panel is key again).
            DispatchQueue.main.async { searchFocused = true }
            let today = calendar.startOfDay(for: Date())
            let windowIsInitial = initialWindow(around: today).map {
                $0.start == agendaStart && $0.end == agendaEnd
            } == true
            // After a search the list sits deep in the result set; the bare
            // scroll-to-today fast path can't reliably climb back, so fall
            // through to a reload (the cold-open path that repositions cleanly).
            if !wasSearching, today == lastLoadedDay, windowIsInitial {
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

    /// Per-day "+": create a placeholder event on that day, then open it in
    /// Calendar.app to finish editing (Upcoming has no event editor of its
    /// own — by design). The short delay lets EventKit/Calendar index the
    /// just-saved event before the ical:// deep link tries to navigate to it.
    private func addEvent(on day: Date) {
        guard let id = calendarService.createEvent(on: day) else { return }
        AppDelegate.shared?.closePopup()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            CalendarAppOpener.showEvent(identifier: id)
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
            windowSectionsByDay = Dictionary(uniqueKeysWithValues: sections.map { ($0.day, $0) })
            // Dots for the whole window come free with this fetch.
            // Out-of-window extras are stale now (data changed); refill
            // below if the displayed month needs them.
            windowDotColors = EventGrouping.dotColors(events: agendaEvents, calendar: cal)
            extraDotColors = [:]
            extraSectionsByDay = [:]
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
            // Sections too, so the day-hover preview works outside the
            // agenda window.
            let gridSections = EventGrouping.sections(
                events: gridEvents, from: gridStart, to: gridEnd, calendar: cal
            )
            extraSectionsByDay.merge(
                Dictionary(uniqueKeysWithValues: gridSections.map { ($0.day, $0) })
            ) { _, new in new }
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

        switch AgendaWindow.edge(
            for: day,
            windowStart: windowStart,
            windowEnd: windowEnd,
            thresholdDays: Self.edgeThresholdDays,
            calendar: cal
        ) {
        case .past:
            // Prepending grows the content above the viewport, which would
            // visually teleport the list; re-anchor on the day that
            // triggered the load to keep the jump within a section.
            extendWindow(intoPast: true, reanchorOn: day)
        case .future:
            // Appending doesn't move existing content; no re-anchor needed.
            extendWindow(intoPast: false, reanchorOn: nil)
        case .none:
            break
        }
    }

    /// Grows the loaded window by `extendByDays`, fetching only the new
    /// slice and merging it into `windowEvents` — never the whole window,
    /// which gets seconds-slow after sustained scrolling.
    private func extendWindow(intoPast: Bool, reanchorOn anchor: Date?) {
        guard let windowStart = agendaStart, let windowEnd = agendaEnd else { return }
        let cal = calendar
        let hidden = config.hiddenCalendarIDs

        guard let slice = AgendaWindow.slice(
            intoPast: intoPast,
            windowStart: windowStart,
            windowEnd: windowEnd,
            extendByDays: Self.extendByDays,
            calendar: cal
        ) else { return }
        let newStart = slice.newStart
        let newEnd = slice.newEnd

        extendingWindow = true
        agendaStart = newStart
        agendaEnd = newEnd
        let generation = reloadGeneration

        Task {
            let delta = await calendarService.events(
                from: slice.fetchFrom,
                to: slice.fetchTo,
                hiddenCalendarIDs: hidden
            )
            // A full reload (EventKit change, settings, re-open) started
            // meanwhile and supersedes this slice.
            guard generation == reloadGeneration else { return }

            // Events spanning the old boundary arrive in both fetches.
            windowEvents = AgendaWindow.merge(existing: windowEvents, delta: delta)

            sections = EventGrouping.sections(
                events: windowEvents,
                from: newStart,
                to: newEnd,
                calendar: cal
            )
            windowSectionsByDay = Dictionary(uniqueKeysWithValues: sections.map { ($0.day, $0) })
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
