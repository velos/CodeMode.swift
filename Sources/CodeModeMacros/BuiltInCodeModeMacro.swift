import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// No-op marker carrying the LLM-facing hint for one argument of a built-in
/// tool; `@BuiltInCodeMode` reads it while generating `codeModeArguments`.
public struct ToolParamMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

/// Generates the mechanical members of a `BuiltInCodeModeTool` from its nested
/// `Arguments` struct: identity statics (`codeModeCapability`, `codeModePath`,
/// `codeModeAliasPaths`), the `codeModeArguments` metadata list, and
/// `decode(arguments:)`. Curated metadata (title, summary, tags, example,
/// permissions, result summary) and `call(arguments:context:)` stay
/// hand-written.
///
/// Field types the macro does not recognize as JSON primitives are emitted
/// through `CodeModeStringEnum`-constrained overloads
/// (`BuiltInToolArgument(_:oneOf:...)`, `CodeModeToolRawArguments.canonicalize`),
/// so the compiler — not the macro — enforces that such a type really is a
/// `CodeModeStringEnum`, and the constraint metadata is derived from the enum.
///
/// A stored property `var raw: [String: JSONValue]` without `@ToolParam` is
/// filled with the full argument dictionary, with constrained values replaced
/// by their canonical spelling — the passthrough transitional tools use while
/// bridges still consume raw dictionaries.
public struct BuiltInCodeModeMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              let capabilityExpr = arguments.first(where: { $0.label == nil })?.expression.trimmedDescription,
              let pathExpr = arguments.first(where: { $0.label?.text == "path" })?.expression.trimmedDescription
        else {
            context.diagnose(BuiltInMacroDiagnostic("@BuiltInCodeMode requires a capability and a path", node: Syntax(node)))
            return []
        }
        let aliasesExpr = arguments.first(where: { $0.label?.text == "aliases" })?.expression.trimmedDescription

        guard let argumentsStruct = declaration.memberBlock.members
            .compactMap({ $0.decl.as(StructDeclSyntax.self) })
            .first(where: { $0.name.text == "Arguments" })
        else {
            context.diagnose(BuiltInMacroDiagnostic("@BuiltInCodeMode requires a nested Arguments struct", node: Syntax(declaration)))
            return []
        }

        guard let parsed = parseFields(of: argumentsStruct, context: context) else {
            return []
        }

        var members: [String] = [
            "static let codeModeCapability: CapabilityID = \(capabilityExpr)",
            "static let codeModePath: String = \(pathExpr)",
        ]
        if let aliasesExpr {
            members.append("static let codeModeAliasPaths: [String] = \(aliasesExpr)")
        }
        members.append(argumentsMetadataSource(for: parsed.fields))
        members.append(decodeSource(for: parsed))

        return members.map { DeclSyntax(stringLiteral: $0) }
    }

    // MARK: Field parsing

    private struct ParsedArguments {
        var fields: [Field]
        var hasRawPassthrough: Bool
    }

    private struct Field {
        var name: String
        var swiftType: String
        var kind: FieldKind
        var optional: Bool
        var hint: String
    }

    fileprivate enum FieldKind {
        /// A JSON primitive or collection with a direct CapabilityArgumentType.
        case primitive(String)
        /// An unrecognized simple type, emitted through the
        /// CodeModeStringEnum-constrained overloads.
        case stringEnum
    }

    private static func parseFields(
        of argumentsStruct: StructDeclSyntax,
        context: some MacroExpansionContext
    ) -> ParsedArguments? {
        var fields: [Field] = []
        var hasRawPassthrough = false
        var rawIsLast = true
        var invalid = false

        for member in argumentsStruct.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else {
                continue
            }
            guard variable.bindings.count == 1,
                  let binding = variable.bindings.first,
                  binding.accessorBlock == nil
            else {
                context.diagnose(BuiltInMacroDiagnostic("@BuiltInCodeMode supports only simple stored properties in Arguments", node: Syntax(variable)))
                invalid = true
                continue
            }
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                  let type = binding.typeAnnotation?.type.trimmedDescription
            else {
                context.diagnose(BuiltInMacroDiagnostic("@BuiltInCodeMode Arguments properties need a name and an explicit type", node: Syntax(binding)))
                invalid = true
                continue
            }

            let name = identifier.identifier.text
            let hint = toolParamHint(on: variable.attributes)

            if hint == nil, name == "raw" {
                guard type.replacingOccurrences(of: " ", with: "") == "[String:JSONValue]" else {
                    context.diagnose(BuiltInMacroDiagnostic("@BuiltInCodeMode raw passthrough must be [String: JSONValue]", node: Syntax(binding)))
                    invalid = true
                    continue
                }
                hasRawPassthrough = true
                rawIsLast = true
                continue
            }
            rawIsLast = false

            guard let hint else {
                context.diagnose(BuiltInMacroDiagnostic("@BuiltInCodeMode Arguments properties need @ToolParam(\"hint\") (or be the raw passthrough)", node: Syntax(binding)))
                invalid = true
                continue
            }

            let info = BuiltInTypeInfo(typeSyntax: type)
            fields.append(
                Field(
                    name: name,
                    swiftType: info.unwrappedType,
                    kind: info.kind,
                    optional: info.optional,
                    hint: hint
                )
            )
        }

        if hasRawPassthrough, rawIsLast == false {
            // decode constructs Arguments with the memberwise initializer, so the
            // passthrough must be the last stored property.
            context.diagnose(BuiltInMacroDiagnostic("@BuiltInCodeMode raw passthrough must be the last stored property of Arguments", node: Syntax(argumentsStruct.name)))
            return nil
        }

        return invalid ? nil : ParsedArguments(fields: fields, hasRawPassthrough: hasRawPassthrough)
    }

    private static func toolParamHint(on attributes: AttributeListSyntax) -> String? {
        for element in attributes {
            guard case let .attribute(attribute) = element,
                  attribute.attributeName.trimmedDescription == "ToolParam",
                  let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
                  let first = arguments.first,
                  let literal = first.expression.as(StringLiteralExprSyntax.self)
            else {
                continue
            }
            return literal.segments.compactMap { segment in
                segment.as(StringSegmentSyntax.self)?.content.text
            }.joined()
        }
        return nil
    }

    // MARK: Code generation

    private static func argumentsMetadataSource(for fields: [Field]) -> String {
        guard fields.isEmpty == false else {
            return "static let codeModeArguments: [BuiltInToolArgument] = []"
        }
        let entries = fields.map { field -> String in
            let optionalPart = field.optional ? ", optional: true" : ""
            switch field.kind {
            case let .primitive(argumentType):
                return "BuiltInToolArgument(\(stringLiteral(field.name)), .\(argumentType)\(optionalPart), hint: \(stringLiteral(field.hint))),"
            case .stringEnum:
                return "BuiltInToolArgument(\(stringLiteral(field.name)), oneOf: \(field.swiftType).self\(optionalPart), hint: \(stringLiteral(field.hint))),"
            }
        }.joined(separator: "\n    ")
        return """
        static let codeModeArguments: [BuiltInToolArgument] = [
            \(entries)
        ]
        """
    }

    private static func decodeSource(for parsed: ParsedArguments) -> String {
        var body: [String] = []
        let enumFields = parsed.fields.filter {
            if case .stringEnum = $0.kind { return true }
            return false
        }

        if parsed.hasRawPassthrough {
            body.append(enumFields.isEmpty ? "let raw = arguments" : "var raw = arguments")
        }
        for field in parsed.fields {
            let method = field.optional ? "optional" : "require"
            body.append("let \(field.name) = try CodeModeArgumentDecoder.\(method)(\(stringLiteral(field.name)), as: \(field.swiftType).self, in: arguments)")
        }
        if parsed.hasRawPassthrough {
            for field in enumFields {
                body.append("CodeModeToolRawArguments.canonicalize(&raw, \(stringLiteral(field.name)), \(field.name))")
            }
        }

        var initArguments = parsed.fields.map { "\($0.name): \($0.name)" }
        if parsed.hasRawPassthrough {
            initArguments.append("raw: raw")
        }
        body.append(initArguments.isEmpty ? "return Arguments()" : "return Arguments(\(initArguments.joined(separator: ", ")))")

        return """
        func decode(arguments: [String: JSONValue]) throws -> Arguments {
            \(body.joined(separator: "\n    "))
        }
        """
    }

    private static func stringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}

