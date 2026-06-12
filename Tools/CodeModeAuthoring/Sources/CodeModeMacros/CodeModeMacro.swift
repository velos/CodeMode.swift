import Foundation
import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct CodeModePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        CodeModeMacro.self,
        CodeModeParamMacro.self,
        CodeModeResultMacro.self,
    ]
}

public struct CodeModeParamMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

public struct CodeModeResultMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

public struct CodeModeMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard isSupportedProviderDeclaration(declaration) else {
            context.diagnose(CodeModeDiagnostic("@CodeMode can only be attached to a struct, final class, or actor", node: Syntax(declaration)))
            return []
        }

        guard isNonGenericDeclaration(declaration) else {
            context.diagnose(CodeModeDiagnostic("@CodeMode does not support generic types", node: Syntax(declaration)))
            return []
        }

        let macroStrings = stringArguments(in: node.description)
        guard macroStrings.count >= 2 else {
            context.diagnose(CodeModeDiagnostic("@CodeMode requires path and description string arguments", node: Syntax(node)))
            return []
        }

        let path = macroStrings[0]
        let summary = macroStrings[1]
        guard isValidPath(path) else {
            context.diagnose(CodeModeDiagnostic("@CodeMode requires a valid dotted JavaScript path", node: Syntax(node)))
            return []
        }

        guard let argumentsStruct = nestedStruct(named: "Arguments", in: declaration) else {
            context.diagnose(CodeModeDiagnostic("@CodeMode requires a nested Arguments struct", node: Syntax(declaration)))
            return []
        }

        guard let call = callMethod(in: declaration, context: context) else {
            return []
        }

        let argumentFields = fields(in: argumentsStruct, attributeName: "CodeModeParam", context: context)
        guard argumentFields.invalid == false else {
            return []
        }

        let resultStruct = nestedStruct(named: "Result", in: declaration)
        let resultInfo = resultStruct.map { structDecl in
            let parsed = fields(in: structDecl, attributeName: nil, context: context)
            return ParsedResult(
                summary: attributeString(named: "CodeModeResult", attributes: structDecl.attributes).first ?? "JSON value",
                fields: parsed.fields,
                invalid: parsed.invalid
            )
        }
        guard resultInfo?.invalid != true else {
            return []
        }

        guard validate(call: call, hasResultStruct: resultStruct != nil, context: context) else {
            return []
        }

        let returnsVoid = call.returnType == "Void" || call.returnType == "()"
        if returnsVoid, resultStruct != nil {
            context.diagnose(CodeModeDiagnostic("@CodeMode Result is only valid when call returns Result", node: Syntax(resultStruct!)))
            return []
        }

        let access = providerAccessModifier(for: declaration)
        let extensionSource = """
        extension \(type.trimmedDescription): CodeModeProvider {
            \(access)var codeModePath: String { \(literal(path)) }

            \(access)func codeModeRegistrations() -> [CodeModeRegistration] {
                [
                    CodeModeRegistration(
                        capabilityKey: CodeModeCapabilityKey(rawValue: \(literal(path))),
                        jsPath: \(literal(path)),
                        title: \(literal(title(for: path))),
                        summary: \(literal(summary)),
                        tags: [\(literal(parentPath(for: path)))],
                        example: "await \(path)({})",
                        requiredArguments: [\(argumentFields.fields.filter { !$0.optional }.map { literal($0.name) }.joined(separator: ", "))],
                        optionalArguments: [\(argumentFields.fields.filter(\.optional).map { literal($0.name) }.joined(separator: ", "))],
                        argumentTypes: \(argumentTypesSource(for: argumentFields.fields)),
                        argumentHints: \(argumentHintsSource(for: argumentFields.fields)),
                        resultSummary: \(literal(returnsVoid ? "null" : resultInfo?.summary ?? "JSON value")),
                        handler: { arguments, _ in
                            try CodeModeAsyncBridge.run {
        \(indent(argumentsSource(for: argumentFields.fields), spaces: 24))
        \(indent(resultSource(for: call, returnsVoid: returnsVoid, resultFields: resultInfo?.fields ?? []), spaces: 24))
                            }
                        }
                    )
                ]
            }
        }
        """

        return [try ExtensionDeclSyntax(SyntaxNodeString(stringLiteral: extensionSource))]
    }

    private static func callMethod(in declaration: some DeclGroupSyntax, context: some MacroExpansionContext) -> CallMethod? {
        let functions = declaration.memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }
            .filter { $0.name.text == "call" }

        guard functions.count == 1, let function = functions.first else {
            context.diagnose(CodeModeDiagnostic("@CodeMode requires exactly one call(arguments:) method", node: Syntax(declaration)))
            return nil
        }

        guard function.genericParameterClause == nil else {
            context.diagnose(CodeModeDiagnostic("@CodeMode does not support generic methods", node: Syntax(function.name)))
            return nil
        }

        guard function.signature.effectSpecifiers?.throwsClause != nil else {
            context.diagnose(CodeModeDiagnostic("@CodeMode call(arguments:) must be throws or async throws", node: Syntax(function.name)))
            return nil
        }

        let parameters = Array(function.signature.parameterClause.parameters)
        guard parameters.count == 1, let parameter = parameters.first else {
            context.diagnose(CodeModeDiagnostic("@CodeMode call method must accept exactly one arguments parameter", node: Syntax(function.name)))
            return nil
        }

        guard parameter.defaultValue == nil, parameter.ellipsis == nil else {
            context.diagnose(CodeModeDiagnostic("@CodeMode call(arguments:) does not support default or variadic parameters", node: Syntax(parameter)))
            return nil
        }

        guard parameter.firstName.text == "arguments",
              parameter.secondName == nil,
              parameter.type.trimmedDescription == "Arguments"
        else {
            context.diagnose(CodeModeDiagnostic("@CodeMode call method must be call(arguments: Arguments)", node: Syntax(parameter)))
            return nil
        }

        return CallMethod(
            isAsync: function.signature.effectSpecifiers?.asyncSpecifier != nil,
            returnType: function.signature.returnClause?.type.trimmedDescription ?? "Void",
            node: Syntax(function.name)
        )
    }

    private static func validate(
        call: CallMethod,
        hasResultStruct: Bool,
        context: some MacroExpansionContext
    ) -> Bool {
        if call.returnType == "Void" || call.returnType == "()" {
            return true
        }

        guard call.returnType == "Result" else {
            context.diagnose(CodeModeDiagnostic("@CodeMode call return type must be Void or nested Result", node: call.node))
            return false
        }

        guard hasResultStruct else {
            context.diagnose(CodeModeDiagnostic("@CodeMode call returning Result requires a nested Result struct", node: call.node))
            return false
        }

        return true
    }

    private static func fields(
        in structDecl: StructDeclSyntax,
        attributeName: String?,
        context: some MacroExpansionContext
    ) -> ParsedFields {
        var result: [ToolField] = []
        var invalid = false
        var seenNames: Set<String> = []

        for member in structDecl.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else {
                continue
            }

            guard variable.bindings.count == 1, let binding = variable.bindings.first else {
                context.diagnose(CodeModeDiagnostic("@CodeMode only supports one stored property per declaration", node: Syntax(variable)))
                invalid = true
                continue
            }

            guard binding.accessorBlock == nil else {
                context.diagnose(CodeModeDiagnostic("@CodeMode does not support computed properties", node: Syntax(binding)))
                invalid = true
                continue
            }

            guard binding.initializer == nil else {
                context.diagnose(CodeModeDiagnostic("@CodeMode does not support default property values", node: Syntax(binding)))
                invalid = true
                continue
            }

            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                context.diagnose(CodeModeDiagnostic("@CodeMode properties must use simple identifiers", node: Syntax(binding.pattern)))
                invalid = true
                continue
            }

            let name = identifier.identifier.text
            guard isValidPathSegment(name) else {
                context.diagnose(CodeModeDiagnostic("@CodeMode property names must be valid JavaScript object keys", node: Syntax(identifier)))
                invalid = true
                continue
            }

            guard seenNames.insert(name).inserted else {
                context.diagnose(CodeModeDiagnostic("@CodeMode properties cannot use duplicate names", node: Syntax(identifier)))
                invalid = true
                continue
            }

            guard let type = binding.typeAnnotation?.type.trimmedDescription else {
                context.diagnose(CodeModeDiagnostic("@CodeMode properties must have explicit types", node: Syntax(binding)))
                invalid = true
                continue
            }

            let typeInfo = TypeInfo(typeSyntax: type)
            guard typeInfo.isSupported else {
                context.diagnose(CodeModeDiagnostic("@CodeMode does not support property type '\(type)'", node: Syntax(binding)))
                invalid = true
                continue
            }

            result.append(
                ToolField(
                    name: name,
                    swiftType: typeInfo.swiftType,
                    argumentType: typeInfo.argumentType,
                    optional: typeInfo.optional,
                    description: attributeName.flatMap { attributeString(named: $0, attributes: variable.attributes).first }
                )
            )
        }

        return ParsedFields(fields: result, invalid: invalid)
    }

    private static func nestedStruct(named name: String, in declaration: some DeclGroupSyntax) -> StructDeclSyntax? {
        declaration.memberBlock.members.compactMap { member in
            member.decl.as(StructDeclSyntax.self)
        }
        .first { $0.name.text == name }
    }

    private static func argumentsSource(for fields: [ToolField]) -> String {
        guard fields.isEmpty == false else {
            return "let decodedArguments = Arguments()"
        }

        let assignments = fields.map { field in
            let method = field.optional ? "optional" : "require"
            return "\(field.name): try CodeModeArgumentDecoder.\(method)(\(literal(field.name)), as: \(field.swiftType).self, in: arguments)"
        }.joined(separator: ",\n")

        return """
        let decodedArguments = Arguments(
        \(indent(assignments, spaces: 4))
        )
        """
    }

    private static func resultSource(for call: CallMethod, returnsVoid: Bool, resultFields: [ToolField]) -> String {
        let callPrefix = call.isAsync ? "try await " : "try "
        let invocation = "\(callPrefix)self.call(arguments: decodedArguments)"

        guard returnsVoid == false else {
            return """
            \(invocation)
            return .null
            """
        }

        guard resultFields.isEmpty == false else {
            return """
            _ = \(invocation)
            return .object([:])
            """
        }

        let objectEntries = resultFields.map { field in
            "\(literal(field.name)): CodeModeValueEncoder.encode(result.\(field.name))"
        }.joined(separator: ",\n")

        return """
        let result = \(invocation)
        return .object([
        \(indent(objectEntries, spaces: 4))
        ])
        """
    }

    private static func argumentTypesSource(for fields: [ToolField]) -> String {
        guard fields.isEmpty == false else {
            return "[:]"
        }
        return "[" + fields.map { field in
            "\(literal(field.name)): CapabilityArgumentType.\(field.argumentType)"
        }.joined(separator: ", ") + "]"
    }

    private static func argumentHintsSource(for fields: [ToolField]) -> String {
        let entries = fields.compactMap { field -> String? in
            guard let description = field.description else {
                return nil
            }
            return "\(literal(field.name)): \(literal(description))"
        }
        guard entries.isEmpty == false else {
            return "[:]"
        }
        return "[" + entries.joined(separator: ", ") + "]"
    }

    private static func isSupportedProviderDeclaration(_ declaration: some DeclGroupSyntax) -> Bool {
        if declaration.as(StructDeclSyntax.self) != nil { return true }
        if declaration.as(ActorDeclSyntax.self) != nil { return true }
        if let classDecl = declaration.as(ClassDeclSyntax.self) {
            return classDecl.modifiers.contains { $0.name.text == "final" }
        }
        return false
    }

    private static func isNonGenericDeclaration(_ declaration: some DeclGroupSyntax) -> Bool {
        if let structDecl = declaration.as(StructDeclSyntax.self) {
            return structDecl.genericParameterClause == nil
        }
        if let actorDecl = declaration.as(ActorDeclSyntax.self) {
            return actorDecl.genericParameterClause == nil
        }
        if let classDecl = declaration.as(ClassDeclSyntax.self) {
            return classDecl.genericParameterClause == nil
        }
        return true
    }

    private static func providerAccessModifier(for declaration: some DeclGroupSyntax) -> String {
        let modifiers: DeclModifierListSyntax?
        if let structDecl = declaration.as(StructDeclSyntax.self) {
            modifiers = structDecl.modifiers
        } else if let actorDecl = declaration.as(ActorDeclSyntax.self) {
            modifiers = actorDecl.modifiers
        } else if let classDecl = declaration.as(ClassDeclSyntax.self) {
            modifiers = classDecl.modifiers
        } else {
            modifiers = nil
        }
        guard let modifiers else {
            return ""
        }
        if modifiers.contains(where: { $0.name.text == "public" || $0.name.text == "open" }) {
            return "public "
        }
        return ""
    }

    private static func attributeString(named name: String, attributes: AttributeListSyntax) -> [String] {
        attributes.compactMap { element -> [String]? in
            guard case let .attribute(attribute) = element,
                  attribute.attributeName.trimmedDescription == name
            else {
                return nil
            }
            return stringArguments(in: attribute.description)
        }
        .flatMap { $0 }
    }

    private static func stringArguments(in source: String) -> [String] {
        var values: [String] = []
        var current = ""
        var inString = false
        var escaped = false
        for character in source {
            if inString {
                if escaped {
                    switch character {
                    case "n": current.append("\n")
                    case "t": current.append("\t")
                    case "\"": current.append("\"")
                    case "\\": current.append("\\")
                    default: current.append(character)
                    }
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    values.append(current)
                    current = ""
                    inString = false
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                inString = true
            }
        }
        return values
    }

    private static func isValidPath(_ path: String) -> Bool {
        let segments = path.split(separator: ".").map(String.init)
        return segments.isEmpty == false && segments.allSatisfy(isValidPathSegment)
    }

    private static func isValidPathSegment(_ segment: String) -> Bool {
        guard let first = segment.first,
              first == "_" || first == "$" || first.isASCIILetter
        else {
            return false
        }
        return segment.allSatisfy { $0 == "_" || $0 == "$" || $0.isASCIILetter || $0.isASCIIDigit }
    }

    private static func title(for path: String) -> String {
        path.split(separator: ".").last.map(String.init) ?? path
    }

    private static func parentPath(for path: String) -> String {
        let segments = path.split(separator: ".").map(String.init)
        guard segments.count > 1 else {
            return path
        }
        return segments.dropLast().joined(separator: ".")
    }

    private static func literal(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    private static func indent(_ value: String, spaces: Int) -> String {
        let prefix = String(repeating: " ", count: spaces)
        return value
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : prefix + $0 }
            .joined(separator: "\n")
    }
}

