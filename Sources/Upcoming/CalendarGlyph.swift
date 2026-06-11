import AppKit

/// THE calendar glyph — single source of truth for all three surfaces:
/// the app icon (Resources/make-icon.swift compiles this file in), the
/// About tab (gradient mask) and the menu bar status item (template).
///
/// Form language follows the SF Symbol "calendar" — rounded frame with a
/// solid header band, inner panel, 4×3 dot grid — but is an original
/// drawing: Apple's licence forbids SF Symbols in app icons.
enum CalendarGlyph {
    /// Aspect ratio height/width of the glyph card.
    static let aspect: CGFloat = 54.0 / 58.0

    struct Geometry {
        let card: CGRect
        let cardCorner: CGFloat
        let panel: CGRect
        let panelCorner: CGFloat
        let dotRadius: CGFloat
        /// 3 rows (top → bottom) × 4 columns (left → right), in the
        /// caller's coordinate space (y-up assumed). Reference grid; not
        /// every position is drawn (see `dots`).
        let dotCenters: [[CGPoint]]
        /// The dots actually drawn: the grid minus top-left and
        /// bottom-right — a month rarely fills its first and last grid
        /// cell, and it keeps the glyph clearly distinct from the SF
        /// Symbol.
        let dots: [CGPoint]
    }

    /// Fits the glyph centered in `rect`, preserving aspect. All measures
    /// scale with the card width.
    static func geometry(fitting rect: CGRect) -> Geometry {
        var width = rect.width
        var height = width * aspect
        if height > rect.height {
            height = rect.height
            width = height / aspect
        }
        let card = CGRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
        let border = width * 0.055
        let headerHeight = width * 0.224 // includes the top border
        let panel = CGRect(
            x: card.minX + border,
            y: card.minY + border,
            width: width - border * 2,
            height: height - border - headerHeight
        )
        var centers: [[CGPoint]] = []
        for rowFraction in [0.25, 0.50, 0.75] { // from panel top
            var row: [CGPoint] = []
            for colFraction in [0.2, 0.4, 0.6, 0.8] {
                row.append(CGPoint(
                    x: panel.minX + panel.width * colFraction,
                    y: panel.maxY - panel.height * rowFraction
                ))
            }
            centers.append(row)
        }
        var dots: [CGPoint] = []
        for (rowIndex, row) in centers.enumerated() {
            for (colIndex, center) in row.enumerated() {
                if (rowIndex == 0 && colIndex == 0) || (rowIndex == 2 && colIndex == 3) {
                    continue
                }
                dots.append(center)
            }
        }
        // Concentric corners: outer radius = inner radius + border, or
        // the bottom corners look thick.
        let panelCorner = width * 0.086
        return Geometry(
            card: card,
            cardCorner: panelCorner + border,
            panel: panel,
            panelCorner: panelCorner,
            dotRadius: width * 0.045,
            dotCenters: centers,
            dots: dots
        )
    }

    /// Single-colour rendering: frame with the panel punched out
    /// (even-odd) plus the dot grid.
    static func draw(in ctx: CGContext, geometry: Geometry, color: CGColor) {
        ctx.setFillColor(color)
        let frame = CGMutablePath()
        frame.addPath(CGPath(
            roundedRect: geometry.card,
            cornerWidth: geometry.cardCorner,
            cornerHeight: geometry.cardCorner,
            transform: nil
        ))
        frame.addPath(CGPath(
            roundedRect: geometry.panel,
            cornerWidth: geometry.panelCorner,
            cornerHeight: geometry.panelCorner,
            transform: nil
        ))
        ctx.addPath(frame)
        ctx.fillPath(using: .evenOdd)

        for center in geometry.dots {
            ctx.addEllipse(in: CGRect(
                x: center.x - geometry.dotRadius,
                y: center.y - geometry.dotRadius,
                width: geometry.dotRadius * 2,
                height: geometry.dotRadius * 2
            ))
        }
        ctx.fillPath()
    }

    /// Rendered image, e.g. for the menu bar (template) or as a mask
    /// (only the alpha channel matters there).
    static func image(width: CGFloat, isTemplate: Bool = false) -> NSImage {
        let size = NSSize(width: width, height: ceil(width * aspect))
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: ctx, geometry: geometry(fitting: rect), color: NSColor.black.cgColor)
            return true
        }
        image.isTemplate = isTemplate
        return image
    }
}
