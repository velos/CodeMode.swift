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
        Search the bundled CodeMode JavaScript API catalog by executing an async JavaScript function against a preloaded api object. Use this before executeJavaScript to discover the correct JS helper names, capability IDs, required arguments, result shapes, and examples. The catalog is filtered to the current host platform, so unsupported helpers are hidden.

        Available in your search code:
        interface JavaScriptAPIReference {
          capability: string;
          jsNames: string[];
          summary: string;
          tags: string[];
          example: string;
          requiredArguments: string[];
          optionalArguments: string[];
          argumentTypes: Record<string, string>;
          argumentHints: Record<string, string>;
          resultSummary: string;
        }

        declare const api: {
          references: JavaScriptAPIReference[];
          byCapability: Record<string, JavaScriptAPIReference>;
          byJSName: Record<string, JavaScriptAPIReference>;
        };

        Your code must evaluate to an async function and return JSON-serializable output.

        Examples:
        async () => {
          return api.references
            .filter(ref => ref.tags.includes("reminders"))
            .map(ref => ({
              capability: ref.capability,
              jsNames: ref.jsNames,
              summary: ref.summary,
              requiredArguments: ref.requiredArguments,
              optionalArguments: ref.optionalArguments,
              argumentHints: ref.argumentHints,
              resultSummary: ref.resultSummary,
              example: ref.example
            }));
        }

        async () => {
          return api.byJSName["apple.fs.read"];
        }
        """
    )

    public static let executeJavaScript = CodeModeAgentToolDescription(
        name: "executeJavaScript",
        description: """
        Execute JavaScript against the CodeMode runtime. Prefer searchJavaScriptAPI first when choosing helpers or arguments. Cross-platform helpers live under apple.* and platform-specific helpers live under platform namespaces such as ios.alarm.*. Only helpers supported on the current host platform are installed. The runtime already wraps your code in an async function, so use top-level await directly and return the final value with an explicit top-level return statement; do not use an unreturned async IIFE as the final expression. Include only the required capabilities in allowedCapabilities. Execution streams logs and diagnostics and returns structured CodeModeToolError failures for syntax errors, missing JS helpers, runtime throws, validation failures, permission denials, timeouts, cancellation, and internal errors.
        """
    )

    public static let all: [CodeModeAgentToolDescription] = [
        searchJavaScriptAPI,
        executeJavaScript,
    ]
}