private struct BuiltInTypeInfo {
    var unwrappedType: String
    var kind: BuiltInCodeModeMacro.FieldKind
    var optional: Bool

    init(typeSyntax rawType: String) {
        let trimmed = rawType.replacingOccurrences(of: " ", with: "")
        if trimmed.hasSuffix("?") {
            optional = true
            unwrappedType = String(trimmed.dropLast())
        } else if trimmed.hasPrefix("Optional<"), trimmed.hasSuffix(">") {
            optional = true
            unwrappedType = String(trimmed.dropFirst("Optional<".count).dropLast())
        } else {
            optional = false
            unwrappedType = trimmed
        }

        switch unwrappedType {
        case "String":
            kind = .primitive("string")
        case "Bool":
            kind = .primitive("bool")
        case "Int", "Double", "Float":
            kind = .primitive("number")
        case "JSONValue":
            kind = .primitive("any")
        default:
            if unwrappedType.hasPrefix("["), unwrappedType.hasSuffix("]") {
                kind = .primitive(unwrappedType.contains(":") ? "object" : "array")
            } else {
                // Unrecognized simple type: emitted through CodeModeStringEnum-
                // constrained overloads; the compiler rejects anything else.
                kind = .stringEnum
            }
        }
    }
}

private struct BuiltInMacroDiagnostic: DiagnosticMessage {
    var message: String
    var diagnosticID: MessageID
    var severity: DiagnosticSeverity
    var node: Syntax

    init(_ message: String, node: Syntax) {
        self.message = message
        self.diagnosticID = MessageID(domain: "CodeModeMacros", id: message)
        self.severity = .error
        self.node = node
    }
}

private extension MacroExpansionContext {
    func diagnose(_ message: BuiltInMacroDiagnostic) {
        diagnose(Diagnostic(node: message.node, message: message))
    }
}
