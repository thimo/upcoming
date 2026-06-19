import SwiftUI
import UpcomingCore

/// Shared Apple-Calendar event styling: pill/row colours (measured
/// per-pixel from native captures), the tentative/pending hatch, and the
/// leaf views (`AllDayPillView`, `BirthdayRowView`, `EventRowView`) used by
/// both the agenda list and the hover previews. Keeping it in one place
/// stops the list and the previews from drifting apart.
enum EventStyle {
    /// Apple Calendar's recurrence glyph: a single ⟳ (verified against a
    /// zoomed Calendar screenshot 2026-06-12).
    static let recurrenceSymbol = "repeat"

    /// Pill/title with Apple Calendar's inline ⟳ for recurring events;
    /// concatenated Text so the marker flows with the (wrappable) title.
    static func pillLabel(_ title: String, isRecurring: Bool) -> Text {
        guard isRecurring else { return Text(title) }
        return Text(title)
            + Text(" ")
            + Text(Image(systemName: recurrenceSymbol))
                .font(.system(size: 8, weight: .bold))
    }
}

/// Apple Calendar pill colours, measured per-pixel from native screen
/// captures (2026-06-12). The display renders in Display P3 and Calendar's
/// values only behave consistently as P3 components, so measured calendars
/// get their exact captured values pinned here (light mode); everything
/// else falls back to the fitted HSB transform. Keyed by the calendar's
/// EventKit sRGB colour. Stateless apart from the colour scheme.
struct PillPalette {
    let colorScheme: ColorScheme

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

    // NB: don't re-tune these from a single screenshot. A screen capture's
    // colour profile (display-dependent, and P3→sRGB conversion varies by
    // capture) can shift the darks by ~40 levels — two captures of the
    // *same* Calendar events disagreed by that much (2026-06-19). These
    // values were verified against a normal full-screen capture and match
    // Calendar pixel-for-pixel; trust them over any one-off comparison.
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

    /// HSB → RGB components on a 0–255 scale (fallback path, so the
    /// tentative tints can be derived in component space).
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

    /// Pill text colour: measured value when pinned, otherwise the fitted
    /// HSB transform. Colours are OPAQUE on purpose — alpha tints sink into
    /// the panel's grey vibrancy and can never reach Apple's lightness.
    func pillTextColor(_ color: CalendarColor) -> Color {
        if let m = measuredEntry(for: color) {
            return Self.p3(colorScheme == .dark ? m.textDark : m.textLight)
        }
        let (h, s, b) = color.hsb
        if colorScheme == .dark {
            return Color(hue: h, saturation: s * 0.85, brightness: min(1, b * 1.1))
        }
        return Color(hue: h, saturation: min(1, s * 1.3), brightness: b * 0.5)
    }

    /// Pill fill as components plus whether they are Display P3 (measured)
    /// or sRGB (fallback); the tentative hatch derives its tints from these
    /// in the same space.
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

    func pillFillColor(_ color: CalendarColor) -> Color {
        let (c, p3) = pillFillComponents(color)
        return Self.color(c, p3: p3)
    }

    // MARK: Tentative (Maybe) hatch — measured from Calendar 2026-06-12:
    // light: field = fill 33% toward white, stripe = fill 9% toward base;
    // dark: field/stripe = fill 13%/29% toward black; title keeps colour.

    func tentativeFieldColor(_ color: CalendarColor) -> Color {
        let (c, p3) = pillFillComponents(color)
        if colorScheme == .dark {
            return Self.color(Self.mix(c, (0, 0, 0), 0.13), p3: p3)
        }
        return Self.color(Self.mix(c, (255, 255, 255), 0.33), p3: p3)
    }

    func tentativeStripeColor(_ color: CalendarColor) -> Color {
        let (c, p3) = pillFillComponents(color)
        if colorScheme == .dark {
            return Self.color(Self.mix(c, (0, 0, 0), 0.29), p3: p3)
        }
        let base = (color.red * 255, color.green * 255, color.blue * 255)
        return Self.color(Self.mix(c, base, 0.09), p3: p3)
    }

    /// Title colour for a timed row: grey when pending, calendar-tinted
    /// when tentative (matching Calendar's hatched-block text), else primary.
    func titleColor(for event: EventItem) -> Color {
        if event.isPendingInvitation { return .secondary }
        if event.isTentative {
            return colorScheme == .dark
                ? Color(calendarColor: event.color) : pillTextColor(event.color)
        }
        return .primary
    }
}

/// One all-day event as a coloured pill (Apple Calendar styling). Pure
/// visual; tap/hover affordances are the caller's to add.
struct AllDayPillView: View {
    let event: EventItem
    let palette: PillPalette

