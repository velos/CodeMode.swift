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
            DiagnosticSpec(message: "@BuiltInCodeMode Arguments properties need @ToolParam(\"hint\") (or be the raw passthrough)", line: 4, column: 13),
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

@Test func builtInCodeModeExpansionSupportsScalarAndEnumDefaults() {
    assertMacroExpansion(
        """
        @BuiltInCodeMode(.calendarRead, path: "apple.calendar.listEvents")
        struct DefaultsTool: BuiltInCodeModeTool {
            struct Arguments: Sendable {
                @ToolParam("limit hint.")
                var limit: Int = 50
                @ToolParam("offset hint.")
                var offset: Int = -2
                @ToolParam("ratio hint.")
                var ratio: Double = 0.5
                @ToolParam("fraction hint.")
                var fraction: Float = 0.1
                @ToolParam("enabled hint.")
                var enabled: Bool = true
                @ToolParam("label hint.")
                var label: String = "hello"
                @ToolParam("span hint.")
                var span: CalendarEventSpan = .thisEvent
            }
        }
        """,
        expandedSource: """
        struct DefaultsTool: BuiltInCodeModeTool {
            struct Arguments: Sendable {
                var limit: Int = 50
                var offset: Int = -2
                var ratio: Double = 0.5
                var fraction: Float = 0.1
                var enabled: Bool = true
                var label: String = "hello"
                var span: CalendarEventSpan = .thisEvent
            }

            static let codeModeCapability: CapabilityID = .calendarRead

            static let codeModePath: String = "apple.calendar.listEvents"

            static let codeModeArguments: [BuiltInToolArgument] = [
                BuiltInToolArgument("limit", .number, optional: true, hint: "limit hint.", defaultValue: .number(Double(50))),
                BuiltInToolArgument("offset", .number, optional: true, hint: "offset hint.", defaultValue: .number(Double(-2))),
                BuiltInToolArgument("ratio", .number, optional: true, hint: "ratio hint.", defaultValue: .number(Double(0.5))),
                BuiltInToolArgument("fraction", .number, optional: true, hint: "fraction hint.", defaultValue: .number(Double(0.1))),
                BuiltInToolArgument("enabled", .bool, optional: true, hint: "enabled hint.", defaultValue: .bool(true)),
                BuiltInToolArgument("label", .string, optional: true, hint: "label hint.", defaultValue: .string("hello")),
                BuiltInToolArgument("span", oneOf: CalendarEventSpan.self, optional: true, hint: "span hint.", defaultValue: .string(CalendarEventSpan.thisEvent.rawValue)),
            ]

            func decode(arguments: [String: JSONValue]) throws -> Arguments {
                let limit = try CodeModeArgumentDecoder.optional("limit", as: Int.self, in: arguments) ?? 50
                let offset = try CodeModeArgumentDecoder.optional("offset", as: Int.self, in: arguments) ?? -2
                let ratio = try CodeModeArgumentDecoder.optional("ratio", as: Double.self, in: arguments) ?? 0.5
                let fraction = try CodeModeArgumentDecoder.optional("fraction", as: Float.self, in: arguments) ?? 0.1
                let enabled = try CodeModeArgumentDecoder.optional("enabled", as: Bool.self, in: arguments) ?? true
                let label = try CodeModeArgumentDecoder.optional("label", as: String.self, in: arguments) ?? "hello"
                let span = try CodeModeArgumentDecoder.optional("span", as: CalendarEventSpan.self, in: arguments) ?? .thisEvent
                return Arguments(limit: limit, offset: offset, ratio: ratio, fraction: fraction, enabled: enabled, label: label, span: span)
            }
        }
        """,
        macros: builtInTestMacros()
    )
}