private struct ParsedFields {
    var fields: [ToolField]
    var invalid: Bool
}

private struct ParsedResult {
    var summary: String
    var fields: [ToolField]
    var invalid: Bool
}

private struct CallMethod {
    var isAsync: Bool
    var returnType: String
    var node: Syntax
}

private struct ToolField {
    var name: String
    var swiftType: String
    var argumentType: String
    var optional: Bool
    var description: String?
}

private struct TypeInfo {
    var swiftType: String
    var argumentType: String
    var optional: Bool
    var isSupported: Bool

    init(typeSyntax rawType: String) {
        let trimmed = rawType.replacingOccurrences(of: " ", with: "")
        let optional: Bool
        let unwrapped: String
        if trimmed.hasSuffix("?") {
            optional = true
            unwrapped = String(trimmed.dropLast())
        } else if trimmed.hasPrefix("Optional<"), trimmed.hasSuffix(">") {
            optional = true
            unwrapped = String(trimmed.dropFirst("Optional<".count).dropLast())
        } else {
            optional = false
            unwrapped = trimmed
        }

        self.optional = optional
        self.swiftType = unwrapped

        switch unwrapped {
        case "String":
            self.argumentType = "string"
            self.isSupported = true
        case "Bool":
            self.argumentType = "bool"
            self.isSupported = true
        case "Int", "Double", "Float":
            self.argumentType = "number"
            self.isSupported = true
        case "JSONValue":
            self.argumentType = "any"
            self.isSupported = true
        default:
            if unwrapped.hasPrefix("["), unwrapped.hasSuffix("]") {
                self.argumentType = unwrapped.contains(":") ? "object" : "array"
                self.isSupported = Self.isSupportedCollection(unwrapped)
            } else {
                self.argumentType = "any"
                self.isSupported = false
            }
        }
    }

    private static func isSupportedCollection(_ type: String) -> Bool {
        let scalarTypes: Set<String> = ["String", "Bool", "Int", "Double", "Float", "JSONValue"]
        let inner = String(type.dropFirst().dropLast())
        if inner.hasPrefix("String:") {
            let value = String(inner.dropFirst("String:".count))
            return scalarTypes.contains(value)
        }
        return scalarTypes.contains(inner)
    }
}

private struct CodeModeDiagnostic: DiagnosticMessage {
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
    func diagnose(_ message: CodeModeDiagnostic) {
        diagnose(Diagnostic(node: message.node, message: message))
    }
}

private extension Character {
    var isASCIILetter: Bool {
        guard unicodeScalars.count == 1, let scalar = unicodeScalars.first else {
            return false
        }
        return (65...90).contains(Int(scalar.value)) || (97...122).contains(Int(scalar.value))
    }

    var isASCIIDigit: Bool {
        guard unicodeScalars.count == 1, let scalar = unicodeScalars.first else {
            return false
        }
        return (48...57).contains(Int(scalar.value))
    }
}
