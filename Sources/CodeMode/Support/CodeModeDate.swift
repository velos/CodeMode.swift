import Foundation

/// The single ISO 8601 parser for every bridge.
///
/// Two spellings were previously in circulation: Health and Alarm tried
/// `.withFractionalSeconds` as a fallback, while EventKit, Notifications, and the
/// system-UI validators used a bare `ISO8601DateFormatter`. So
/// `2026-07-24T10:00:00.000Z` — a spelling models emit constantly, and what
/// `Date.toISOString()` produces in JavaScript — parsed in some bridges and not
/// others.
enum CodeModeDate {
    /// Parses an ISO 8601 timestamp with or without fractional seconds.
    static func parse(_ text: String?) -> Date? {
        guard let text else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: trimmed) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: trimmed)
    }

    /// Parses a timestamp that the caller requires, throwing a repairable error
    /// rather than substituting a default.
    ///
    /// Silently falling back to "now" (or "now + 14 days") gave the script a
    /// plausible but wrong window with no diagnostic — the worst failure mode
    /// available, because the model has no way to notice it happened.
    static func require(_ text: String?, argument: String, capability: String) throws -> Date {
        guard let text, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw BridgeError.invalidArguments("\(capability) requires '\(argument)'")
        }
        guard let date = parse(text) else {
            throw BridgeError.invalidArguments(
                "\(capability) could not parse '\(argument)' as an ISO 8601 timestamp: \"\(text)\". Use a form like 2026-07-24T10:00:00Z."
            )
        }
        return date
    }

    /// Parses an optional timestamp, throwing when a value is present but
    /// unparseable. A missing value returns nil and the caller's default applies.
    static func optional(_ text: String?, argument: String, capability: String) throws -> Date? {
        guard let text, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        return try require(text, argument: argument, capability: capability)
    }

    static func string(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
