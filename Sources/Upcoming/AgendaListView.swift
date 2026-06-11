import AppKit
import SwiftUI
import UpcomingCore

/// Agenda list: starts at today, grouped per day. All-day events render as
/// pills in their calendar colour; timed events get a colour dot, time
/// range, title and location. Today's already-finished events are dimmed —
/// past *days* (once backward scroll lands) stay at full colour.
struct AgendaListView: View {
    let sections: [DaySection]
    let calendar: Calendar
    /// Day to scroll to (set by a month-grid click); cleared after scrolling.
    @Binding var scrollTarget: Date?

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
                    }
                }
                .padding(12)
            }
            .onChange(of: scrollTarget) {
                guard let target = scrollTarget else { return }
                scrollTarget = nil
                // Empty days have no section; land on the next day that
                // has events (or the last one for clicks past the window).
                guard let destination = sections.first(where: { $0.day >= target })?.day
                    ?? sections.last?.day else { return }
                withAnimation {
                    proxy.scrollTo(destination, anchor: .top)
                }
            }
        }
    }

    private func daySection(_ section: DaySection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            dayHeader(section.day)
            if !section.allDay.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(section.allDay) { event in
                        allDayPill(event)
                    }
                }
            }
            ForEach(section.timed) { event in
                timedRow(event, day: section.day)
            }
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
        let isPastToday = calendar.isDateInToday(day) && event.end < Date()

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
                    openVideoCall(url)
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

    /// Teams join links open straight in the Teams app when something
    /// handles the msteams: scheme; everything else (and Teams-less Macs)
    /// goes through the default browser.
    private func openVideoCall(_ url: URL) {
        if let appURL = VideoCallDetector.teamsAppURL(for: url),
           NSWorkspace.shared.urlForApplication(toOpen: appURL) != nil {
            NSWorkspace.shared.open(appURL)
        } else {
            NSWorkspace.shared.open(url)
        }
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
    var spacing: CGFloat = 6
    /// Vertical gap between wrapped rows; tighter than the in-row gap.
    var rowSpacing: CGFloat = 4

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
