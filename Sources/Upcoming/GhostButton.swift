import AppKit
import SwiftUI

/// Corner radius shared by hover/press backgrounds of interactive
/// controls. (Uncommitted convention.)
let interactiveCornerRadius: CGFloat = 6

extension Color {
    /// Apple Calendar's today-red (systemRed), shared by the grid's
    /// today badge and the agenda's TODAY header.
    static let todayRed = Color(red: 1.0, green: 0.23, blue: 0.19)
}

/// Borderless button that shows a subtle background on hover and a
/// slightly stronger one while pressed. Copied from Uncommitted.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GhostButtonBody(label: configuration.label, isPressed: configuration.isPressed)
    }
}

/// Apple Calendar-style nav button: a constant soft-grey fill in the
/// given shape (not hover-only like GhostButton), darkening on hover
/// and press.
struct CalendarNavButtonStyle<S: Shape>: ButtonStyle {
    let shape: S

    func makeBody(configuration: Configuration) -> some View {
        CalendarNavButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            shape: shape
        )
    }
}

private struct CalendarNavButtonBody<Label: View, S: Shape>: View {
    let label: Label
    let isPressed: Bool
    let shape: S
    @State private var isHovered = false

    var body: some View {
        label
            .background(
                shape
                    .fill(fill)
                    .animation(.easeOut(duration: 0.2), value: isPressed)
                    .animation(.easeOut(duration: 0.2), value: isHovered)
            )
            .contentShape(shape)
            .onHover { isHovered = $0 }
    }

    private var fill: Color {
        // Explicit-ish opacities tuned to stay visible through the
        // panel's vibrancy (subtler values disappear into the material).
        if isPressed { return Color.primary.opacity(0.22) }
        if isHovered { return Color.primary.opacity(0.16) }
        return Color.primary.opacity(0.10)
    }
}

private struct GhostButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    @State private var isHovered = false

    var body: some View {
        label
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: interactiveCornerRadius)
                    .fill(fill)
                    // Animate ONLY on press state changes so the click
                    // fades in/out instead of snapping. Scoping to
                    // `value: isPressed` keeps the animation from
                    // bleeding into other properties.
                    .animation(.easeOut(duration: 0.35), value: isPressed)
            )
            .contentShape(RoundedRectangle(cornerRadius: interactiveCornerRadius))
            .onHover { isHovered = $0 }
    }

    private var fill: Color {
        if isPressed { return Color.primary.opacity(0.18) }
        if isHovered { return Color.primary.opacity(0.08) }
        return .clear
    }
}

/// Caption box for instant hover tips — native `.help()` tooltips carry
/// macOS's fixed ~1.5s delay. Positioning is the caller's job (anchor
/// preference at the scroll-view level, so the tip draws above all rows;
/// an in-place overlay loses the z-order fight with later siblings).
struct HoverTipLabel: View {
    let text: String

    var body: some View {
        Text(text)
            // 11pt = native macOS tooltip size (NSFont.toolTipsFont).
            .font(.system(size: 11))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thickMaterial,
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.12),
                    radius: 6, x: 0, y: 2)
            .fixedSize()
            .allowsHitTesting(false)
    }
}

extension View {
    /// Changes the cursor to a pointing hand while hovering this view so
    /// clickable controls read as clickable (macOS doesn't do this by
    /// default the way web browsers do).
    ///
    /// Uses `onContinuousHover` + `NSCursor.set()` rather than the
    /// `push()`/`pop()` stack — the stack desyncs when rows recycle in a
    /// LazyVStack, leaving the cursor stuck. (Uncommitted's lesson.)
    func pointingHandCursor(_ enabled: Bool = true) -> some View {
        onContinuousHover { phase in
            switch phase {
            case .active:
                if enabled {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            case .ended:
                NSCursor.arrow.set()
            }
        }
    }
}
