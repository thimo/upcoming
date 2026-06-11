import AppKit
import ServiceManagement
import SwiftUI
import UpcomingCore

/// Settings window content, Uncommitted's setup: a TabView inside the
/// SwiftUI `Settings` scene, one struct per tab, each tab a grouped Form
/// at fixed width with `fixedSize` so the window hugs its content.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }

            CalendarsSettingsView()
                .tabItem { Label("Calendars", systemImage: "calendar") }

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
    }
}

private let tabWidth: CGFloat = 480

// MARK: - General

struct GeneralSettingsView: View {
    @EnvironmentObject private var config: AppConfig
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Shortcut") {
                ShortcutRecorderRow(shortcut: $config.globalShortcut)
            }

            Section {
                Picker("Alert before video meetings", selection: $config.notificationLeadMinutes) {
                    ForEach([0, 1, 2, 3, 5, 10, 15], id: \.self) { minutes in
                        Text(
                            minutes == 0 ? "None"
                                : minutes == 1 ? "1 minute" : "\(minutes) minutes"
                        )
                        .tag(minutes)
                    }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Only events with a video-call link get an alert; the notification's Join button opens the call directly.")
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.60))
            }

            Section {
                Toggle(
                    "Combine multiple all-day events from the same calendar",
                    isOn: $config.combineAllDayPills
                )
            } header: {
                Text("Agenda")
            } footer: {
                Text("Days where one calendar has several all-day events show a single count pill; click it to expand.")
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.60))
            }

            Section("Startup") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: tabWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Calendars

/// Per-calendar visibility toggles, grouped by account/source. Hidden
/// calendars disappear from grid dots and list.
struct CalendarsSettingsView: View {
    @EnvironmentObject private var calendarService: CalendarService
    @EnvironmentObject private var config: AppConfig

    @State private var calendars: [CalendarInfo] = []

    var body: some View {
        Form {
            ForEach(groupedSources, id: \.source) { group in
                Section(group.source) {
                    ForEach(group.calendars) { calendar in
                        Toggle(isOn: isVisibleBinding(calendar.id)) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(calendarColor: calendar.color))
                                    .frame(width: 10, height: 10)
                                Text(calendar.title)
                            }
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        // Fixed height (unlike the other tabs): the calendar list length
        // varies per Mac and scrolls when it doesn't fit.
        .frame(width: tabWidth, height: 440)
        .onAppear(perform: refresh)
        .onChange(of: calendarService.changeToken) { refresh() }
    }

    /// Calendars grouped per account ("iCloud", "Exchange", …), keeping
    /// CalendarService's (source, title) sort order.
    private var groupedSources: [(source: String, calendars: [CalendarInfo])] {
        var order: [String] = []
        var bySource: [String: [CalendarInfo]] = [:]
        for calendar in calendars {
            if bySource[calendar.sourceTitle] == nil {
                order.append(calendar.sourceTitle)
            }
            bySource[calendar.sourceTitle, default: []].append(calendar)
        }
        return order.map { (source: $0, calendars: bySource[$0] ?? []) }
    }

    private func refresh() {
        calendars = calendarService.calendars()
    }

    private func isVisibleBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !config.hiddenCalendarIDs.contains(id) },
            set: { visible in
                if visible {
                    config.hiddenCalendarIDs.remove(id)
                } else {
                    config.hiddenCalendarIDs.insert(id)
                }
            }
        )
    }
}

// MARK: - Shortcut recorder

/// Inline shortcut recorder: click to start recording, press a key combo
/// to set it, Escape to cancel. Uses `addLocalMonitorForEvents` which
/// works in the active Settings window without extra permissions.
/// Copied from Uncommitted.
private struct ShortcutRecorderRow: View {
    @Binding var shortcut: GlobalShortcut?
    @StateObject private var recorder = ShortcutRecorderState()

