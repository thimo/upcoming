import Foundation

/// UserDefaults-backed settings. Kept tiny on purpose: the spec is a
/// per-calendar on/off list plus a notification lead time.
@MainActor
public final class AppConfig: ObservableObject {
    private enum Key {
        static let hiddenCalendarIDs = "hiddenCalendarIDs"
        static let notificationLeadMinutes = "notificationLeadMinutes"
        static let globalShortcut = "globalShortcut"
        static let combineAllDayPills = "combineAllDayPills"
    }

    private let defaults: UserDefaults

    @Published public var hiddenCalendarIDs: Set<String> {
        didSet { defaults.set(Array(hiddenCalendarIDs), forKey: Key.hiddenCalendarIDs) }
    }

    /// Minutes before an event with a video-call link to fire a
    /// notification; 0 = notifications off. Persisted as -1 when off,
    /// because UserDefaults returns 0 for "never set" and that case must
    /// fall back to the 1-minute default.
    @Published public var notificationLeadMinutes: Int {
        didSet {
            defaults.set(
                notificationLeadMinutes == 0 ? -1 : notificationLeadMinutes,
                forKey: Key.notificationLeadMinutes
            )
        }
    }

    /// Global hotkey that toggles the popup. nil = explicitly cleared by
    /// the user (stored as empty Data, distinct from "never set" which
    /// gets the ⌘⇧C default).
    @Published public var globalShortcut: GlobalShortcut? {
        didSet {
            if let shortcut = globalShortcut,
               let data = try? JSONEncoder().encode(shortcut) {
                defaults.set(data, forKey: Key.globalShortcut)
            } else {
                defaults.set(Data(), forKey: Key.globalShortcut)
            }
        }
    }

    /// ≥2 all-day events from the same calendar on one day collapse into
    /// a single count-pill in the agenda (default on). The rule only ever
    /// hits noisy calendars; single pills are never touched.
    @Published public var combineAllDayPills: Bool {
        didSet { defaults.set(combineAllDayPills, forKey: Key.combineAllDayPills) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.combineAllDayPills = defaults.object(forKey: Key.combineAllDayPills) as? Bool ?? true
        self.hiddenCalendarIDs = Set(defaults.stringArray(forKey: Key.hiddenCalendarIDs) ?? [])
        let lead = defaults.integer(forKey: Key.notificationLeadMinutes)
        self.notificationLeadMinutes = lead == 0 ? 1 : max(0, lead)
        if let data = defaults.data(forKey: Key.globalShortcut) {
            self.globalShortcut = data.isEmpty
                ? nil
                : try? JSONDecoder().decode(GlobalShortcut.self, from: data)
        } else {
            self.globalShortcut = .defaultShortcut
        }
    }
}
