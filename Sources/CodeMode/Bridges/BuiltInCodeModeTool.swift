import Foundation

/// Declarative description of one argument of a built-in tool.
struct BuiltInToolArgument {
    var name: String
    var type: CapabilityArgumentType
    var optional: Bool
    var hint: String
    /// Accepted spellings when the argument is constrained to a closed set;
    /// nil for unconstrained arguments.
    var allowedValues: [String]?

    init(_ name: String, _ type: CapabilityArgumentType, optional: Bool = false, hint: String) {
        self.name = name
        self.type = type
        self.optional = optional
        self.hint = hint
        self.allowedValues = nil
    }

    /// A string argument constrained to a `CodeModeStringEnum`'s accepted
    /// values. The advertised constraint and the decode behavior both come
    /// from the enum, so they cannot drift.
    init<Value: CodeModeStringEnum>(_ name: String, oneOf: Value.Type, optional: Bool = false, hint: String) {
        self.name = name
        self.type = .string
        self.optional = optional
        self.hint = hint
        self.allowedValues = Value.codeModeAllowedValues
    }
}

/// The standard idiom for defining a built-in capability: typed arguments,
/// static metadata, and a handler that receives the invocation context.
///
/// Registration metadata (required/optional argument lists, types, hints, and
/// constraints) is derived from `codeModeArguments`, so what the catalog
/// advertises and what `decode` accepts come from one declaration. Phase 2 of
/// PLAN-registration-macros.md generates `decode` and the argument list with a
/// macro; hand-written and macro-authored tools share this protocol, so
/// migration is incremental.
protocol BuiltInCodeModeTool: Sendable {
    associatedtype Arguments: Sendable

    static var codeModeCapability: CapabilityID { get }
    static var codeModePath: String { get }
    /// Additional JavaScript names routed to this tool (same handler and
    /// metadata), e.g. `apple.calendar.updateEvent` alongside `createEvent`.
    static var codeModeAliasPaths: [String] { get }
    static var codeModeTitle: String { get }
    static var codeModeSummary: String { get }
    static var codeModeTags: [String] { get }
    static var codeModeExample: String { get }
    static var codeModeRequiredPermissions: [PermissionKind] { get }
    static var codeModeArguments: [BuiltInToolArgument] { get }
    static var codeModeResultSummary: String { get }

    func decode(arguments: [String: JSONValue]) throws -> Arguments
    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue
}

extension BuiltInCodeModeTool {
    static var codeModeAliasPaths: [String] { [] }
    static var codeModeRequiredPermissions: [PermissionKind] { [] }
}

extension CapabilityRegistration {
    init<Tool: BuiltInCodeModeTool>(tool: Tool) {
        let arguments = Tool.codeModeArguments
        var allowedStringValues: [String: [String]] = [:]
        for argument in arguments {
            if let allowed = argument.allowedValues {
                allowedStringValues[argument.name] = allowed
            }
        }

        self.init(
            jsNames: [Tool.codeModePath] + Tool.codeModeAliasPaths,
            descriptor: CapabilityDescriptor(
                id: Tool.codeModeCapability,
                title: Tool.codeModeTitle,
                summary: Tool.codeModeSummary,
                tags: Tool.codeModeTags,
                example: Tool.codeModeExample,
                requiredPermissions: Tool.codeModeRequiredPermissions,
                requiredArguments: arguments.filter { $0.optional == false }.map(\.name),
                optionalArguments: arguments.filter(\.optional).map(\.name),
                argumentTypes: Dictionary(uniqueKeysWithValues: arguments.map { ($0.name, $0.type) }),
                argumentHints: Dictionary(uniqueKeysWithValues: arguments.map { ($0.name, $0.hint) }),
                // nil keeps the central defaults table in play for tools without
                // enum-typed arguments while unmigrated capabilities still rely on it.
                argumentConstraints: allowedStringValues.isEmpty
                    ? nil
                    : CapabilityArgumentConstraints(allowedStringValues: allowedStringValues),
                resultSummary: Tool.codeModeResultSummary
            ),
            handler: { rawArguments, context in
                let decoded = try tool.decode(arguments: rawArguments)
                return try tool.call(arguments: decoded, context: context)
            }
        )
    }
}