    var body: some View {
        // Full title, never truncated: pills flow and wrap; a title wider
        // than the panel wraps inside its own pill.
        EventStyle.pillLabel(event.title, isRecurring: event.isRecurring)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.pillTextColor(event.color))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                ZStack {
                    let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
                    if event.isTentative {
                        shape.fill(palette.tentativeFieldColor(event.color))
                        DiagonalStripes()
                            .fill(palette.tentativeStripeColor(event.color))
                            .clipShape(shape)
                    } else if event.isPendingInvitation {
                        shape.fill(Color.primary.opacity(0.04))
                        DiagonalStripes()
                            .fill(Color.primary.opacity(0.045))
                            .clipShape(shape)
                    } else {
                        shape.fill(palette.pillFillColor(event.color))
                    }
                }
            )
    }
}

/// A birthday as Fantastical's gift-icon row (not an all-day pill). Pure
/// visual; the leading column mirrors `EventRowView`'s 3pt bar + 5pt gap so
/// the title lines up with the timed titles.
struct BirthdayRowView: View {
    let event: EventItem

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "gift.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red)
                .frame(width: 3)
            Text(event.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
    }
}

/// One timed event: colour bar, time range, title, optional location, and
/// trailing recurrence / video markers (Apple Calendar styling). Used by
/// the agenda list and the day-hover preview; the list adds tap/hover.
struct EventRowView: View {
    let event: EventItem
    let day: Date
    let now: Date
    let calendar: Calendar
    let palette: PillPalette

