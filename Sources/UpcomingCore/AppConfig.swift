import Foundation

/// UserDefaults-backed settings. Kept tiny on purpose: the spec is a
/// per-calendar on/off list plus a notification lead time.
@MainActor
public final class AppConfig: ObservableObject {
    private enum Key {
        static let hiddenCalendarIDs = "hiddenCalendarIDs"
        static let notificationLeadMinutes = "notificationLeadMinutes"
        static let globalShortcut = "globalShortcut"
    }

    private let defaults: UserDefaults

    @Published public var hiddenCalendarIDs: Set<String> {
        didSet { defaults.set(Array(hiddenCalendarIDs), forKey: Key.hiddenCalendarIDs) }
    }

    /// Minutes before an event with a video-call link to fire a notification.
    @Published public var notificationLeadMinutes: Int {
        didSet { defaults.set(notificationLeadMinutes, forKey: Key.notificationLeadMinutes) }
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

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hiddenCalendarIDs = Set(defaults.stringArray(forKey: Key.hiddenCalendarIDs) ?? [])
        let lead = defaults.integer(forKey: Key.notificationLeadMinutes)
        self.notificationLeadMinutes = lead > 0 ? lead : 5
        if let data = defaults.data(forKey: Key.globalShortcut) {
            self.globalShortcut = data.isEmpty
                ? nil
                : try? JSONDecoder().decode(GlobalShortcut.self, from: data)
        } else {
            self.globalShortcut = .defaultShortcut
        }
    }
}
