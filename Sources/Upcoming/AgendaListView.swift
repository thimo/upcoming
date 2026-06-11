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

    var body: some View {
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
                }
            }
            .padding(12)
        }
    }

    private func daySection(_ section: DaySection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            dayHeader(section.day)
            if !section.allDay.isEmpty {
                // Wrapping flow layout can come later; pills in a row.
                HStack(spacing: 6) {
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
        Text(event.title)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color(calendarColor: event.color))
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
                    NSWorkspace.shared.open(url)
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
