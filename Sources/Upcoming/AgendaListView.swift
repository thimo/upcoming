import AppKit
import SwiftUI
import UpcomingCore

/// Agenda list: starts at today, grouped per day. All-day events render as
/// pills in their calendar colour; timed events get a colour bar, time
/// range, title and location. Today's already-finished events are dimmed —
/// past *days* (once backward scroll lands) stay at full colour. The pill
/// and row visuals live in EventStyle.swift (shared with the hover
/// previews); this file owns the list's grouping, scrolling and hover.
///
/// Per-day section frames in the agenda scroll coordinate space; feeds
/// the grid-follows-list highlight.
private struct DayFramePreference: PreferenceKey {
    static var defaultValue: [Date: CGRect] = [:]
    static func reduce(value: inout [Date: CGRect], nextValue: () -> [Date: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Hover affordance for clickable agenda rows: the GhostButton hover
/// fill, extended slightly past the row bounds (negative padding, so
/// layout doesn't shift) plus the pointing-hand cursor.
private struct RowHover: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: interactiveCornerRadius)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                    .padding(.horizontal, -6)
                    .padding(.vertical, -3)
            )
            .onHover { isHovered = $0 }
            .pointingHandCursor()
    }
}

/// One-shot scroll command for the agenda list. The token makes every
/// request unique, so requesting the same day twice still fires onChange.
struct ScrollRequest: Equatable {
    let day: Date
    let animated: Bool
    private let token = UUID()

    init(day: Date, animated: Bool) {
        self.day = day
        self.animated = animated
    }
}

struct AgendaListView: View {
    let sections: [DaySection]
    let calendar: Calendar
    /// Reference clock for the dimmed-past-today cue; owned by the parent
    /// so rows re-evaluate on popup open even when the data didn't change.
    let now: Date
    /// ≥2 all-day events from one calendar on one day → one count pill.
    let combinePills: Bool
    /// calendarID → display name, for count-pill labels.
    let calendarNames: [String: String]
    /// Shown when there are no sections (varies for search vs. normal).
    var emptyMessage: String = "No upcoming events"
    /// Pending scroll command; cleared after scrolling. The parent arms
    /// its window-edge triggers on that clear.
    @Binding var scrollRequest: ScrollRequest?
    /// Reports day-sections scrolling into view, so the parent can extend
    /// the loaded window near its edges (infinite scroll).
    let onSectionAppear: (Date) -> Void
    /// Reports the day section currently at the top of the viewport, so
    /// the month grid can highlight it and follow along (grid-follows-list).
    let onTopDayChange: (Date) -> Void

    @Environment(\.colorScheme) private var colorScheme
    /// Count-pills the user clicked open, keyed day+calendarID. Cleared
    /// on popup open, so every visit starts compact.
    @State private var expandedGroups: Set<String> = []

