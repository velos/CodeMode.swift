import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Marker read by `@ToolResult`; property types remain the compiler's concern.
public struct ToolFieldMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] { [] }
}

/// Generates encoding and schema from the same stored instance properties.
public struct ToolResultMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        func reject(_ message: String, at syntax: some SyntaxProtocol) {
            context.diagnose(Diagnostic(node: Syntax(syntax), message: MacroExpansionErrorMessage(message)))
        }
        guard let structure = declaration.as(StructDeclSyntax.self) else {
            reject("@ToolResult can only be attached to a struct", at: node)
            return []
        }
        // Public/package results need equally visible protocol witnesses. As
        // with @CodeMode, implicit member access handles private/fileprivate types.
        let access = structure.modifiers.first { ["public", "package"].contains($0.name.text) }
            .map { $0.name.text + " " } ?? ""
        var encoded: [String] = []
        var fields: [String] = []
        for member in structure.memberBlock.members {
            if member.decl.is(IfConfigDeclSyntax.self) {
                reject("@ToolResult does not support conditional compilation blocks", at: member.decl)
                return []
            }
            guard let property = member.decl.as(VariableDeclSyntax.self) else { continue }
            for binding in property.bindings {
                if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                    let name = identifier.identifier.text.replacingOccurrences(of: "`", with: "")
                    if ["codeModeJSONValue", "codeModeResultSchema"].contains(name) {
                        reject("@ToolResult property name '\(name)' is reserved for generated members", at: property)
                        return []
                    }
                }
            }
            // Type metadata does not describe an instance's JSON payload.
            if property.modifiers.contains(where: { ["static", "class"].contains($0.name.text) }) { continue }
            if property.modifiers.contains(where: { $0.name.text == "lazy" }) {
                reject("@ToolResult does not support lazy properties", at: property)
                return []
            }
            guard property.bindings.count == 1,
                  let binding = property.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                  let type = binding.typeAnnotation?.type else {
                reject("@ToolResult requires one named property with an explicit type per declaration", at: property)
                return []
            }
            if let accessors = binding.accessorBlock {
                switch accessors.accessors {
                case .getter:
                    reject("@ToolResult properties must be stored instance properties", at: property)
                    return []
                case let .accessors(list):
                    if list.contains(where: { !["willSet", "didSet"].contains($0.accessorSpecifier.text) }) {
                        reject("@ToolResult properties must be stored instance properties", at: property)
                        return []
                    }
                }
            }
            let markers = property.attributes.compactMap { $0.as(AttributeSyntax.self) }
                .filter { $0.attributeName.trimmedDescription == "ToolField" }
            var hint = "nil"
            if let marker = markers.first {
                guard markers.count == 1,
                      let arguments = marker.arguments?.as(LabeledExprListSyntax.self),
                      arguments.count == 1,
                      arguments.first?.label == nil,
                      let literal = arguments.first?.expression.as(StringLiteralExprSyntax.self),
                      literal.segments.allSatisfy({ $0.is(StringSegmentSyntax.self) }) else {
                    reject("@ToolField requires one string literal hint", at: marker)
                    return []
                }
                hint = literal.trimmedDescription
            }
            let name = identifier.identifier.text.replacingOccurrences(of: "`", with: "")
            let key = StringLiteralExprSyntax(content: name).description
            encoded.append("\(key): self.\(identifier.trimmedDescription).codeModeJSONValue,")
            // The constrained initializer enforces conformance for arbitrary
            // nested and collection types without parsing them here.
            fields.append("CodeModeResultSchema.Field(name: \(key), describing: (\(type.trimmedDescription)).self, hint: \(hint)),")
        }
        let object = encoded.isEmpty ? ".object([:])" : ".object([\n        \(encoded.joined(separator: "\n        "))\n    ])"
        let schema = fields.isEmpty ? ".object([])" : ".object([\n        \(fields.joined(separator: "\n        "))\n    ])"
        return [
            DeclSyntax(stringLiteral: """
            \(access)var codeModeJSONValue: JSONValue {
                \(object)
            }
            """),
            DeclSyntax(stringLiteral: """
            \(access)static var codeModeResultSchema: CodeModeResultSchema {
                \(schema)
            }
            """),
        ]
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else { return [] }
        return [try ExtensionDeclSyntax("extension \(type): CodeModeResultDescribable {}")]
    }
}
