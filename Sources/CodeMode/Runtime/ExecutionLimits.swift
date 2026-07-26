import Foundation

/// Bounds on how much an execution may accumulate.
///
/// Nothing about a script's *output* was previously capped: the whole result was
/// stringified, copied into a Swift `String`, and re-decoded into a `JSONValue`;
/// every `console.log` was retained and then copied again into any
/// `CodeModeToolError`; and the events `AsyncStream` used unbounded buffering, so
/// a chatty script that the host was not draining buffered without limit. A
/// single script could jetsam an iOS host.
///
/// For an LLM consumer, a truncated result carrying a diagnostic is strictly
/// better than an out-of-memory kill, so every limit here degrades rather than
/// fails.
public struct ExecutionLimits: Sendable, Equatable {
    /// Maximum size of the serialized result, in JSON characters. A larger
    /// result is replaced by a descriptor object carrying a prefix of the JSON.
    public var maxResultCharacters: Int

    /// How much of the oversized JSON to include in that descriptor.
    public var truncatedResultPreviewCharacters: Int

    /// Maximum retained `console.log` entries.
    public var maxLogEntries: Int

    /// Maximum characters retained per log message; longer messages are elided
    /// in the middle, which keeps both the prefix and the tail readable.
    public var maxLogMessageCharacters: Int

    /// Maximum retained diagnostics.
    public var maxDiagnostics: Int

    /// Maximum retained permission events.
    public var maxPermissionEvents: Int

    /// How many executions may hold a thread and a live JavaScriptCore context
    /// at once. Excess executions queue rather than exhausting the GCD thread
    /// pool; the per-execution `timeoutMs` measures the run, not the wait.
    public var maxConcurrentExecutions: Int

    /// Depth of the events `AsyncStream` buffer. A host that stops draining
    /// drops the oldest events rather than growing without bound.
    public var maxBufferedEvents: Int

    public init(
        maxResultCharacters: Int = 1_000_000,
        truncatedResultPreviewCharacters: Int = 4_000,
        maxLogEntries: Int = 1_000,
        maxLogMessageCharacters: Int = 8_000,
        maxDiagnostics: Int = 200,
        maxPermissionEvents: Int = 200,
        maxBufferedEvents: Int = 1_000,
        maxConcurrentExecutions: Int = 8
    ) {
        self.maxResultCharacters = maxResultCharacters
        self.truncatedResultPreviewCharacters = truncatedResultPreviewCharacters
        self.maxLogEntries = maxLogEntries
        self.maxLogMessageCharacters = maxLogMessageCharacters
        self.maxDiagnostics = maxDiagnostics
        self.maxPermissionEvents = maxPermissionEvents
        self.maxBufferedEvents = maxBufferedEvents
        self.maxConcurrentExecutions = maxConcurrentExecutions
    }

    public static let standard = ExecutionLimits()
}
