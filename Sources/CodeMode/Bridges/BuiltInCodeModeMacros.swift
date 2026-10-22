import Foundation

/// Generates the mechanical members of a `BuiltInCodeModeTool` — the identity
/// statics, `codeModeArguments`, and `decode(arguments:)` — from the nested
/// `Arguments` struct. Curated metadata (title, summary, tags, example,
/// permissions, result summary) and `call(arguments:context:)` stay
/// hand-written.
///
/// Annotate each argument property with `@ToolParam("hint")`. Property types
/// may be JSON primitives (`String`, `Bool`, `Int`, `Double`, `[JSONValue]`,
/// `[String: JSONValue]`, `JSONValue`, optionals thereof) or a
/// `CodeModeStringEnum`, whose accepted values become the argument's
/// constraint metadata. `Date`/`Date?` decode ISO 8601 strings through
/// `CodeModeDate`, retaining the capability and argument in date errors.
/// Nonoptional scalar properties may have literal defaults (or `.case` enum
/// defaults): omission uses the initializer, and catalog hints advertise it.
/// Dynamic defaults belong in `call` and use optional properties.
///
/// An unannotated `var providedArguments: Set<String>` receives the supplied
/// keys, so patch tools can distinguish omission from explicit null without
/// retaining raw values. A trailing unannotated `var raw: [String: JSONValue]`
/// receives the full argument dictionary with constrained values canonicalized
/// — the passthrough transitional tools use while bridges consume raw
/// dictionaries.
@attached(member, names: named(codeModeCapability), named(codeModePath), named(codeModeAliasPaths), named(codeModeArguments), named(decode))
macro BuiltInCodeMode(
    _ capability: CapabilityID,
    path: String,
    aliases: [String] = []
) = #externalMacro(module: "CodeModeMacros", type: "BuiltInCodeModeMacro")

/// Marks one argument property of a `@BuiltInCodeMode` tool and carries its
/// LLM-facing hint.
@attached(peer)
macro ToolParam(_ hint: String) = #externalMacro(module: "CodeModeMacros", type: "ToolParamMacro")

/// Helpers referenced by `@BuiltInCodeMode`-generated `decode` implementations.
enum CodeModeToolRawArguments {
    /// Replaces a constrained value in the raw passthrough dictionary with its
    /// canonical spelling, so bridges parsing the raw dictionary see exactly
    /// the advertised form.
    static func canonicalize<Value: CodeModeStringEnum>(_ raw: inout [String: JSONValue], _ name: String, _ value: Value?) {
        if let value {
            raw[name] = .string(value.rawValue)
        }
    }

    static func canonicalize<Value: CodeModeStringEnum>(_ raw: inout [String: JSONValue], _ name: String, _ value: Value) {
        raw[name] = .string(value.rawValue)
    }
}
