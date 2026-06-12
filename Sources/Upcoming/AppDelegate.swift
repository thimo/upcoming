import AppKit
import Combine
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
    private let hotkeyManager = HotkeyManager()
    private let notificationScheduler = NotificationScheduler()
    private var subscriptions = Set<AnyCancellable>()

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
        // LSUIElement in Info.plist covers bundle launches; .accessory also
        // covers running the bare binary during development.
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPanel()
        calendarService.requestAccess()

        // Global hotkey (default ⌘⇧C). The published-property sink also
        // fires once on subscription, registering the initial shortcut.
        hotkeyManager.onTrigger = { [weak self] in
            self?.togglePopupFromHotkey()
        }
        config.$globalShortcut.sink { [weak self] shortcut in
            if let shortcut {
                self?.hotkeyManager.register(shortcut)
            } else {
                self?.hotkeyManager.unregister()
            }
        }
        .store(in: &subscriptions)

        // Notifications before video meetings. Reschedule wholesale on
        // every input change; the changeToken sink fires once on
        // subscription, covering the initial schedule at launch.
        notificationScheduler.setUp()
        calendarService.$changeToken
            .combineLatest(config.$notificationLeadMinutes, config.$hiddenCalendarIDs)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rescheduleNotifications()
            }
            .store(in: &subscriptions)

        // The scheduling horizon is 48h; without changes or relaunches the
        // pending set would silently run dry. Slow timer + wake-from-sleep
        // keep it topped up (spec's sleep/wake-backstop pattern).
        Timer.publish(every: 6 * 3600, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.rescheduleNotifications()
            }
            .store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func didWake(_ note: Notification) {
        rescheduleNotifications()
    }

    /// Fetches the next 48h and re-schedules video-meeting notifications.
    private func rescheduleNotifications() {
        let lead = config.notificationLeadMinutes
        let hidden = config.hiddenCalendarIDs
        Task {
            let now = Date()
            let horizon = now.addingTimeInterval(48 * 3600)
            let events = await calendarService.events(
                from: now, to: horizon, hiddenCalendarIDs: hidden
            )
            notificationScheduler.schedule(events: events, leadMinutes: lead)
        }
    }

    private func togglePopupFromHotkey() {
        guard let panel, let button = statusItem?.button else { return }
        if panel.isVisible {
            closePopup()
        } else {
            showPopup(from: button)
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // THE shared glyph (CalendarGlyph, same drawing as app icon
            // and About tab) as a template image, so it follows the menu
            // bar appearance.
            button.image = CalendarGlyph.image(width: 17, isTemplate: true)
            button.image?.accessibilityDescription = "Upcoming"
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
        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit Upcoming",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
    }

    // MARK: - Settings window

    @objc private func openSettings() {
        closePopup()
        // Accessory apps don't activate on their own; without this the
        // Settings window opens behind whatever is frontmost.
        NSApp.activate(ignoringOtherApps: true)
        // Opens the SwiftUI `Settings` scene from AppKit. Soft-deprecated
        // responder-chain selector, but the sanctioned `openSettings`
        // environment value only exists inside SwiftUI views.
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Popup panel

    private func setupPanel() {
        let contentView = ContentView()
            .environmentObject(calendarService)
            .environmentObject(config)

        // No sizingOptions: the panel dictates the size (clamped in
        // showPopup); the autolayout constraints stretch the SwiftUI
        // content to fill it.
        let hosting = NSHostingController(rootView: AnyView(contentView))
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

    /// Breathing room kept below the popup (Fantastical leaves a similar
    /// gap); the popup otherwise fills the screen's visible height.
    private static let panelBottomMargin: CGFloat = 24

    private func showPopup(from button: NSStatusBarButton) {
        guard let panel else { return }

        guard let buttonWindow = button.window else { return }
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonFrameInWindow)

        let screen = NSScreen.screens.first(where: { $0.frame.contains(buttonFrameOnScreen.origin) })
            ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Fill the screen's visible height bar a small bottom margin —
        // scales with the display, never runs off a small or scaled
        // screen; the agenda list inside flexes with it.
        let fitting = NSSize(
            width: ContentView.panelWidth,
            height: visibleFrame.height - Self.panelBottomMargin
        )
        panel.setContentSize(fitting)

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
            // Arrow keys step the agenda by a day; ⌘ makes it a week.
            let step = event.modifierFlags.contains(.command) ? 7 : 1
            switch event.keyCode {
            case 53: // escape
                self.closePopup()
                return nil
            case 124, 125: // right / down → forward
                NotificationCenter.default.post(
                    name: .navigateAgendaDay, object: nil, userInfo: ["delta": step])
                return nil
            case 123, 126: // left / up → backward
                NotificationCenter.default.post(
                    name: .navigateAgendaDay, object: nil, userInfo: ["delta": -step])
                return nil
            default:
                return event
            }
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
    /// Arrow-key day navigation; userInfo["delta"] is +1 or -1 days.
    static let navigateAgendaDay = Notification.Name("UpcomingNavigateAgendaDay")
}
