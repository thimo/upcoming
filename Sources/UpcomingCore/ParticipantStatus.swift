import Foundation

/// EventKit-free mirror of `EKParticipantStatus`, holding the invitation
/// decisions that drive filtering and styling. `CalendarService` maps the
/// EventKit enum onto this once; the rules below stay testable without a
/// live event store.
public enum ParticipantStatus: Equatable {
    case unknown
    case pending
    case accepted
    case declined
    case tentative
    case delegated
    /// Anything EventKit adds later (completed, in-process, …).
    case other

    /// Declined invitations are filtered out of the list and grid dots
    /// entirely (spec). `nil` = the user isn't an attendee (own events),
    /// which is never a decline.
    public static func isDeclined(_ status: ParticipantStatus?) -> Bool {
        status == .declined
    }

    /// Unanswered invitation. Exchange/Google deliver "needs action" as
    /// `.unknown` rather than `.pending` (verified empirically 2026-06-12),
    /// so both count — but only when the user actually appears in the
    /// attendee list (own attendee-less events report no status at all).
    public static func isPending(_ status: ParticipantStatus?) -> Bool {
        switch status {
        case .pending, .unknown: return true
        default: return false
        }
    }

    public static func isTentative(_ status: ParticipantStatus?) -> Bool {
        status == .tentative
    }

    /// Collapse to the four cases the attendee popover renders a glyph for.
    public var attendeeStatus: EventAttendee.Status {
        switch self {
        case .accepted: return .accepted
        case .declined: return .declined
        case .tentative: return .tentative
        default: return .noResponse // pending, unknown, delegated, other
        }
    }
}
