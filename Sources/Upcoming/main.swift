import AppKit

// Top-level code in main.swift is not MainActor-isolated under the v5
// language mode, hence the explicit hop.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    // LSUIElement in Info.plist covers bundle launches; .accessory also
    // covers running the bare binary during development.
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
