import SwiftUI
import UpcomingCore

/// Hover preview for a collapsed all-day count pill ("<calendar> · N"):
/// each hidden event rendered exactly like the single-event popover,
/// stacked below each other.
struct GroupPopoverView: View {
    let events: [EventItem]
    let calendar: Calendar

    /// Same width as the single-event popover, so the stacked cards match.
    static let contentWidth: CGFloat = EventPopoverView.contentWidth

    var body: some View {
        VStack(spacing: 14) {
            ForEach(events) { event in
                EventPopoverView(event: event, calendar: calendar)
            }
        }
    }
}
