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
        CodeModeDescriptionMacro.self,
        CodeModeNameMacro.self,
        CodeModeParamMacro.self,
        CodeModeResultMacro.self,
    ]
}

public struct CodeModeDescriptionMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

public struct CodeModeNameMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
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

        guard let path = stringArguments(in: node.description).first, isValidPath(path) else {
            context.diagnose(CodeModeDiagnostic("@CodeMode requires a valid dotted JavaScript path", node: Syntax(node)))
            return []
        }

        var seenNames: Set<String> = []
        var entries: [FunctionEntry] = []
        for member in declaration.memberBlock.members {
            guard let function = member.decl.as(FunctionDeclSyntax.self) else {
                continue
            }

            guard let description = attributeString(named: "CodeModeDescription", on: function).first else {
                continue
            }

            let exposedName = attributeString(named: "CodeModeName", on: function).first ?? function.name.text
            guard isValidPathSegment(exposedName) else {
                context.diagnose(CodeModeDiagnostic("@CodeModeName must be a valid JavaScript identifier segment", node: Syntax(function.name)))
                continue
            }
            guard seenNames.insert(exposedName).inserted else {
                context.diagnose(CodeModeDiagnostic("@CodeMode functions cannot expose duplicate names", node: Syntax(function.name)))
                continue
            }

            guard function.genericParameterClause == nil else {
                context.diagnose(CodeModeDiagnostic("@CodeMode does not support generic methods", node: Syntax(function.name)))
                continue
            }

            let isAsync = function.signature.effectSpecifiers?.asyncSpecifier != nil
            let isThrowing = function.signature.effectSpecifiers?.throwsClause != nil
            guard isThrowing else {
                context.diagnose(CodeModeDiagnostic("@CodeMode methods must be throws or async throws", node: Syntax(function.name)))
                continue
            }

            var parameters: [FunctionParameter] = []
            var hasInvalidParameter = false
            for parameter in function.signature.parameterClause.parameters {
                if parameter.defaultValue != nil {
                    context.diagnose(CodeModeDiagnostic("@CodeMode does not support default parameter values", node: Syntax(parameter)))
                    hasInvalidParameter = true
                    continue
                }
                if parameter.ellipsis != nil {
                    context.diagnose(CodeModeDiagnostic("@CodeMode does not support variadic parameters", node: Syntax(parameter)))
                    hasInvalidParameter = true
                    continue
                }
                let externalName = parameter.firstName.text
                if externalName == "_" || parameter.secondName != nil {
                    context.diagnose(CodeModeDiagnostic("@CodeMode v1 requires one named parameter label per argument", node: Syntax(parameter)))
                    hasInvalidParameter = true
                    continue
                }
                guard isValidPathSegment(externalName) else {
                    context.diagnose(CodeModeDiagnostic("@CodeMode parameter labels must be valid JavaScript object keys", node: Syntax(parameter)))
                    hasInvalidParameter = true
                    continue
                }

                let typeInfo = TypeInfo(typeSyntax: parameter.type.trimmedDescription)
                guard typeInfo.isSupported else {
                    context.diagnose(CodeModeDiagnostic("@CodeMode does not support parameter type '\(parameter.type.trimmedDescription)'", node: Syntax(parameter)))
                    hasInvalidParameter = true
                    continue
                }

                parameters.append(
                    FunctionParameter(
                        name: externalName,
                        type: typeInfo.swiftType,
                        argumentType: typeInfo.argumentType,
                        optional: typeInfo.optional,
                        description: parameterDescription(named: externalName, on: function)
                    )
                )
            }
            if hasInvalidParameter {
                continue
            }

            let returnType = function.signature.returnClause?.type.trimmedDescription ?? "Void"
            let returnInfo = TypeInfo(typeSyntax: returnType)
            guard returnType == "Void" || returnInfo.isSupported else {
                context.diagnose(CodeModeDiagnostic("@CodeMode does not support return type '\(returnType)'", node: Syntax(function.name)))
                continue
            }

            entries.append(
                FunctionEntry(
                    swiftName: function.name.text,
                    exposedName: exposedName,
                    summary: description,
                    resultSummary: attributeString(named: "CodeModeResult", on: function).first ?? "JSON value",
                    parameters: parameters,
                    isAsync: isAsync,
                    returnsVoid: returnType == "Void"
                )
            )
        }

        let body = entries.map { registrationSource(for: $0, path: path) }.joined(separator: ",\n")
        let access = providerAccessModifier(for: declaration)
        let extensionSource = """
        extension \(type.trimmedDescription): CodeModeProvider {
            \(access)var codeModePath: String { \(literal(path)) }

            \(access)func codeModeRegistrations() -> [CodeModeRegistration] {
                [
        \(indent(body, spaces: 12))
                ]
            }
        }
        """

        return [try ExtensionDeclSyntax(SyntaxNodeString(stringLiteral: extensionSource))]
    }

    private static func registrationSource(for entry: FunctionEntry, path: String) -> String {
        let capability = "\(path).\(entry.exposedName)"
        let required = entry.parameters.filter { !$0.optional }.map { literal($0.name) }.joined(separator: ", ")
        let optional = entry.parameters.filter(\.optional).map { literal($0.name) }.joined(separator: ", ")
        let argumentTypes = entry.parameters.map { parameter in
            "\(literal(parameter.name)): CapabilityArgumentType.\(parameter.argumentType)"
        }.joined(separator: ", ")
        let argumentHints = entry.parameters.compactMap { parameter -> String? in
            guard let description = parameter.description else { return nil }
            return "\(literal(parameter.name)): \(literal(description))"
        }.joined(separator: ", ")
        let decodeLines = entry.parameters.map { parameter in
            let method = parameter.optional ? "optional" : "require"
            return "let \(parameter.name) = try CodeModeArgumentDecoder.\(method)(\(literal(parameter.name)), as: \(parameter.type).self, in: arguments)"
        }.joined(separator: "\n")
        let callArguments = entry.parameters.map { "\($0.name): \($0.name)" }.joined(separator: ", ")
        let callPrefix = entry.isAsync ? "try await " : "try "
        let call = "\(callPrefix)self.\(entry.swiftName)(\(callArguments))"
        let resultLine = entry.returnsVoid
            ? "\(call)\nreturn .null"
            : "let result = \(call)\nreturn CodeModeValueEncoder.encode(result)"

        return """
        CodeModeRegistration(
            capabilityKey: CodeModeCapabilityKey(rawValue: \(literal(capability))),
            jsPath: \(literal(capability)),
            title: \(literal(entry.exposedName)),
            summary: \(literal(entry.summary)),
            tags: [\(literal(path))],
            example: "await \(capability)({})",
            requiredArguments: [\(required)],
            optionalArguments: [\(optional)],
            argumentTypes: [\(argumentTypes)],
            argumentHints: [\(argumentHints)],
            resultSummary: \(literal(entry.resultSummary)),
            handler: { arguments, _ in
                try CodeModeAsyncBridge.run {
        \(indent(decodeLines, spaces: 12))
        \(indent(resultLine, spaces: 12))
                }
            }
        )
        """
    }

    private static func isSupportedProviderDeclaration(_ declaration: some DeclGroupSyntax) -> Bool {
        if declaration.as(StructDeclSyntax.self) != nil { return true }
        if declaration.as(ActorDeclSyntax.self) != nil { return true }
        if let classDecl = declaration.as(ClassDeclSyntax.self) {
            return classDecl.modifiers.contains { $0.name.text == "final" }
        }
        return false
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

    private static func attributeString(named name: String, on function: FunctionDeclSyntax) -> [String] {
        function.attributes.compactMap { element -> [String]? in
            guard case let .attribute(attribute) = element,
                  attribute.attributeName.trimmedDescription == name
            else {
                return nil
            }
            return stringArguments(in: attribute.description)
        }
        .flatMap { $0 }
    }

    private static func parameterDescription(named name: String, on function: FunctionDeclSyntax) -> String? {
        function.attributes.compactMap { element -> String? in
            guard case let .attribute(attribute) = element,
                  attribute.attributeName.trimmedDescription == "CodeModeParam"
            else {
                return nil
            }
            let strings = stringArguments(in: attribute.description)
            guard strings.count == 2, strings[0] == name else {
                return nil
            }
            return strings[1]
        }
        .first
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

private struct FunctionEntry {
    var swiftName: String
    var exposedName: String
    var summary: String
    var resultSummary: String
    var parameters: [FunctionParameter]
    var isAsync: Bool
    var returnsVoid: Bool
}

private struct FunctionParameter {
    var name: String
    var type: String
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
