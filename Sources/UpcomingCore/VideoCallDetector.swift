import Foundation

/// Finds a joinable video-call link in an event's URL, location, or notes
/// (checked in that order). Used for the row video icon and, later, the
/// notification join action — one detector, two surfaces.
public enum VideoCallDetector {
    /// Host/path fragments that mark a URL as a meeting join link.
    /// Substring match against the absolute URL string.
    private static let patterns: [String] = [
        "teams.microsoft.com/l/meetup-join",
        "teams.live.com/meet",
        "zoom.us/j/",
        "zoom.us/my/",
        "meet.google.com/",
        "webex.com/meet",
        "webex.com/join",
        "whereby.com/",
        "meet.jit.si/",
        "facetime.apple.com/join",
    ]

    public static func detect(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, isCallLink(url) { return url }
        for text in [location, notes] {
            guard let text else { continue }
            if let found = firstCallLink(in: text) { return found }
        }
        return nil
    }

    private static func isCallLink(_ url: URL) -> Bool {
        let s = url.absoluteString
        return patterns.contains { s.contains($0) }
    }

    private static func firstCallLink(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            if let url = match.url, isCallLink(url) { return url }
        }
        return nil
    }
}
