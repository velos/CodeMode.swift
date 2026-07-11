import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
import CodeModeMacros

private func builtInTestMacros() -> [String: Macro.Type] {
    [
        "BuiltInCodeMode": BuiltInCodeModeMacro.self,
        "ToolParam": ToolParamMacro.self,
    ]
}

@Test func builtInCodeModeExpansionGeneratesMetadataAndDecode() {
    assertMacroExpansion(
        """
        @BuiltInCodeMode(.calendarDelete, path: "apple.calendar.deleteEvent", aliases: ["apple.calendar.removeEvent"])
        struct CalendarDeleteEventTool: BuiltInCodeModeTool {
            struct Arguments: Sendable {
                @ToolParam("EventKit eventIdentifier.")
                var identifier: String
                @ToolParam("thisEvent (default) or futureEvents.")
                var span: CalendarEventSpan?
                var raw: [String: JSONValue]
            }

            func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
                .null
            }
        }
        """,
        expandedSource: """
        struct CalendarDeleteEventTool: BuiltInCodeModeTool {
            struct Arguments: Sendable {
                var identifier: String
                var span: CalendarEventSpan?
                var raw: [String: JSONValue]
            }

            func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
                .null
            }

            static let codeModeCapability: CapabilityID = .calendarDelete

            static let codeModePath: String = "apple.calendar.deleteEvent"

            static let codeModeAliasPaths: [String] = ["apple.calendar.removeEvent"]

            static let codeModeArguments: [BuiltInToolArgument] = [
                BuiltInToolArgument("identifier", .string, hint: "EventKit eventIdentifier."),
                BuiltInToolArgument("span", oneOf: CalendarEventSpan.self, optional: true, hint: "thisEvent (default) or futureEvents."),
            ]

            func decode(arguments: [String: JSONValue]) throws -> Arguments {
                var raw = arguments
                let identifier = try CodeModeArgumentDecoder.require("identifier", as: String.self, in: arguments)
                let span = try CodeModeArgumentDecoder.optional("span", as: CalendarEventSpan.self, in: arguments)
                CodeModeToolRawArguments.canonicalize(&raw, "span", span)
                return Arguments(identifier: identifier, span: span, raw: raw)
            }
        }
        """,
        macros: builtInTestMacros()
    )
}

@Test func builtInCodeModeExpansionSupportsNoArgumentsAndNoRaw() {
    assertMacroExpansion(
        """
        @BuiltInCodeMode(.locationPermissionRequest, path: "apple.location.requestPermission")
        struct LocationPermissionRequestTool: BuiltInCodeModeTool {
            struct Arguments: Sendable {}

            func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
                .null
            }
        }
        """,
        expandedSource: """
        struct LocationPermissionRequestTool: BuiltInCodeModeTool {
            struct Arguments: Sendable {}

            func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
                .null
            }

            static let codeModeCapability: CapabilityID = .locationPermissionRequest

            static let codeModePath: String = "apple.location.requestPermission"

            static let codeModeArguments: [BuiltInToolArgument] = []

            func decode(arguments: [String: JSONValue]) throws -> Arguments {
                return Arguments()
            }
        }
        """,
        macros: builtInTestMacros()
    )
}

@Test func builtInCodeModeExpansionDiagnosesMissingArgumentsStruct() {
    assertMacroExpansion(
        """
        @BuiltInCodeMode(.calendarRead, path: "apple.calendar.listEvents")
        struct BrokenTool: BuiltInCodeModeTool {
            func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
                .null
            }
        }
        """,
        expandedSource: """
        struct BrokenTool: BuiltInCodeModeTool {
            func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
                .null
            }
        }
        """,
        diagnostics: [
            DiagnosticSpec(message: "@BuiltInCodeMode requires a nested Arguments struct", line: 1, column: 1),
        ],
        macros: builtInTestMacros()
    )
}

@Test func builtInCodeModeExpansionDiagnosesUnannotatedField() {
    assertMacroExpansion(
        """
        @BuiltInCodeMode(.calendarRead, path: "apple.calendar.listEvents")
        struct BrokenTool: BuiltInCodeModeTool {
            struct Arguments: Sendable {
                var limit: Int?
            }

            func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
                .null
            }
        }
        """,
        expandedSource: """
        struct BrokenTool: BuiltInCodeModeTool {
            struct Arguments: Sendable {
                var limit: Int?
            }

            func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
                .null
            }
        }
        """,
        diagnostics: [
            DiagnosticSpec(message: "@BuiltInCodeMode Arguments properties need @ToolParam(\"hint\") (or be the raw passthrough)", line: 4, column: 9),
        ],
        macros: builtInTestMacros()
    )
}

@Test func builtInCodeModeExpansionDiagnosesRawNotLast() {
    assertMacroExpansion(
        """
        @BuiltInCodeMode(.calendarRead, path: "apple.calendar.listEvents")
        struct BrokenTool: BuiltInCodeModeTool {
            struct Arguments: Sendable {
                var raw: [String: JSONValue]
                @ToolParam("Max items.")
                var limit: Int?
            }

            func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
                .null
            }
        }
        """,
        expandedSource: """
        struct BrokenTool: BuiltInCodeModeTool {
            struct Arguments: Sendable {
                var raw: [String: JSONValue]
                var limit: Int?
            }

            func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
                .null
            }
        }
        """,
        diagnostics: [
            DiagnosticSpec(message: "@BuiltInCodeMode raw passthrough must be the last stored property of Arguments", line: 3, column: 12),
        ],
        macros: builtInTestMacros()
    )
}