    var body: some View {
        HStack {
            Text("Toggle popup")
            Spacer()
            Button(action: { recorder.startRecording() }) {
                Text(recorder.isRecording ? "Press shortcut…" : displayText)
                    .frame(minWidth: 100, alignment: .center)
                    .foregroundStyle(recorder.isRecording ? .secondary : .primary)
            }
            .buttonStyle(.bordered)
            if shortcut != nil && !recorder.isRecording {
                Button(action: { shortcut = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: recorder.recorded) { _, newValue in
            if let newValue {
                shortcut = newValue
                recorder.recorded = nil
            }
        }
    }

    private var displayText: String {
        shortcut?.displayString ?? "None"
    }
}

private final class ShortcutRecorderState: ObservableObject {
    @Published var isRecording = false
    @Published var recorded: GlobalShortcut?
    private var monitor: Any?

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            // Escape cancels recording.
            if event.keyCode == 53 {
                self.stopRecording()
                return nil
            }

            // Require at least one "real" modifier (not just Shift alone).
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasModifier = mods.contains(.command)
                || mods.contains(.control)
                || mods.contains(.option)
            guard hasModifier else { return nil }

            let character = Self.displayCharacter(
                for: event.keyCode,
                fallback: event.charactersIgnoringModifiers
            )
            self.recorded = GlobalShortcut(
                keyCode: Int(event.keyCode),
                character: character,
                command: mods.contains(.command),
                shift: mods.contains(.shift),
                option: mods.contains(.option),
                control: mods.contains(.control)
            )
            self.stopRecording()
            return nil // consume the event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    /// Best-effort display string for a virtual key code. Falls back to
    /// the event's `charactersIgnoringModifiers` for regular keys.
    static func displayCharacter(for keyCode: UInt16, fallback: String?) -> String {
        switch Int(keyCode) {
        // F-keys
        case 0x7A: return "F1"
        case 0x78: return "F2"
        case 0x63: return "F3"
        case 0x76: return "F4"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x6D: return "F10"
        case 0x67: return "F11"
        case 0x6F: return "F12"
        // Special keys
        case 0x31: return "Space"
        case 0x24: return "Return"
        case 0x30: return "Tab"
        case 0x33: return "Delete"
        case 0x75: return "Fwd Del"
        case 0x7E: return "↑"
        case 0x7D: return "↓"
        case 0x7B: return "←"
        case 0x7C: return "→"
        default:
            return fallback?.uppercased() ?? "?"
        }
    }
}

// MARK: - About

struct AboutSettingsView: View {
    /// GitHub's official mark, template-rendered so it follows the link
    /// colour. (Uncommitted's asset, bundled via SPM resources.)
    private static let githubMark: NSImage? = {
        guard let url = Bundle.module.url(forResource: "github-mark", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        return image
    }()

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private var buildDateString: String {
        guard let execURL = Bundle.main.executableURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: execURL.path),
              let date = attrs[.modificationDate] as? Date else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy 'at' HH:mm"
        return "Built \(formatter.string(from: date))"
    }

    var body: some View {
        VStack(spacing: 12) {
            // THE shared glyph (CalendarGlyph, same drawing as app icon
            // and menu bar), masked with the brand gradient —
            // Uncommitted's About treatment (no squircle background
            // here; that's the app icon's job).
            LinearGradient(
                colors: [
                    Color(red: 0.878, green: 0.000, blue: 0.565), // #E00090
                    Color(red: 0.537, green: 0.000, blue: 0.824), // #8900D2
                    Color(red: 0.310, green: 0.000, blue: 1.000), // #4F00FF
                ],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
            .mask {
                Image(nsImage: CalendarGlyph.image(width: 90))
            }
            .frame(width: 90, height: 84)
            .padding(.top, 28)

            VStack(spacing: 2) {
                Text("Upcoming")
                    .font(.title.weight(.semibold))
                Text("Version \(version)")
                    .font(.callout)
                    .foregroundStyle(.primary.opacity(0.70))
                Text(buildDateString)
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.50))
            }

            Text("Your calendar, one click away.")
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.70))

            Link(destination: URL(string: "https://github.com/thimo/upcoming")!) {
                HStack(spacing: 6) {
                    if let mark = Self.githubMark {
                        Image(nsImage: mark)
                            .resizable()
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.up.right.square")
                    }
                    Text("github.com/thimo/upcoming")
                }
                .font(.callout)
            }
            .pointingHandCursor()
            .padding(.top, 6)

            // Manual check until the Sparkle pipeline lands (roadmap);
            // Sparkle's updater takes over this button then.
            Button("Check for Updates…") {
                NSWorkspace.shared.open(
                    URL(string: "https://github.com/thimo/upcoming/releases")!
                )
            }
            .padding(.top, 2)

            Text("Built with ❤️ in the Netherlands by Thimo Jansen.")
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.50))
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
        .frame(width: tabWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}
