import CodeMode
import Foundation

private enum CLIError: LocalizedError {
    case usage(String)
    case invalidValue(flag: String, value: String)

    var errorDescription: String? {
        switch self {
        case let .usage(message):
            return message
        case let .invalidValue(flag, value):
            return "Invalid value for \(flag): \(value)"
        }
    }
}

private struct CLIExecutionEvent: Codable {
    var type: String
    var log: ExecutionLog?
    var diagnostic: ToolDiagnostic?
    var error: CodeModeToolError?
}

private struct CLIExecutionResponse: Codable {
    var events: [CLIExecutionEvent]
    var result: JavaScriptExecutionResult?
    var error: CodeModeToolError?
}

@main
struct CodeModeEvalCLI {
    static func main() async {
        do {
            try await run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            fputs("codemode-eval: \(error.localizedDescription)\n", stderr)
            exit(2)
        }
    }

    private static func run(arguments: [String]) async throws {
        guard let command = arguments.first else {
            throw CLIError.usage(usage())
        }

        let tools = CodeModeAgentTools()
        let parsed = try parseFlags(Array(arguments.dropFirst()))

        switch command {
        case "search":
            let query = parsed["query"] ?? parsed["_arg0"]
            let capability = try parseCapability(parsed["capability"])
            let tags = parseCSV(parsed["tags"])
            let limit = try parseInt(parsed["limit"], flag: "--limit") ?? 8
            let request = JavaScriptAPISearchRequest(
                query: query,
                capability: capability,
                tags: tags,
                limit: limit
            )
            let response = try await tools.searchJavaScriptAPI(request)
            try printJSON(response)

        case "execute":
            guard let code = parsed["code"] ?? parsed["_arg0"] else {
                throw CLIError.usage("execute requires --code <javascript>\n\n\(usage())")
            }

            let timeoutMs = try parseInt(parsed["timeout"], flag: "--timeout") ?? 10_000
            let allowedCapabilities = try parseCapabilities(parsed["allow"])
            let context = ExecutionContext(
                userID: parsed["user-id"],
                sessionID: parsed["session-id"]
            )

            let request = JavaScriptExecutionRequest(
                code: code,
                allowedCapabilities: allowedCapabilities,
                timeoutMs: timeoutMs,
                context: context
            )

            let call = try await tools.executeJavaScript(request)
            let eventsTask = Task { await collectEvents(from: call) }

            let result: JavaScriptExecutionResult?
            let error: CodeModeToolError?
            do {
                result = try await call.result
                error = nil
            } catch let toolError as CodeModeToolError {
                result = nil
                error = toolError
            }

            let response = CLIExecutionResponse(events: await eventsTask.value, result: result, error: error)
            try printJSON(response)

        default:
            throw CLIError.usage(usage())
        }
    }

    private static func collectEvents(from call: JavaScriptExecutionCall) async -> [CLIExecutionEvent] {
        var events: [CLIExecutionEvent] = []
        for await event in call.events {
            switch event {
            case let .log(entry):
                events.append(CLIExecutionEvent(type: "log", log: entry, diagnostic: nil, error: nil))
            case let .diagnostic(diagnostic):
                events.append(CLIExecutionEvent(type: "diagnostic", log: nil, diagnostic: diagnostic, error: nil))
            case let .syntaxError(error):
                events.append(CLIExecutionEvent(type: "syntaxError", log: nil, diagnostic: nil, error: error))
            case let .functionNotFound(error):
                events.append(CLIExecutionEvent(type: "functionNotFound", log: nil, diagnostic: nil, error: error))
            case let .thrownError(error):
                events.append(CLIExecutionEvent(type: "thrownError", log: nil, diagnostic: nil, error: error))
            case let .toolError(error):
                events.append(CLIExecutionEvent(type: "toolError", log: nil, diagnostic: nil, error: error))
            case .finished:
                events.append(CLIExecutionEvent(type: "finished", log: nil, diagnostic: nil, error: nil))
            }
        }
        return events
    }

    private static func parseFlags(_ arguments: [String]) throws -> [String: String] {
        var values: [String: String] = [:]
        var positionalIndex = 0
        var index = 0

        while index < arguments.count {
            let token = arguments[index]
            if token.hasPrefix("--") {
                let key = String(token.dropFirst(2))
                let nextIndex = index + 1
                guard nextIndex < arguments.count else {
                    throw CLIError.usage("Missing value for --\(key)")
                }
                values[key] = arguments[nextIndex]
                index += 2
            } else {
                values["_arg\(positionalIndex)"] = token
                positionalIndex += 1
                index += 1
            }
        }

        return values
    }

    private static func parseCSV(_ raw: String?) -> [String] {
        guard let raw else {
            return []
        }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    private static func parseCapability(_ raw: String?) throws -> CapabilityID? {
        guard let raw, raw.isEmpty == false else {
            return nil
        }
        guard let capability = CapabilityID(rawValue: raw) else {
            throw CLIError.invalidValue(flag: "--capability", value: raw)
        }
        return capability
    }

    private static func parseCapabilities(_ raw: String?) throws -> [CapabilityID] {
        let tokens = parseCSV(raw)
        var capabilities: [CapabilityID] = []

        for token in tokens {
            guard let capability = CapabilityID(rawValue: token) else {
                throw CLIError.invalidValue(flag: "--allow", value: token)
            }
            capabilities.append(capability)
        }

        return capabilities
    }

    private static func parseInt(_ raw: String?, flag: String) throws -> Int? {
        guard let raw else {
            return nil
        }
        guard let value = Int(raw) else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return value
    }

    private static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CLIError.usage("Failed to encode JSON output")
        }
        print(text)
    }

    private static func usage() -> String {
        """
        Usage:
          codemode-eval search --query <text> [--tags a,b] [--limit n]
          codemode-eval search --capability <capability.id>
          codemode-eval execute --code <javascript> [--allow cap1,cap2] [--timeout ms] [--user-id id] [--session-id id]
        """
    }
}
