import AppKit
@preconcurrency import EventKit
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

    // unsafe: EKEventStore is documented thread-safe but not Sendable-annotated;
    // the background fetch in events(from:to:) relies on this.
    private nonisolated(unsafe) let store = EKEventStore()
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

    /// All calendars, for the Settings toggle list. Source order: iCloud
    /// first (primary provider), Exchange last, everything else
    /// alphabetical in between; calendars alphabetical within a source.
    public func calendars() -> [CalendarInfo] {
        store.calendars(for: .event)
            .sorted { lhs, rhs in
                let lp = Self.sourcePriority(lhs.source)
                let rp = Self.sourcePriority(rhs.source)
                if lp != rp { return lp < rp }
                let ls = lhs.source?.title ?? ""
                let rs = rhs.source?.title ?? ""
                if ls != rs {
                    return ls.localizedCaseInsensitiveCompare(rs) == .orderedAscending
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .map { cal in
                CalendarInfo(
                    id: cal.calendarIdentifier,
                    title: cal.title,
                    sourceTitle: cal.source?.title ?? "",
                    color: CalendarColor(nsColor: cal.color)
                )
            }
    }

    /// iCloud is a plain CalDAV source titled "iCloud" (no dedicated
    /// type), so that one check is name-based; Exchange has a real
    /// source type.
    private nonisolated static func sourcePriority(_ source: EKSource?) -> Int {
        guard let source else { return 1 }
        if source.sourceType == .calDAV, source.title == "iCloud" { return 0 }
        if source.sourceType == .exchange { return 2 }
        return 1
    }

    /// Events in [from, to], excluding hidden calendars and meetings the
    /// user declined (spec: declined = gone from list and grid dots).
    ///
    /// Runs the EventKit query on a background queue — Exchange-backed
    /// fetches take hundreds of ms and must never block the main thread
    /// (the popup would visibly stall on open). EKEventStore is documented
    /// thread-safe; the EKEvents stay on the fetch thread, only value-type
    /// `EventItem`s cross back.
    public func events(
        from: Date,
        to: Date,
        hiddenCalendarIDs: Set<String>
    ) async -> [EventItem] {
        guard authState == .authorized else { return [] }
        nonisolated(unsafe) let store = store

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let visible = store.calendars(for: .event)
                    .filter { !hiddenCalendarIDs.contains($0.calendarIdentifier) }
                guard !visible.isEmpty else {
                    continuation.resume(returning: [])
                    return
                }

                let predicate = store.predicateForEvents(
                    withStart: from, end: to, calendars: visible
                )
                let items = store.events(matching: predicate)
                    .filter { !Self.isDeclinedByMe($0) }
                    .map(Self.eventItem(from:))
                continuation.resume(returning: items)
            }
        }
    }

    private nonisolated static func isDeclinedByMe(_ event: EKEvent) -> Bool {
        guard let attendees = event.attendees,
              let me = attendees.first(where: { $0.isCurrentUser }) else {
            return false
        }
        return me.participantStatus == .declined
    }

    private nonisolated static func eventItem(from event: EKEvent) -> EventItem {
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
            isBirthday: event.calendar?.type == .birthday,
            isRecurring: event.hasRecurrenceRules,
            eventIdentifier: baseID,
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
