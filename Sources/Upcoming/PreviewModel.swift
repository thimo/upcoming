import SwiftUI
import UpcomingCore

/// Bridges hover state from the SwiftUI popup to the AppKit-driven hover
/// preview panel. A row reports which payload the cursor is over and where
/// it sits (in the popup's `.global` coordinate space — top-left origin);
/// the AppDelegate observes `request`, positions an interactive child panel
/// beside the popup, and then owns *closing* via global cursor tracking
/// (the panel stays open while the cursor is over the row or the card).
///
/// Closing can't be driven by the card's SwiftUI `.onHover`: hover tracking
/// only fires in the key window, and the preview panel isn't key until
/// clicked — so the AppDelegate watches the real cursor position instead.
@MainActor
final class PreviewModel: ObservableObject {
    enum Payload: Equatable {
        case event(EventItem)
        case day(DaySection)
        /// A collapsed all-day count pill: its hidden events.
        case group(events: [EventItem])
    }

    struct Request: Equatable {
        let payload: Payload
        /// Hovered view's frame in the popup `.global` space.
        let anchor: CGRect
    }

    @Published private(set) var request: Request?

    func show(_ payload: Payload, anchor: CGRect) {
        request = Request(payload: payload, anchor: anchor)
    }

    func clear() {
        request = nil
    }
}

private struct PreviewHover: ViewModifier {
    let payload: PreviewModel.Payload
    @EnvironmentObject private var preview: PreviewModel
    /// The hovered view's frame in the popup `.global` space, kept fresh as
    /// the list scrolls. Captured via a background reader so `.onHover` can
    /// sit on the content itself (the pattern RowHover uses, which fires
    /// reliably — `.onHover` on a clear background did not). Only *opening*
    /// is driven here; the AppDelegate closes it via cursor tracking.
    @State private var anchor: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { anchor = geo.frame(in: .global) }
                        .onChange(of: geo.frame(in: .global)) { anchor = geo.frame(in: .global) }
                }
            )
            .onHover { hovering in
                if hovering { preview.show(payload, anchor: anchor) }
            }
    }
}

extension View {
    /// Show the Apple-Calendar-style hover preview for `payload` while the
    /// pointer is over this view.
    func previewHover(_ payload: PreviewModel.Payload) -> some View {
        modifier(PreviewHover(payload: payload))
    }

    /// As `previewHover`, but a no-op when there's nothing to show (e.g. a
    /// grid day with no events).
    @ViewBuilder
    func previewHoverIfPresent(_ payload: PreviewModel.Payload?) -> some View {
        if let payload {
            modifier(PreviewHover(payload: payload))
        } else {
            self
        }
    }
}
