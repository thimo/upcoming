import AppKit
import SwiftUI
import UpcomingCore

/// Owns the menu-bar presence: an NSStatusItem toggling a floating NSPanel
/// that hosts the SwiftUI content. Custom NSPanel — not NSPopover (arrow
/// can't be hidden), not NSMenu (its tracking loop breaks scrolling, which
/// is fatal for our infinite agenda list), not MenuBarExtra (no control).
/// Pattern inherited from Uncommitted's AppDelegate.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    let calendarService = CalendarService()
    let config = AppConfig()

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyMonitor: Any?

    private static let cornerRadius: CGFloat = 10

    /// 9-slice mask for NSVisualEffectView so the vibrancy backing gets a
    /// rounded alpha channel and the window shadow follows the corners.
    /// (`layer.cornerRadius` is bypassed by behind-window vibrancy.)
    private static let roundedMaskImage: NSImage = {
        let radius = cornerRadius
        let edge = radius * 2 + 1
        let image = NSImage(
            size: NSSize(width: edge, height: edge),
            flipped: false
        ) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        setupStatusItem()
        setupPanel()
        calendarService.requestAccess()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "calendar",
                accessibilityDescription: "Upcoming"
            )
            button.target = self
            button.action = #selector(togglePopup(_:))
            // mouseDown so Bartender doesn't trigger its hidden bar.
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        statusItem = item
    }

    @objc private func togglePopup(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseDown {
            showContextMenu()
            return
        }
        guard let panel, let button = statusItem?.button else { return }
        if panel.isVisible {
            closePopup()
        } else {
            showPopup(from: button)
        }
    }

    private func showContextMenu() {
        guard let button = statusItem?.button else { return }
        let menu = NSMenu()
        let quit = NSMenuItem(
            title: "Quit Upcoming",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Popup panel

    private func setupPanel() {
        let contentView = ContentView()
            .environmentObject(calendarService)
            .environmentObject(config)

        let hosting = NSHostingController(rootView: AnyView(contentView))
        hosting.sizingOptions = .intrinsicContentSize
        self.hostingController = hosting

        let panel = PopupPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.fullScreenAuxiliary]

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .headerView
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.maskImage = Self.roundedMaskImage

        let hView = hosting.view
        hView.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(hView)
        NSLayoutConstraint.activate([
            hView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])

        panel.contentView = visualEffect
        self.panel = panel

        // Dismiss when the user switches Spaces, like every status-bar app.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    @objc private func activeSpaceDidChange(_ note: Notification) {
        guard let panel, panel.isVisible else { return }
        closePopup()
    }

    private func showPopup(from button: NSStatusBarButton) {
        guard let panel, let hostingController else { return }

        let hView = hostingController.view
        hView.layoutSubtreeIfNeeded()
        let fitting = hView.intrinsicContentSize
        panel.setContentSize(fitting)

        guard let buttonWindow = button.window else { return }
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonFrameInWindow)

        let screen = NSScreen.screens.first(where: { $0.frame.contains(buttonFrameOnScreen.origin) })
            ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let panelX = buttonFrameOnScreen.minX
        let panelY = visibleFrame.maxY - fitting.height - 1
        let maxX = visibleFrame.maxX - fitting.width
        let clampedX = min(panelX, maxX)

        panel.setFrameOrigin(NSPoint(x: clampedX, y: panelY))
        panel.orderFrontRegardless()
        panel.makeKey()
        NotificationCenter.default.post(name: .popupDidOpen, object: nil)

        button.highlight(true)
        installEventMonitors()
    }

    func closePopup() {
        statusItem?.button?.highlight(false)
        panel?.orderOut(nil)
        removeEventMonitors()
        NotificationCenter.default.post(name: .popupDidClose, object: nil)
    }

    // MARK: - Click-outside / escape dismissal

    private func installEventMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePopup()
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.window == panel { return event }
            if event.window == self.statusItem?.button?.window { return event }
            self.closePopup()
            return event
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible,
                  event.window == panel else { return event }
            if event.keyCode == 53 { // escape
                self.closePopup()
                return nil
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }
}

/// Borderless panels refuse key status by default; we need it so escape
/// reaches our key monitor. `.nonactivatingPanel` keeps the app itself
/// from activating.
final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

extension Notification.Name {
    static let popupDidOpen = Notification.Name("UpcomingPopupDidOpen")
    static let popupDidClose = Notification.Name("UpcomingPopupDidClose")
}
