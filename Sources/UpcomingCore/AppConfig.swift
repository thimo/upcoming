import Foundation

/// UserDefaults-backed settings. Kept tiny on purpose: the spec is a
/// per-calendar on/off list plus a notification lead time.
@MainActor
public final class AppConfig: ObservableObject {
    private enum Key {
        static let hiddenCalendarIDs = "hiddenCalendarIDs"
        static let notificationLeadMinutes = "notificationLeadMinutes"
    }

    private let defaults: UserDefaults

    @Published public var hiddenCalendarIDs: Set<String> {
        didSet { defaults.set(Array(hiddenCalendarIDs), forKey: Key.hiddenCalendarIDs) }
    }

    /// Minutes before an event with a video-call link to fire a notification.
    @Published public var notificationLeadMinutes: Int {
        didSet { defaults.set(notificationLeadMinutes, forKey: Key.notificationLeadMinutes) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hiddenCalendarIDs = Set(defaults.stringArray(forKey: Key.hiddenCalendarIDs) ?? [])
        let lead = defaults.integer(forKey: Key.notificationLeadMinutes)
        self.notificationLeadMinutes = lead > 0 ? lead : 5
    }
}
