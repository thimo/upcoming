// Generates an .iconset directory with all sizes macOS expects for iconutil.
//
// Compiled by build.sh together with Sources/Upcoming/CalendarGlyph.swift
// (swiftc, multi-file — hence @main instead of top-level code), so the
// icon renders THE shared glyph: the same drawing feeds the About tab
// and the menu bar status item.
//
// Background recipe copied from Uncommitted (same palette on purpose —
// house style): Apple Big Sur+ template geometry, pink→purple→blue
// gradient, magenta hotspot, top-edge highlight, drop shadow in the
// 100px gutter.
//
//   Canvas:         1024×1024
//   Icon body:      824×824 centered (100px gutter all sides)
//   Corner radius:  ~232 circular ≈ Apple's 185.4 continuous squircle
//   Drop shadow:    28px blur, 12px down, black 50%
//
// The glyph itself is plain white on the gradient.

import Foundation
import AppKit

// Palette (sampled from Datadog's brand gradient, via Uncommitted).
private let pink   = (r: CGFloat(0.878), g: CGFloat(0.000), b: CGFloat(0.565)) // #E00090
private let purple = (r: CGFloat(0.537), g: CGFloat(0.000), b: CGFloat(0.824)) // #8900D2
private let blue   = (r: CGFloat(0.310), g: CGFloat(0.000), b: CGFloat(1.000)) // #4F00FF

@main
struct MakeIcon {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            FileHandle.standardError.write("Usage: make-icon <output.iconset>\n".data(using: .utf8)!)
            exit(1)
        }

        let outDir = URL(fileURLWithPath: args[1])
        try? FileManager.default.removeItem(at: outDir)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        struct IconEntry {
            let base: Int
            let scale: Int
            var filename: String {
                scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@\(scale)x.png"
            }
            var pixelSize: Int { base * scale }
        }

        let entries: [IconEntry] = [
            .init(base: 16, scale: 1),
            .init(base: 16, scale: 2),
            .init(base: 32, scale: 1),
            .init(base: 32, scale: 2),
            .init(base: 128, scale: 1),
            .init(base: 128, scale: 2),
            .init(base: 256, scale: 1),
            .init(base: 256, scale: 2),
            .init(base: 512, scale: 1),
            .init(base: 512, scale: 2),
        ]

        for entry in entries {
            let image = render(size: CGFloat(entry.pixelSize))
            let url = outDir.appendingPathComponent(entry.filename)
            try writePNG(image, to: url, pixelSize: entry.pixelSize)
            print("wrote \(entry.filename)")
        }
    }
}

private func render(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    // Apple template geometry: 824×824 icon body inside a 1024×1024
    // canvas, with 100px gutter on every side that hosts the drop shadow.
    let gutter = size * (100.0 / 1024.0)
    let inner = size - gutter * 2
    let rect = CGRect(x: gutter, y: gutter, width: inner, height: inner)
    let cornerRadius = inner * (232.0 / 824.0)
    let bodyPath = CGPath(
        roundedRect: rect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )

    // Icon body drop shadow (cast from an opaque fill that the gradient
    // immediately paints over).
    let shadowScale = size / 1024.0
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -12 * shadowScale),
        blur: 28 * shadowScale,
        color: NSColor.black.withAlphaComponent(0.5).cgColor
    )
    ctx.addPath(bodyPath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()

    // Pink → purple → blue-violet linear gradient, bottom-left → top-right.
    let gradientColors = [
        NSColor(srgbRed: pink.r, green: pink.g, blue: pink.b, alpha: 1).cgColor,
        NSColor(srgbRed: purple.r, green: purple.g, blue: purple.b, alpha: 1).cgColor,
        NSColor(srgbRed: blue.r, green: blue.g, blue: blue.b, alpha: 1).cgColor,
    ]
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: gradientColors as CFArray,
        locations: [0.0, 0.55, 1.0]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.minY),
        end: CGPoint(x: rect.maxX, y: rect.maxY),
        options: []
    )

    // Vivid magenta radial hotspot, screen-blended for luminance.
    let hotspotColors = [
        NSColor(srgbRed: 1.00, green: 0.10, blue: 0.70, alpha: 0.70).cgColor,
        NSColor(srgbRed: 1.00, green: 0.10, blue: 0.70, alpha: 0.00).cgColor,
    ]
    let hotspot = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: hotspotColors as CFArray,
        locations: [0, 1]
    )!
    let hotspotCenter = CGPoint(
        x: rect.minX + inner * 0.25,
        y: rect.minY + inner * 0.82
    )
    ctx.saveGState()
    ctx.setBlendMode(.screen)
    ctx.drawRadialGradient(
        hotspot,
        startCenter: hotspotCenter,
        startRadius: 0,
        endCenter: hotspotCenter,
        endRadius: inner * 0.7,
        options: []
    )
    ctx.restoreGState()

    // Subtle inner highlight along the top edge for depth.
    let highlightColors = [
        NSColor.white.withAlphaComponent(0.18).cgColor,
        NSColor.white.withAlphaComponent(0.0).cgColor,
    ]
    let highlight = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: highlightColors as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        highlight,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY + inner * 0.55),
        options: []
    )

    // ---- The shared glyph ----

    let glyphRect = CGRect(
        x: rect.midX - inner * 0.29,
        y: rect.midY - inner * 0.27,
        width: inner * 0.58,
        height: inner * 0.54
    )
    let geometry = CalendarGlyph.geometry(fitting: glyphRect)

    ctx.restoreGState() // body clip

    // White glyph with a soft drop shadow for lift.
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.012),
        blur: size * 0.04,
        color: NSColor.black.withAlphaComponent(0.35).cgColor
    )
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    CalendarGlyph.draw(in: ctx, geometry: geometry, color: NSColor.white.cgColor)
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    return image
}

private func writePNG(_ image: NSImage, to url: URL, pixelSize: Int) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else {
        throw NSError(domain: "make-icon", code: 1)
    }
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-icon", code: 2)
    }
    try png.write(to: url)
}