@Test func builtInCodeModeExpansionSupportsDates() {
    assertMacroExpansion(
        """
        @BuiltInCodeMode(.calendarRead, path: "apple.calendar.listEvents")
        struct DatesTool: BuiltInCodeModeTool {
            struct Arguments: Sendable {
                @ToolParam("Start timestamp.")
                var start: Date
                @ToolParam("End timestamp.")
                var end: Foundation.Date?
                var raw: [String: JSONValue]
            }
        }
        """,
        expandedSource: """
        struct DatesTool: BuiltInCodeModeTool {
            struct Arguments: Sendable {
                var start: Date
                var end: Foundation.Date?
                var raw: [String: JSONValue]
            }

            static let codeModeCapability: CapabilityID = .calendarRead

            static let codeModePath: String = "apple.calendar.listEvents"

            static let codeModeArguments: [BuiltInToolArgument] = [
                BuiltInToolArgument("start", .string, hint: "Start timestamp."),
                BuiltInToolArgument("end", .string, optional: true, hint: "End timestamp."),
            ]

            func decode(arguments: [String: JSONValue]) throws -> Arguments {
                let raw = arguments
                let start = try CodeModeDate.require(arguments.string("start"), argument: "start", capability: Self.codeModeCapability.rawValue)
                let end = try CodeModeDate.optional(arguments.string("end"), argument: "end", capability: Self.codeModeCapability.rawValue)
                return Arguments(start: start, end: end, raw: raw)
            }
        }
        """,
        macros: builtInTestMacros()
    )
}

@Test(arguments: [
    ("Int?", "5", true, "var"),
    ("Optional<Int>", "5", true, "var"),
    ("Date", "Date()", false, "var"),
    ("Int", "makeLimit()", false, "var"),
    ("Int", "1 + 2", false, "var"),
    ("Int", "1.5", false, "var"),
    ("String", "5", false, "var"),
    ("[Int]", "[1]", false, "var"),
    ("String", #""\(value)""#, false, "var"),
    ("Int", "50", false, "let"),
])
func builtInCodeModeExpansionDiagnosesUnsupportedDefaults(type: String, initializer: String, optional: Bool, binding: String) {
    assertMacroExpansion(
        """
        @BuiltInCodeMode(.calendarRead, path: "apple.calendar.listEvents")
        struct BrokenTool: BuiltInCodeModeTool {
            struct Arguments: Sendable {
                @ToolParam("Value hint.")
                \(binding) value: \(type) = \(initializer)
            }
        }
        """,
        expandedSource: """
        struct BrokenTool: BuiltInCodeModeTool {
            struct Arguments: Sendable {
                \(binding) value: \(type) = \(initializer)
            }
        }
        """,
        diagnostics: [DiagnosticSpec(
            message: binding == "let"
                ? "@BuiltInCodeMode Arguments properties must be var"
                : optional
                ? "@ToolParam optional properties cannot have initializers; resolve dynamic defaults in call"
                : "@ToolParam defaults must be a matching integer, float, bool, or string literal, or .case for a CodeModeStringEnum",
            line: 5,
            column: binding == "let" ? 9 : 9 + "\(binding) value: \(type) = ".count
        )],
        macros: builtInTestMacros()
    )
}

@Test func builtInCodeModeExpansionTracksSuppliedFieldsWithoutRawValues() {
    assertMacroExpansion(
        """
        @BuiltInCodeMode(.calendarWrite, path: "apple.calendar.updateEvent")
        struct PatchTool: BuiltInCodeModeTool {
            struct Arguments: Sendable {
                var providedArguments: Set<String>
                @ToolParam("Notes patch.")
                var notes: String?
            }
        }
        """,
        expandedSource: """
        struct PatchTool: BuiltInCodeModeTool {
            struct Arguments: Sendable {
                var providedArguments: Set<String>
                var notes: String?
            }

            static let codeModeCapability: CapabilityID = .calendarWrite

            static let codeModePath: String = "apple.calendar.updateEvent"

            static let codeModeArguments: [BuiltInToolArgument] = [
                BuiltInToolArgument("notes", .string, optional: true, hint: "Notes patch."),
            ]

            func decode(arguments: [String: JSONValue]) throws -> Arguments {
                let notes = try CodeModeArgumentDecoder.optional("notes", as: String.self, in: arguments)
                return Arguments(providedArguments: Set(arguments.keys), notes: notes)
            }
        }
        """,
        macros: builtInTestMacros()
    )
}