    var body: some View {
        // Dim only today's already-finished events ("already happened"),
        // not events on past days.
        let isPastToday = calendar.isDateInToday(day) && event.end < now

        return HStack(alignment: .top, spacing: 5) {
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
                    .foregroundStyle(palette.titleColor(for: event))
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
                Image(systemName: EventStyle.recurrenceSymbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(height: 15)
            }
            if let url = event.videoCallURL {
                Button {
                    VideoCallOpener.open(url)
                } label: {
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
            // Negative padding mirrors the list's RowHover so fills align.
            Group {
                if event.isTentative {
                    let shape = RoundedRectangle(cornerRadius: interactiveCornerRadius)
                    ZStack {
                        shape.fill(palette.tentativeFieldColor(event.color))
                        DiagonalStripes()
                            .fill(palette.tentativeStripeColor(event.color))
                            .clipShape(shape)
                    }
                    .padding(.horizontal, -6)
                    .padding(.vertical, -3)
                } else if event.isPendingInvitation {
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
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

/// 45° hatching for tentative / unanswered invitations (Apple Calendar's
/// treatment). Geometry measured from a Calendar screenshot @2x: stripe
/// and gap each ~4.5pt.
struct DiagonalStripes: Shape {
    var lineWidth: CGFloat = 4.5
    var spacing: CGFloat = 4.5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = lineWidth + spacing
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
struct FlowLayout: Layout {
    var spacing: CGFloat = 3
    /// Vertical gap between wrapped rows.
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

/// Which side of the popup the hover preview sits on; drives the arrow
/// edge and positioning.
enum PanelSide {
    case left   // card to the left of the popup, arrow on its right edge
    case right  // card to the right of the popup, arrow on its left edge
}

enum PopoverMetrics {
    static let arrowWidth: CGFloat = 8
    static let arrowHeight: CGFloat = 14
    static let cornerRadius: CGFloat = 12
    /// Gap between the popup edge and the arrow tip.
    static let gap: CGFloat = 10
}

extension View {
    /// Wraps the preview content as a single material-filled card with an
    /// arrow poking toward the popup (Uncommitted's HoverDetail pattern).
    /// No SwiftUI drop shadow — the host panel draws a native window shadow
    /// that follows this combined shape. `arrowOffset` is the arrow's top
    /// edge measured from the card top (set by the controller so the arrow
    /// points at the hovered row).
    func popoverCard(width: CGFloat, arrowSide: PanelSide, arrowOffset: CGFloat) -> some View {
        let shape = CardWithArrowShape(
            arrowSide: arrowSide,
            cornerRadius: PopoverMetrics.cornerRadius,
            arrowWidth: PopoverMetrics.arrowWidth,
            arrowHeight: PopoverMetrics.arrowHeight,
            arrowTopOffset: arrowOffset
        )
        return frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .frame(width: width)
            // Reserve the arrow strip on the side facing the popup; the
            // shape draws the card in the rest and the arrow into the strip.
            .padding(.leading, arrowSide == .right ? PopoverMetrics.arrowWidth : 0)
            .padding(.trailing, arrowSide == .left ? PopoverMetrics.arrowWidth : 0)
            .background(shape.fill(Material.regular))
            .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}

/// A rounded card with an arrow poking out of one edge, as a single path
/// so the material fills as one unit and the stroke/shadow wrap the whole
/// outline (no seam where the arrow meets the card). Ported from
/// Uncommitted's HoverDetailWindow.
struct CardWithArrowShape: Shape {
    let arrowSide: PanelSide
    let cornerRadius: CGFloat
    let arrowWidth: CGFloat
    let arrowHeight: CGFloat
    let arrowTopOffset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = cornerRadius

        let cardRect: CGRect
        switch arrowSide {
        case .right:
            cardRect = CGRect(x: rect.minX + arrowWidth, y: rect.minY,
                              width: rect.width - arrowWidth, height: rect.height)
        case .left:
            cardRect = CGRect(x: rect.minX, y: rect.minY,
                              width: rect.width - arrowWidth, height: rect.height)
        }

        let arrowTopY = rect.minY + arrowTopOffset
        let arrowBottomY = arrowTopY + arrowHeight
        let arrowTipY = arrowTopY + arrowHeight / 2

        switch arrowSide {
        case .right:
            // Arrow on the card's LEFT edge, pointing left at the popup.
            path.move(to: CGPoint(x: cardRect.minX + r, y: cardRect.minY))
            path.addLine(to: CGPoint(x: cardRect.maxX - r, y: cardRect.minY))
            path.addQuadCurve(to: CGPoint(x: cardRect.maxX, y: cardRect.minY + r),
                              control: CGPoint(x: cardRect.maxX, y: cardRect.minY))
            path.addLine(to: CGPoint(x: cardRect.maxX, y: cardRect.maxY - r))
            path.addQuadCurve(to: CGPoint(x: cardRect.maxX - r, y: cardRect.maxY),
                              control: CGPoint(x: cardRect.maxX, y: cardRect.maxY))
            path.addLine(to: CGPoint(x: cardRect.minX + r, y: cardRect.maxY))
            path.addQuadCurve(to: CGPoint(x: cardRect.minX, y: cardRect.maxY - r),
                              control: CGPoint(x: cardRect.minX, y: cardRect.maxY))
            path.addLine(to: CGPoint(x: cardRect.minX, y: arrowBottomY))
            path.addLine(to: CGPoint(x: rect.minX, y: arrowTipY))
            path.addLine(to: CGPoint(x: cardRect.minX, y: arrowTopY))
            path.addLine(to: CGPoint(x: cardRect.minX, y: cardRect.minY + r))
            path.addQuadCurve(to: CGPoint(x: cardRect.minX + r, y: cardRect.minY),
                              control: CGPoint(x: cardRect.minX, y: cardRect.minY))

        case .left:
            // Arrow on the card's RIGHT edge, pointing right at the popup.
            path.move(to: CGPoint(x: cardRect.minX + r, y: cardRect.minY))
            path.addLine(to: CGPoint(x: cardRect.maxX - r, y: cardRect.minY))
            path.addQuadCurve(to: CGPoint(x: cardRect.maxX, y: cardRect.minY + r),
                              control: CGPoint(x: cardRect.maxX, y: cardRect.minY))
            path.addLine(to: CGPoint(x: cardRect.maxX, y: arrowTopY))
            path.addLine(to: CGPoint(x: rect.maxX, y: arrowTipY))
            path.addLine(to: CGPoint(x: cardRect.maxX, y: arrowBottomY))
            path.addLine(to: CGPoint(x: cardRect.maxX, y: cardRect.maxY - r))
            path.addQuadCurve(to: CGPoint(x: cardRect.maxX - r, y: cardRect.maxY),
                              control: CGPoint(x: cardRect.maxX, y: cardRect.maxY))
            path.addLine(to: CGPoint(x: cardRect.minX + r, y: cardRect.maxY))
            path.addQuadCurve(to: CGPoint(x: cardRect.minX, y: cardRect.maxY - r),
                              control: CGPoint(x: cardRect.minX, y: cardRect.maxY))
            path.addLine(to: CGPoint(x: cardRect.minX, y: cardRect.minY + r))
            path.addQuadCurve(to: CGPoint(x: cardRect.minX + r, y: cardRect.minY),
                              control: CGPoint(x: cardRect.minX, y: cardRect.minY))
        }

        path.closeSubpath()
        return path
    }
}

/// Apple Calendar's day header: weekday/TODAY/TOMORROW label + natural
/// date. Shared by the agenda list and the day-hover preview.
struct DayHeaderView: View {
    let day: Date
    let calendar: Calendar

    var body: some View {
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
}
