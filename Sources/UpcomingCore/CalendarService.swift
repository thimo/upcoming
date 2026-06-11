import AppKit
import EventKit
import Foundation

/// EventKit wrapper. Reads whatever Calendar.app syncs (iCloud, Exchange /
/// Microsoft 365, Google, …) — Upcoming never talks to calendar providers
/// itself, so there is no account setup and no OAuth.
@MainActor
public final class CalendarService: ObservableObject {
    public enum AuthState {
        case undetermined
        case denied
        case authorized
    }

    @Published public private(set) var authState: AuthState = .undetermined
    /// Bumped whenever the underlying store reports changes, so views can
    /// re-fetch. Cheaper than diffing EventKit's coarse change notification.
    @Published public private(set) var changeToken = UUID()

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    public init() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            authState = .authorized
        case .notDetermined:
            authState = .undetermined
        default:
            authState = .denied
        }

        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.changeToken = UUID()
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func requestAccess() {
        guard authState == .undetermined else { return }
        store.requestFullAccessToEvents { [weak self] granted, _ in
            Task { @MainActor in
                guard let self else { return }
                self.authState = granted ? .authorized : .denied
                self.changeToken = UUID()
            }
        }
    }

    /// All calendars, for the Settings toggle list.
    public func calendars() -> [CalendarInfo] {
        store.calendars(for: .event).map { cal in
            CalendarInfo(
                id: cal.calendarIdentifier,
                title: cal.title,
                sourceTitle: cal.source?.title ?? "",
                color: CalendarColor(nsColor: cal.color)
            )
        }
        .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
    }

    /// Events in [from, to], excluding hidden calendars and meetings the
    /// user declined (spec: declined = gone from list and grid dots).
    public func events(
        from: Date,
        to: Date,
        hiddenCalendarIDs: Set<String>
    ) -> [EventItem] {
        guard authState == .authorized else { return [] }

        let visible = store.calendars(for: .event)
            .filter { !hiddenCalendarIDs.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: visible)
        return store.events(matching: predicate)
            .filter { !isDeclinedByMe($0) }
            .map(eventItem(from:))
    }

    private func isDeclinedByMe(_ event: EKEvent) -> Bool {
        guard let attendees = event.attendees,
              let me = attendees.first(where: { $0.isCurrentUser }) else {
            return false
        }
        return me.participantStatus == .declined
    }

    private func eventItem(from event: EKEvent) -> EventItem {
        // eventIdentifier is shared across occurrences of a recurring
        // event; the start timestamp disambiguates the occurrence.
        let baseID = event.eventIdentifier ?? UUID().uuidString
        let id = "\(baseID)@\(Int(event.startDate.timeIntervalSince1970))"
        return EventItem(
            id: id,
            title: event.title ?? "(untitled)",
            calendarID: event.calendar?.calendarIdentifier ?? "",
            color: CalendarColor(nsColor: event.calendar?.color),
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location?.trimmingCharacters(in: .whitespacesAndNewlines),
            videoCallURL: VideoCallDetector.detect(
                url: event.url,
                location: event.location,
                notes: event.notes
            )
        )
    }
}

extension CalendarColor {
    init(nsColor: NSColor?) {
        guard let rgb = nsColor?.usingColorSpace(.sRGB) else {
            self.init(red: 0.5, green: 0.5, blue: 0.5)
            return
        }
        self.init(
            red: Double(rgb.redComponent),
            green: Double(rgb.greenComponent),
            blue: Double(rgb.blueComponent)
        )
    }
}
