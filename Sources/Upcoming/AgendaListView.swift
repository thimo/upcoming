import AppKit
import SwiftUI
import UpcomingCore

/// Agenda list: starts at today, grouped per day. All-day events render as
/// pills in their calendar colour; timed events get a colour dot, time
/// range, title and location. Today's already-finished events are dimmed —
/// past *days* (once backward scroll lands) stay at full colour.
/// Per-day section frames in the agenda scroll coordinate space; feeds
/// the grid-follows-list highlight.
private struct DayFramePreference: PreferenceKey {
    static var defaultValue: [Date: CGRect] = [:]
    static func reduce(value: inout [Date: CGRect], nextValue: () -> [Date: CGRect]) {
        value.merge(nextValue()) { _, new in new }
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
    /// Pending scroll command; cleared after scrolling. The parent arms
    /// its window-edge triggers on that clear.
    @Binding var scrollRequest: ScrollRequest?
    /// Reports day-sections scrolling into view, so the parent can extend
    /// the loaded window near its edges (infinite scroll).
    let onSectionAppear: (Date) -> Void
    /// Reports the day section currently at the top of the viewport, so
    /// the month grid can highlight it and follow along (grid-follows-list).
    let onTopDayChange: (Date) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if sections.isEmpty {
                        Text("No upcoming events")
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
            }
            // Margins instead of LazyVStack padding: scrollTo's .top
            // anchor ignores stack padding (sections would land 12pt too
            // high) but does respect content margins.
            .contentMargins(12, for: .scrollContent)
            .coordinateSpace(name: "agenda")
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

    private func daySection(_ section: DaySection) -> some View {
        // Birthdays get Fantastical's treatment: a gift-icon row between
        // the pills and the timed events, not an all-day pill.
        let pills = section.allDay.filter { !$0.isBirthday }
        let birthdays = section.allDay.filter(\.isBirthday)

        return VStack(alignment: .leading, spacing: 6) {
            dayHeader(section.day)
            if !pills.isEmpty {
                FlowLayout(spacing: 3) {
                    ForEach(pills) { event in
                        allDayPill(event)
                    }
                }
            }
            ForEach(birthdays) { event in
                birthdayRow(event)
            }
            ForEach(section.timed) { event in
                timedRow(event, day: section.day)
            }
        }
    }

    private func birthdayRow(_ event: EventItem) -> some View {
        // Mirrors timedRow's leading column (8pt dot + 8pt gap) so the
        // title lines up with the timed titles below it.
        HStack(spacing: 8) {
            Image(systemName: "gift.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red)
                .frame(width: 8)
            Text(event.title)
                .font(.system(size: 12))
                .lineLimit(1)
        }
    }

    private func dayHeader(_ day: Date) -> some View {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "dd/MM/yyyy"

        let name: String
        if calendar.isDateInToday(day) {
            name = "TODAY"
        } else if calendar.isDateInTomorrow(day) {
            name = "TOMORROW"
        } else {
            let weekday = DateFormatter()
            weekday.calendar = calendar
            weekday.dateFormat = "EEEE"
            name = weekday.string(from: day).uppercased()
        }

        return HStack(spacing: 5) {
            Text(name)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(calendar.isDateInToday(day) ? Color.accentColor : .primary)
            Text(formatter.string(from: day))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func allDayPill(_ event: EventItem) -> some View {
        // Full title, never truncated: pills flow and wrap via FlowLayout;
        // a title wider than the panel wraps inside its own pill.
        Text(event.title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(calendarColor: event.color))
            )
    }

    private func timedRow(_ event: EventItem, day: Date) -> some View {
        // Dim only today's already-finished events ("already happened"
        // cue within today) — not events on past days.
        let isPastToday = calendar.isDateInToday(day) && event.end < now

        return HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color(calendarColor: event.color))
                .frame(width: 8, height: 8)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(timeString(event.start)) – \(timeString(event.end))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(event.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let url = event.videoCallURL {
                Button {
                    VideoCallOpener.open(url)
                } label: {
                    Image(systemName: "video.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.borderless)
                .help("Join video call")
            }
        }
        .opacity(isPastToday ? 0.45 : 1.0)
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

/// Left-aligned flow: items keep their natural size and wrap to the next
/// line when the row is full (all-day pills).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 3
    /// Vertical gap between wrapped rows; can sit tighter than (or equal
    /// to) the in-row gap.
    var rowSpacing: CGFloat = 3

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(in: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, arrangement.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(in maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            // Proposing maxWidth lets an over-wide pill wrap internally.
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x - spacing)
        }
        return (CGSize(width: totalWidth, height: y + rowHeight), frames)
    }
}
