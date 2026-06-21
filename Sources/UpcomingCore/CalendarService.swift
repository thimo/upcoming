import AppKit
import CoreLocation
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
        ParticipantStatus.isDeclined(myParticipantStatus(event))
    }

    /// The current user's participation, mapped to the EventKit-free enum.
    /// `nil` when the user isn't an attendee (own attendee-less events).
    private nonisolated static func myParticipantStatus(_ event: EKEvent) -> ParticipantStatus? {
        guard let attendees = event.attendees,
              let me = attendees.first(where: { $0.isCurrentUser }) else {
            return nil
        }
        return ParticipantStatus(me.participantStatus)
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
            isPendingInvitation: ParticipantStatus.isPending(myParticipantStatus(event)),
            isTentative: ParticipantStatus.isTentative(myParticipantStatus(event)),
            eventIdentifier: baseID,
            location: event.location?.trimmingCharacters(in: .whitespacesAndNewlines),
            videoCallURL: VideoCallDetector.detect(
                url: event.url,
                location: event.location,
                notes: event.notes
            ),
            notes: event.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            url: event.url,
            attendees: attendees(from: event),
            alertText: alertText(from: event),
            recurrenceText: recurrenceText(from: event),
            latitude: event.structuredLocation?.geoLocation?.coordinate.latitude,
            longitude: event.structuredLocation?.geoLocation?.coordinate.longitude
        )
    }

    // MARK: - Popover field mapping

    /// Attendee list for the detail popover: organiser first (synthesised
    /// from `event.organizer` if it isn't in the attendee array), then the
    /// rest in EventKit order. Birthday/holiday-style events have no
    /// attendees and return [].
    private nonisolated static func attendees(from event: EKEvent) -> [EventAttendee] {
        let participants = event.attendees ?? []
        // A lone attendee that is just the current user (own events Exchange
        // sometimes tags) isn't worth a list.
        guard participants.count > 1 || event.organizer != nil else { return [] }

        let organizerURL = event.organizer?.url
        var result: [EventAttendee] = participants.map { p in
            EventAttendee(
                name: displayName(p),
                status: ParticipantStatus(p.participantStatus).attendeeStatus,
                isOrganizer: p.url == organizerURL,
                isOptional: p.participantRole == .optional
            )
        }
        // Organiser is often not listed among the attendees; prepend it.
        if let organizer = event.organizer, !result.contains(where: { $0.isOrganizer }) {
            result.insert(
                EventAttendee(
                    name: displayName(organizer),
                    status: .accepted,
                    isOrganizer: true
                ),
                at: 0
            )
        }
        return result
    }

    private nonisolated static func displayName(_ participant: EKParticipant) -> String {
        if let name = participant.name, !name.isEmpty { return name }
        // Fall back to the email from the mailto: URL.
        let url = participant.url.absoluteString
        return url.hasPrefix("mailto:") ? String(url.dropFirst("mailto:".count)) : url
    }


    /// First alarm rendered as Apple's "Alert …" line. Relative offsets
    /// become "N minutes/hours before start" (0 → "at time of event");
    /// absolute alarms become a date. Location/proximity alarms are skipped.
    private nonisolated static func alertText(from event: EKEvent) -> String? {
        guard let alarm = event.alarms?.first, alarm.structuredLocation == nil else { return nil }
        if let absolute = alarm.absoluteDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return "Alert on \(formatter.string(from: absolute))"
        }
        let offset = alarm.relativeOffset
        if offset == 0 { return "Alert at time of event" }
        let before = offset < 0
        let magnitude = Int(abs(offset))
        return "Alert \(durationPhrase(seconds: magnitude)) \(before ? "before start" : "after start")"
    }

    /// "15 minutes", "1 hour", "2 days", … for the alert line.
    private nonisolated static func durationPhrase(seconds: Int) -> String {
        let units: [(Int, String)] = [(86_400, "day"), (3_600, "hour"), (60, "minute")]
        for (size, name) in units where seconds % size == 0 && seconds >= size {
            let count = seconds / size
            return "\(count) \(name)\(count == 1 ? "" : "s")"
        }
        return "\(seconds) second\(seconds == 1 ? "" : "s")"
    }

    /// Apple-style natural-language recurrence for the common rules
    /// (daily/weekly/monthly/yearly + interval + weekly day list).
    /// Exotic rules fall back to a bare "Repeats".
    private nonisolated static func recurrenceText(from event: EKEvent) -> String? {
        guard let rule = event.recurrenceRules?.first else { return nil }
        let interval = max(rule.interval, 1)

        let unit: String
        switch rule.frequency {
        case .daily: unit = "day"
        case .weekly: unit = "week"
        case .monthly: unit = "month"
        case .yearly: unit = "year"
        @unknown default: return "Repeats"
        }

        var text: String
        if interval == 1 {
            text = "Repeats every \(unit)"
        } else {
            text = "Repeats every \(interval) \(unit)s"
        }

        if rule.frequency == .weekly, let days = rule.daysOfTheWeek, !days.isEmpty {
            let names = days
                .map(\.dayOfTheWeek)
                .sorted { $0.rawValue < $1.rawValue }
                .map { weekdayName($0) }
            text += " on \(listPhrase(names))"
        }
        return text
    }

    private nonisolated static func weekdayName(_ day: EKWeekday) -> String {
        let symbols = Calendar.current.standaloneWeekdaySymbols // Sunday-first
        let index = day.rawValue - 1 // EKWeekday.sunday == 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }

    /// "Monday", "Monday and Thursday", "Monday, Wednesday and Friday".
    private nonisolated static func listPhrase(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return "\(items.dropLast().joined(separator: ", ")) and \(items.last!)"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension ParticipantStatus {
    /// Bridge EventKit's enum to the testable mirror. `@unknown` future
    /// cases collapse to `.other` (treated as no-response everywhere).
    init(_ status: EKParticipantStatus) {
        switch status {
        case .unknown: self = .unknown
        case .pending: self = .pending
        case .accepted: self = .accepted
        case .declined: self = .declined
        case .tentative: self = .tentative
        case .delegated: self = .delegated
        case .completed, .inProcess: self = .other
        @unknown default: self = .other
        }
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
