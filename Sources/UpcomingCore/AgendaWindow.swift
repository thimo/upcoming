import Foundation

/// Pure window-math for the infinite agenda scroll, factored out of
/// `ContentView` so the perf-critical edge/slice/merge logic can be tested
/// without SwiftUI or EventKit. The view keeps the `@State` and async
/// fetches; this enum only computes *what* to fetch and *how* to merge.
public enum AgendaWindow {
    /// Which direction (if any) a newly-visible day should grow the loaded
    /// window. Returned by `edge(for:)`.
    public enum Extension: Equatable {
        case past
        case future
        case none
    }

    /// The day slice a window extension must fetch, plus the resulting
    /// window bounds. Only the `fetch` slice is queried from EventKit — the
    /// rest of the window is already in memory (the perf invariant).
    public struct Slice: Equatable {
        public let newStart: Date
        public let newEnd: Date
        /// The half-open-ish span to actually fetch ([fetchFrom, fetchTo]).
        /// Events spanning the old boundary come back in both the old and
        /// the new fetch, so callers still dedupe by id (see `merge`).
        public let fetchFrom: Date
        public let fetchTo: Date

        public init(newStart: Date, newEnd: Date, fetchFrom: Date, fetchTo: Date) {
            self.newStart = newStart
            self.newEnd = newEnd
            self.fetchFrom = fetchFrom
            self.fetchTo = fetchTo
        }
    }

    /// Does `day` sit within `thresholdDays` of either window edge, and if
    /// so which way should we extend? The past edge wins ties (it can only
    /// matter when the window is degenerate, but keep it deterministic).
    public static func edge(
        for day: Date,
        windowStart: Date,
        windowEnd: Date,
        thresholdDays: Int,
        calendar: Calendar = .current
    ) -> Extension {
        if let pastEdge = calendar.date(byAdding: .day, value: thresholdDays, to: windowStart),
           day < pastEdge {
            return .past
        }
        if let futureEdge = calendar.date(byAdding: .day, value: -thresholdDays, to: windowEnd),
           day > futureEdge {
            return .future
        }
        return .none
    }

    /// Computes the grown window and the slice to fetch for a given
    /// extension. Returns nil only if date arithmetic overflows (never in
    /// practice). Fetching into the past adds `[newStart, windowStart]`;
    /// into the future adds `[windowEnd, newEnd]`.
    public static func slice(
        intoPast: Bool,
        windowStart: Date,
        windowEnd: Date,
        extendByDays: Int,
        calendar: Calendar = .current
    ) -> Slice? {
        if intoPast {
            guard let newStart = calendar.date(byAdding: .day, value: -extendByDays, to: windowStart)
            else { return nil }
            return Slice(
                newStart: newStart, newEnd: windowEnd,
                fetchFrom: newStart, fetchTo: windowStart
            )
        } else {
            guard let newEnd = calendar.date(byAdding: .day, value: extendByDays, to: windowEnd)
            else { return nil }
            return Slice(
                newStart: windowStart, newEnd: newEnd,
                fetchFrom: windowEnd, fetchTo: newEnd
            )
        }
    }

    /// Merges a freshly-fetched slice into the known events, dropping
    /// anything already loaded (boundary-spanning events arrive twice).
    /// Preserves `existing` order; new events keep their fetch order.
    public static func merge(existing: [EventItem], delta: [EventItem]) -> [EventItem] {
        let known = Set(existing.map(\.id))
        return existing + delta.filter { !known.contains($0.id) }
    }
}
