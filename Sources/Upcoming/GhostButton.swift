import AppKit
import SwiftUI

/// Corner radius shared by hover/press backgrounds of interactive
/// controls. (Uncommitted convention.)
let interactiveCornerRadius: CGFloat = 6

/// Borderless button that shows a subtle background on hover and a
/// slightly stronger one while pressed. Copied from Uncommitted.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GhostButtonBody(label: configuration.label, isPressed: configuration.isPressed)
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
