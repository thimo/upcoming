import AppKit
import SwiftUI
import UpcomingCore

/// Agenda list: starts at today, grouped per day. All-day events render as
/// pills in their calendar colour; timed events get a colour dot, time
/// range, title and location. Today's already-finished events are dimmed —
/// past *days* (once backward scroll lands) stay at full colour.
/// Bounds anchors of the collapsed count-pills, keyed by group key;
/// the hover tip is drawn at the scroll-view level from these so it
/// renders above every row (an in-pill overlay loses the z-order fight
/// with later siblings) and can hang below the pill.
private struct TipAnchorPreference: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

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
    /// Count-pill currently under the cursor (group key + tip text).
    @State private var hoveredTip: (key: String, text: String)?

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
                hoveredTip = nil
            }
            // Hover tip for count-pills, drawn at this level so it sits
            // above all rows and hangs below the hovered pill.
            .overlayPreferenceValue(TipAnchorPreference.self) { anchors in
                GeometryReader { proxy in
                    if let tip = hoveredTip, let anchor = anchors[tip.key] {
                        let rect = proxy[anchor]
                        HoverTipLabel(text: tip.text)
                            .offset(x: rect.minX, y: rect.maxY + 4)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.12), value: hoveredTip?.key)
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
            dayHeader(section.day)
            if !items.isEmpty {
                FlowLayout(spacing: 3) {
                    ForEach(items) { item in
                        switch item {
                        case .single(let event):
                            allDayPill(event)
                        case .group(let calendarID, let events):
                            groupPill(calendarID: calendarID, events: events, day: section.day)
                        }
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
    /// group for this day; hover previews the titles instantly.
    private func groupPill(calendarID: String, events: [EventItem], day: Date) -> some View {
        let name = calendarNames[calendarID] ?? "All-day"
        let key = groupKey(day, calendarID)
        let color = events.first?.color ?? CalendarColor(red: 0.5, green: 0.5, blue: 0.5)
        return Text("\(name) · \(events.count)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(pillTextColor(color))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                // Capsule for the normal single-line pill; the rounded
                // rect keeps corners sane when a long title wraps.
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(pillFillColor(color))
            )
            .onTapGesture {
                hoveredTip = nil
                expandedGroups.insert(key)
            }
            .pointingHandCursor()
            .anchorPreference(key: TipAnchorPreference.self, value: .bounds) { [key: $0] }
            .onHover { hovering in
                if hovering {
                    hoveredTip = (key, events.map(\.title).joined(separator: "\n"))
                } else if hoveredTip?.key == key {
                    hoveredTip = nil
                }
            }
    }

    private func birthdayRow(_ event: EventItem) -> some View {
        // Mirrors timedRow's leading column (3pt bar + 5pt gap) so the
        // title lines up with the timed titles below it; the gift glyph
        // overhangs its narrow frame a touch, which the hover fill
        // (negative padding) comfortably covers.
        HStack(spacing: 5) {
            Image(systemName: "gift.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red)
                .frame(width: 3)
            Text(event.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture { open(event) }
        .modifier(RowHover())
    }

    /// Click on an event = show it in Calendar.app (read-only app; edits
    /// happen there). Close the popup so Calendar isn't buried under it.
    private func open(_ event: EventItem) {
        CalendarAppOpener.show(event)
        AppDelegate.shared?.closePopup()
    }

    private func dayHeader(_ day: Date) -> some View {
        // Apple Calendar register: today's label in red, everything else
        // quiet grey, with a natural date ("12 June 2026") instead of the
        // Fantastical-era 12/06/2026.
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("d MMMM y")

        let isToday = calendar.isDateInToday(day)
        let name: String
        if isToday {
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
                .foregroundStyle(isToday ? Color.todayRed : .secondary)
            Text(formatter.string(from: day))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func allDayPill(_ event: EventItem) -> some View {
        // Full title, never truncated: pills flow and wrap via FlowLayout;
        // a title wider than the panel wraps inside its own pill.
        pillLabel(event.title, isRecurring: event.isRecurring)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(pillTextColor(event.color))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                ZStack {
                    let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
                    if event.isTentative {
                        // Maybe: hatch in the calendar tint (Calendar's
                        // tentative treatment).
                        shape.fill(tentativeFieldColor(event.color))
                        DiagonalStripes()
                            .fill(tentativeStripeColor(event.color))
                            .clipShape(shape)
                    } else if event.isPendingInvitation {
                        // Unanswered invitation: grey hatch instead of the
                        // tint (Calendar's treatment); text keeps colour.
                        shape.fill(Color.primary.opacity(0.04))
                        DiagonalStripes()
                            .fill(Color.primary.opacity(0.045))
                            .clipShape(shape)
                    } else {
                        shape.fill(pillFillColor(event.color))
                    }
                }
            )
            .onTapGesture { open(event) }
            .pointingHandCursor()
    }

    /// Apple Calendar's recurrence glyph: two stacked horizontal arrows
    /// (verified against a zoomed Calendar screenshot 2026-06-12).
    static let recurrenceSymbol = "repeat"

    /// Pill title with Apple Calendar's inline ⟳ for recurring events;
    /// concatenated Text so the marker flows with the (wrappable) title.
    private func pillLabel(_ title: String, isRecurring: Bool) -> Text {
        guard isRecurring else { return Text(title) }
        return Text(title)
            + Text(" ")
            + Text(Image(systemName: Self.recurrenceSymbol))
                .font(.system(size: 8, weight: .bold))
    }

    /// Apple Calendar pill colours, measured per-pixel from native
    /// screen captures (2026-06-12). The display renders in Display P3
    /// and Calendar's values only behave consistently as P3 components,
    /// so measured calendars get their exact captured values pinned
    /// here (light mode); everything else falls back to the fitted HSB
    /// transform below. Keyed by the calendar's EventKit sRGB colour.
    private struct MeasuredPill {
        let base: CalendarColor
        // Component tuples on a 0–255 scale, in Display P3.
        let fillLight: (Double, Double, Double)
        let textLight: (Double, Double, Double)
        let fillDark: (Double, Double, Double)
        let textDark: (Double, Double, Double)

        init(base: (Double, Double, Double),
             fillLight: (Double, Double, Double), textLight: (Double, Double, Double),
             fillDark: (Double, Double, Double), textDark: (Double, Double, Double)) {
            self.base = CalendarColor(
                red: base.0 / 255, green: base.1 / 255, blue: base.2 / 255)
            self.fillLight = fillLight
            self.textLight = textLight
            self.fillDark = fillDark
            self.textDark = textDark
        }
    }

    private static let measuredPills: [MeasuredPill] = [
        // Blue (Thimo Werk)
        MeasuredPill(base: (0, 136, 255),
                     fillLight: (215, 238, 255), textLight: (0, 68, 127),
                     fillDark: (13, 53, 83), textDark: (63, 170, 255)),
        // Brown (Digital Team / Calendar)
        MeasuredPill(base: (172, 127, 94),
                     fillLight: (243, 237, 232), textLight: (86, 63, 47),
                     fillDark: (56, 44, 33), textDark: (183, 138, 102)),
        // Yellow (Thimo Prive)
        MeasuredPill(base: (255, 204, 0),
                     fillLight: (251, 244, 209), textLight: (127, 102, 0),
                     fillDark: (77, 66, 6), textDark: (255, 214, 0)),
    ]

    private func measuredEntry(for color: CalendarColor) -> MeasuredPill? {
        Self.measuredPills.first {
            abs($0.base.red - color.red) + abs($0.base.green - color.green)
                + abs($0.base.blue - color.blue) < 0.05
        }
    }

    private static func p3(_ c: (Double, Double, Double)) -> Color {
        Color(.displayP3, red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255)
    }

    private static func color(_ c: (Double, Double, Double), p3: Bool) -> Color {
        p3 ? Self.p3(c) : Color(red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255)
    }

    private static func mix(
        _ a: (Double, Double, Double), _ b: (Double, Double, Double), _ f: Double
    ) -> (Double, Double, Double) {
        (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f, a.2 + (b.2 - a.2) * f)
    }

    /// HSB → RGB components on a 0–255 scale (for the fallback path,
    /// so the tentative tints can be derived in component space).
    private static func rgb(
        hue: Double, saturation: Double, brightness: Double
    ) -> (Double, Double, Double) {
        let h = (hue - hue.rounded(.down)) * 6
        let i = Int(h) % 6
        let f = h - h.rounded(.down)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * f)
        let t = brightness * (1 - saturation * (1 - f))
        let rgb: (Double, Double, Double)
        switch i {
        case 0: rgb = (brightness, t, p)
        case 1: rgb = (q, brightness, p)
        case 2: rgb = (p, brightness, t)
        case 3: rgb = (p, q, brightness)
        case 4: rgb = (t, p, brightness)
        default: rgb = (brightness, p, q)
        }
        return (rgb.0 * 255, rgb.1 * 255, rgb.2 * 255)
    }

    /// Fallback for calendars without a measured entry: keep the hue,
    /// transform saturation/brightness in HSB (fitted to the captures).
    /// Colours are OPAQUE on purpose — alpha tints sink into the panel's
    /// grey vibrancy material and can never reach Apple's lightness.
    /// Dark mode values are untuned estimates (no reference measured).
    private func pillTextColor(_ color: CalendarColor) -> Color {
        if let m = measuredEntry(for: color) {
            return Self.p3(colorScheme == .dark ? m.textDark : m.textLight)
        }
        let (h, s, b) = color.hsb
        if colorScheme == .dark {
            return Color(hue: h, saturation: s * 0.85, brightness: min(1, b * 1.1))
        }
        return Color(hue: h, saturation: min(1, s * 1.3), brightness: b * 0.5)
    }

    /// Pill fill as components plus whether they are Display P3
    /// (measured) or sRGB (fallback); the tentative hatch derives its
    /// tints from these in the same space.
    private func pillFillComponents(_ color: CalendarColor) -> (c: (Double, Double, Double), p3: Bool) {
        if let m = measuredEntry(for: color) {
            return (colorScheme == .dark ? m.fillDark : m.fillLight, true)
        }
        let (h, s, b) = color.hsb
        let c = colorScheme == .dark
            ? Self.rgb(hue: h, saturation: s * 0.85, brightness: b * 0.33)
            : Self.rgb(hue: h, saturation: s * 0.22, brightness: 1 - (1 - b) * 0.33)
        return (c, false)
    }

    private func pillFillColor(_ color: CalendarColor) -> Color {
        let (c, p3) = pillFillComponents(color)
        return Self.color(c, p3: p3)
    }

    // MARK: Tentative (Maybe) hatch — measured from Calendar 2026-06-12:
    // light: field = fill 33% toward white (exact for the pinned brown),
    // stripe = fill 9% toward the base colour; dark: field/stripe = fill
    // 13%/29% toward black; title keeps colour (light: pill text, dark:
    // the plain calendar colour, as measured).

    private func tentativeFieldColor(_ color: CalendarColor) -> Color {
        let (c, p3) = pillFillComponents(color)
        if colorScheme == .dark {
            return Self.color(Self.mix(c, (0, 0, 0), 0.13), p3: p3)
        }
        return Self.color(Self.mix(c, (255, 255, 255), 0.33), p3: p3)
    }

    private func tentativeStripeColor(_ color: CalendarColor) -> Color {
        let (c, p3) = pillFillComponents(color)
        if colorScheme == .dark {
            return Self.color(Self.mix(c, (0, 0, 0), 0.29), p3: p3)
        }
        let base = (color.red * 255, color.green * 255, color.blue * 255)
        return Self.color(Self.mix(c, base, 0.09), p3: p3)
    }

    private func titleColor(for event: EventItem) -> Color {
        if event.isPendingInvitation { return .secondary }
        if event.isTentative {
            return colorScheme == .dark
                ? Color(calendarColor: event.color) : pillTextColor(event.color)
        }
        return .primary
    }

    private func timedRow(_ event: EventItem, day: Date) -> some View {
        // Dim only today's already-finished events ("already happened"
        // cue within today) — not events on past days.
        let isPastToday = calendar.isDateInToday(day) && event.end < now

        return HStack(alignment: .top, spacing: 5) {
            // Calendar-style colour bar instead of a dot, with Calendar's
            // tight bar-to-text gap.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(calendarColor: event.color))
                .frame(width: 3)
                .padding(.vertical, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(timeString(event.start)) – \(timeString(event.end))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(event.title)
                    .font(.system(size: 12, weight: .medium))
                    // Pending → grey, tentative → calendar-coloured,
                    // like the text on Calendar's hatched blocks.
                    .foregroundStyle(titleColor(for: event))
                    .lineLimit(1)
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // Both trailing icons share the time line's height so they
            // centre on it together (the row HStack is top-aligned).
            if event.isRecurring {
                Image(systemName: Self.recurrenceSymbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(height: 15)
            }
            if let url = event.videoCallURL {
                Button {
                    VideoCallOpener.open(url)
                } label: {
                    // Outlined like Apple Calendar's video marker, not
                    // the louder filled variant.
                    Image(systemName: "video")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                        .frame(height: 15)
                }
                .buttonStyle(.borderless)
                .help("Join video call")
            }
        }
        .background(
            // Hatched rows like Apple Calendar: tentative (Maybe) in the
            // calendar tint, unanswered invitations in neutral grey.
            // Negative padding mirrors RowHover so both fills align.
            Group {
                if event.isTentative {
                    let shape = RoundedRectangle(cornerRadius: interactiveCornerRadius)
                    ZStack {
                        shape.fill(tentativeFieldColor(event.color))
                        DiagonalStripes()
                            .fill(tentativeStripeColor(event.color))
                            .clipShape(shape)
                    }
                    .padding(.horizontal, -6)
                    .padding(.vertical, -3)
                } else if event.isPendingInvitation {
                    // Measured from Calendar: field ~4% grey, stripes
                    // another ~4% on top — low contrast, wide stripes.
                    let shape = RoundedRectangle(cornerRadius: interactiveCornerRadius)
                    ZStack {
                        shape.fill(Color.primary.opacity(0.04))
                        DiagonalStripes()
                            .fill(Color.primary.opacity(0.045))
                            .clipShape(shape)
                    }
                    .padding(.horizontal, -6)
                    .padding(.vertical, -3)
                }
            }
        )
        .opacity(isPastToday ? 0.45 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture { open(event) }
        .modifier(RowHover())
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

/// 45° hatching for unanswered invitations (Apple Calendar's pending
/// treatment). Geometry measured from a Calendar screenshot @2x:
/// stripe and gap each ~4.5pt.
private struct DiagonalStripes: Shape {
    var lineWidth: CGFloat = 4.5
    var spacing: CGFloat = 4.5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = lineWidth + spacing
        // Start one height early so the slanted lines cover the left edge.
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += step
        }
        return path.strokedPath(StrokeStyle(lineWidth: lineWidth))
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
