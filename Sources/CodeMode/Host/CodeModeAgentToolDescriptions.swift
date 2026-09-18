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
    public static let searchJavaScriptAPIParameterSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "code": .object([
                "type": .string("string"),
                "description": .string("JavaScript source that evaluates to an async function and returns JSON-serializable catalog output."),
            ]),
        ]),
        "required": .array([.string("code")]),
        "additionalProperties": .bool(false),
    ])

    public static let executeJavaScriptParameterSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "code": .object([
                "type": .string("string"),
                "description": .string("JavaScript body to execute. Use an explicit top-level return for multi-statement outputs; a bare final top-level await expression also returns that awaited value."),
            ]),
            "allowedCapabilities": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("string"),
                ]),
                "description": .string("Built-in capability IDs required by the JavaScript, for example fs.read or calendar.write. Use an empty array when no built-in capabilities are needed."),
            ]),
            "allowedCapabilityKeys": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("string"),
                ]),
                "description": .string("Custom provider capability keys required by the JavaScript, for example myapp.tasks.complete. Built-in capability IDs do not belong here and are ignored — list those in allowedCapabilities."),
            ]),
            "timeoutMs": .object([
                "type": .string("integer"),
                "minimum": .number(1),
                "maximum": .number(60_000),
                "description": .string("Optional execution timeout in milliseconds. Defaults to 10000."),
            ]),
        ]),
        "required": .array([.string("code"), .string("allowedCapabilities")]),
        "additionalProperties": .bool(false),
    ])

    public static let searchJavaScriptAPI = CodeModeAgentToolDescription(
        name: "searchJavaScriptAPI",
        description: """
        Search the bundled CodeMode JavaScript API catalog by executing an async JavaScript function against a preloaded api object. Use this before executeJavaScript to discover the correct JS helper names, capability IDs, required arguments, result shapes, and examples. The catalog is filtered to the current host platform, so unsupported helpers are hidden.

        Available in your search code:
        interface JavaScriptAPIReference {
          capability: string;
          capabilityKey: string;
          builtInCapability: string | null;
          jsNames: string[];
          summary: string;
          tags: string[];
          example: string;
          requiredArguments: string[];
          optionalArguments: string[];
          argumentTypes: Record<string, string>;
          argumentHints: Record<string, string>;
          argumentConstraints: { allowedStringValues: Record<string, string[]> };
          resultSummary: string;
          dts: string;
        }

        declare const api: {
          references: JavaScriptAPIReference[];
          byCapability: Record<string, JavaScriptAPIReference>;
          byJSName: Record<string, JavaScriptAPIReference>;
        };

        Your code must evaluate to an async function and return JSON-serializable output.
        Search has a 2s budget, so slice broad result sets before returning them.

        Prefer returning ref.dts: it is the TypeScript declaration for the helper, with argument names, types, string-literal unions for constrained values, optionality, and the result summary. It is more precise and usually shorter than assembling argumentTypes, argumentHints, and argumentConstraints yourself.

        Examples:
        async () => {
          return api.references
            .filter(ref => ref.tags.includes("reminders"))
            .slice(0, 10)
            .map(ref => ({
              capability: ref.capability,
              capabilityKey: ref.capabilityKey,
              builtInCapability: ref.builtInCapability,
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
          return api.byJSName["apple.fs.read"].dts;
        }

        async () => {
          return api.references
            .filter(ref => ref.tags.includes("calendar"))
            .map(ref => ref.dts)
            .join("\n\n");
        }
        """
    )

    public static let executeJavaScript = CodeModeAgentToolDescription(
        name: "executeJavaScript",
        description: """
        Execute JavaScript against the CodeMode runtime. Use one call to run a whole task — read, loop, branch, filter, transform, write — and return only the finished answer. Many helper calls inside one script is the intended shape; many executeJavaScript calls that each make one helper call is not, because every round trip costs a turn and pushes intermediate data through your context. Prefer searchJavaScriptAPI first when choosing helpers or arguments. Cross-platform helpers live under apple.* and platform-specific helpers live under platform namespaces such as ios.alarm.*; custom host providers may expose additional namespaces. System UI helpers such as apple.ui.presentAlert, apple.calendar.presentNewEvent, apple.photos.pick, apple.contacts.pick, apple.documents.pick, apple.share.present, apple.quicklook.preview, apple.web.present, and apple.auth.webAuthenticate require a host-provided SystemUIPresenter; camera, document scan, mail, and message compose helpers are iOS-only. Only helpers supported on the current host platform are installed.

        Calling conventions: apple.* and other namespaced helpers take one object argument, for example apple.fs.read({ path: "tmp:file.txt" }) and often return structured objects such as { text, base64 }. Node-style filesystem aliases under fs.promises.* use positional arguments, for example fs.promises.readFile("tmp:file.txt", "utf8"), and return Node-like values such as a string for readFile. When in doubt, use the ref.dts from searchJavaScriptAPI — it states the exact signature. fetch(url, options) is a global helper and returns a Response-like object with text(), json(), headers.get(), status, and ok.

        Return semantics: the runtime wraps your code in an async function. For multi-statement code, return the final graded value with an explicit top-level return statement. A script that is only a bare final top-level await expression, such as await apple.fs.read({ path: "tmp:file.txt" }), returns that awaited value. Do not use an unreturned async IIFE as the final expression.

        Examples. Do the whole job in one script and return the graded answer, not the raw data you read:

        const start = new Date().toISOString();
        const end = new Date(Date.now() + 7 * 86400000).toISOString();
        const events = await apple.calendar.listEvents({ start, end });
        const conflicts = events.filter((event, index) =>
          events.slice(index + 1).some(other => other.startDate < event.endDate)
        );
        return { total: events.length, conflicts: conflicts.map(event => event.title) };

        Prefer one call that takes a collection over a loop of single calls — check the catalog for a plural argument before writing the loop:

        const contacts = await apple.contacts.list({ identifiers: ids });

        When the work genuinely is per-item, keep going after a failure and report what happened:

        const results = [];
        for (const city of cities) {
          try {
            const response = await fetch(`https://api.example.com/weather/${city}`);
            results.push({ city, ok: response.ok, data: response.ok ? await response.json() : null });
          } catch (error) {
            results.push({ city, error: String(error) });
          }
        }
        return results;

        Concurrency: setTimeout and clearTimeout work normally — callbacks are deferred and delays are honoured, so `await new Promise(r => setTimeout(r, 1000))` really waits. There is no I/O event loop, though: native calls run one at a time, so Promise.all over several helpers completes them sequentially rather than concurrently. A promise with no resolve path and no pending timer can never settle and fails fast with JS_RUNTIME_ERROR rather than running out the clock.

        Allowlisting: request the exact set of capabilities your script calls and nothing more — a capability you list but never use is a wider grant than the task needs, and hosts that enforce a ceiling will refuse it. Built-in capability IDs go in allowedCapabilities; custom provider keys go in allowedCapabilityKeys. The two fields are not interchangeable: a built-in capability listed in allowedCapabilityKeys is ignored. These fields declare what your script needs; the host app applies its own ceiling on top, so a capability you list may still be withheld. Execution defaults to a 10000ms timeout and returns structured CodeModeToolError failures for syntax errors, missing JS helpers, runtime throws, validation failures, permission denials, timeouts, cancellation, and internal errors.

        Error repair guide:
        JS_API_NOT_FOUND: use the suggested JS helper names or searchJavaScriptAPI.
        CAPABILITY_DENIED: add the exact capability to allowedCapabilities (built-ins) or allowedCapabilityKeys (custom provider keys) and retry — unless the error suggestions say the host withheld it, in which case retrying will not help.
        PERMISSION_DENIED: the capability is allowlisted but the OS, host, or custom provider denied permission; request permission if a helper exists, otherwise tell the user or host.
        UI_PRESENTER_UNAVAILABLE: host configuration issue; do not retry the same call.
        INVALID_ARGUMENTS: use the catalog requiredArguments, optionalArguments, argumentHints, and example.
        NETWORK_POLICY_VIOLATION: the host's network access policy refused the destination; do not retry the same URL and do not add capabilities to work around it.
        JS_RUNTIME_ERROR "can never settle": a promise in your script has no resolve path; await every promise and make sure each one resolves.

        Warning diagnostics worth acting on:
        BRIDGE_FAILURES_NOT_SURFACED: a helper failed but your script still returned successfully — usually a missing await, which discards the rejection.
        RESULT_TRUNCATED: the return value exceeded the size limit; return a summary or write the payload to the sandbox and return the path.
        TIMER_CALLBACK_ERROR: a setTimeout callback threw; its error cannot reach the caller, so handle it inside the callback.
        """
    )

    public static let all: [CodeModeAgentToolDescription] = [
        searchJavaScriptAPI,
        executeJavaScript,
    ]
}
