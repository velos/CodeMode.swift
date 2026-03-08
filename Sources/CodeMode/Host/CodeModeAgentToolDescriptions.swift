import Foundation

public struct CodeModeAgentToolDescription: Sendable, Codable, Equatable {
    public var name: String
    public var description: String

    public init(name: String, description: String) {
        self.name = name
        self.description = description
    }
}

public enum CodeModeAgentToolDescriptions {
    public static let searchJavaScriptAPI = CodeModeAgentToolDescription(
        name: "searchJavaScriptAPI",
        description: """
        Search the bundled CodeMode JavaScript API surface before executing code. Use this to discover the correct JS helper names, capability IDs, arguments, and examples. Pass a natural-language query such as "create reminder", "read file", "request location permission", or "turn off light", or provide an exact capability for direct lookup. Prefer this tool whenever you are not already certain which CodeMode helper to call. Empty queries are invalid unless capability is provided.
        """
    )

    public static let executeJavaScript = CodeModeAgentToolDescription(
        name: "executeJavaScript",
        description: """
        Execute JavaScript against the CodeMode runtime. Prefer searchJavaScriptAPI first when choosing helpers or arguments. Return the final value you want from the script and include only the required capabilities in allowedCapabilities. Execution streams logs and diagnostics and returns structured CodeModeToolError failures for syntax errors, missing JS helpers, runtime throws, validation failures, permission denials, timeouts, cancellation, and internal errors.
        """
    )

    public static let all: [CodeModeAgentToolDescription] = [
        searchJavaScriptAPI,
        executeJavaScript,
    ]
}