    private var palette: PillPalette { PillPalette(colorScheme: colorScheme) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if sections.isEmpty {
                        Text(emptyMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                    ForEach(sections) { section in
                        daySection(section)
                            .id(section.day)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: DayFramePreference.self,
                                        value: [section.day: geo.frame(in: .named("agenda"))]
                                    )
                                }
                            )
                            .onAppear { onSectionAppear(section.day) }
                    }
                }
                .padding(.horizontal, 12)
            }
            // Vertical margins instead of LazyVStack padding: scrollTo's
            // .top anchor ignores stack padding (sections would land 12pt
            // too high) but does respect content margins. Horizontal is
            // plain padding — a trailing content margin would inset the
            // scroll indicator off the window edge.
            .contentMargins(.vertical, 12, for: .scrollContent)
            .coordinateSpace(name: "agenda")
            .onReceive(NotificationCenter.default.publisher(for: .popupDidOpen)) { _ in
                expandedGroups = []
            }
            .onPreferenceChange(DayFramePreference.self) { frames in
                // Topmost section still (partly) visible: the earliest day
                // whose bottom edge sits below the viewport top. Sections
                // above the viewport have negative maxY; the 10pt slop
                // keeps a 2px sliver from claiming the top spot. Only
                // LazyVStack-materialised sections report, which is
                // exactly the visible neighbourhood.
                let top = frames
                    .filter { $0.value.maxY > 10 }
                    .min(by: { $0.key < $1.key })?
                    .key
                if let top { onTopDayChange(top) }
            }
            .onChange(of: scrollRequest) {
                guard let request = scrollRequest else { return }
                // Empty days have no section; land on the next day that
                // has events (or the last one for targets past the window).
                if let destination = sections.first(where: { $0.day >= request.day })?.day
                    ?? sections.last?.day {
                    if request.animated {
                        withAnimation {
                            proxy.scrollTo(destination, anchor: .top)
                        }
                    } else {
                        proxy.scrollTo(destination, anchor: .top)
                    }
                }
                scrollRequest = nil
            }
        }
    }

    /// One entry in the pill flow: a regular pill, or a clicked-open
    /// count pill's underlying events rendered individually.
    private enum PillItem: Identifiable {
        case single(EventItem)
        case group(calendarID: String, events: [EventItem])

        var id: String {
            switch self {
            case .single(let event): return event.id
            case .group(let calendarID, _): return "group-\(calendarID)"
            }
        }
    }

    private func daySection(_ section: DaySection) -> some View {
        // Birthdays get Fantastical's treatment: a gift-icon row between
        // the pills and the timed events, not an all-day pill.
        let birthdays = section.allDay.filter(\.isBirthday)
        let items = pillItems(for: section)

        return VStack(alignment: .leading, spacing: 6) {
            DayHeaderView(day: section.day, calendar: calendar)
            if !items.isEmpty {
                FlowLayout(spacing: 3) {
                    ForEach(items) { item in
                        switch item {
                        case .single(let event):
                            AllDayPillView(event: event, palette: palette)
                                .onTapGesture { open(event) }
                                .pointingHandCursor()
                                .previewHover(.event(event))
                        case .group(let calendarID, let events):
                            groupPill(calendarID: calendarID, events: events, day: section.day)
                        }
                    }
                }
            }
            ForEach(birthdays) { event in
                BirthdayRowView(event: event)
                    .contentShape(Rectangle())
                    .onTapGesture { open(event) }
                    .modifier(RowHover())
                    .previewHover(.event(event))
            }
            ForEach(section.timed) { event in
                EventRowView(
                    event: event, day: section.day,
                    now: now, calendar: calendar, palette: palette
                )
                .contentShape(Rectangle())
                .onTapGesture { open(event) }
                .modifier(RowHover())
                .previewHover(.event(event))
            }
        }
    }

    /// Clusters the day's pills per calendar (first-appearance order).
    /// ≥2 pills from one calendar collapse into a count pill unless the
    /// user clicked that group open. Single pills are never touched.
    private func pillItems(for section: DaySection) -> [PillItem] {
        let pills = section.allDay.filter { !$0.isBirthday }
        guard combinePills else { return pills.map { .single($0) } }

        var order: [String] = []
        var byCalendar: [String: [EventItem]] = [:]
        for event in pills {
            if byCalendar[event.calendarID] == nil {
                order.append(event.calendarID)
            }
            byCalendar[event.calendarID, default: []].append(event)
        }

        return order.flatMap { calendarID -> [PillItem] in
            let events = byCalendar[calendarID] ?? []
            if events.count >= 2, !expandedGroups.contains(groupKey(section.day, calendarID)) {
                return [.group(calendarID: calendarID, events: events)]
            }
            return events.map { .single($0) }
        }
    }

    private func groupKey(_ day: Date, _ calendarID: String) -> String {
        "\(day.timeIntervalSinceReferenceDate)-\(calendarID)"
    }

    /// Collapsed stand-in for a calendar's multiple all-day events:
    /// "<calendar> · <count>" in the calendar colour. Click expands the
    /// group for this day; hover shows the hidden events in a popover.
    private func groupPill(calendarID: String, events: [EventItem], day: Date) -> some View {
        let name = calendarNames[calendarID] ?? "All-day"
        let key = groupKey(day, calendarID)
        let color = events.first?.color ?? CalendarColor(red: 0.5, green: 0.5, blue: 0.5)
        return Text("\(name) · \(events.count)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.pillTextColor(color))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(palette.pillFillColor(color))
            )
            .onTapGesture { expandedGroups.insert(key) }
            .pointingHandCursor()
            .previewHover(.group(events: events))
    }

    /// Click on an event = show it in Calendar.app (read-only app; edits
    /// happen there). Close the popup so Calendar isn't buried under it.
    private func open(_ event: EventItem) {
        CalendarAppOpener.show(event)
        AppDelegate.shared?.closePopup()
    }
}
