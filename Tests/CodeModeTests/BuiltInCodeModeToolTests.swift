import Foundation
import Testing
@testable import CodeMode

@Test func macroGeneratedDecodeCanonicalizesConstrainedValues() throws {
    let tool = CalendarDeleteEventTool()

    let decoded = try tool.decode(arguments: [
        "identifier": .string("E1"),
        "span": .string("FUTURE_EVENTS"),
    ])
    #expect(decoded.identifier == "E1")
    #expect(decoded.span == .futureEvents)
}

@Test func macroGeneratedDecodeRejectsMissingRequiredAndUnknownConstrainedValues() {
    let tool = CalendarDeleteEventTool()

    #expect(throws: (any Error).self) {
        _ = try tool.decode(arguments: ["span": .string("thisEvent")])
    }
    #expect(throws: (any Error).self) {
        _ = try tool.decode(arguments: [
            "identifier": .string("E1"),
            "span": .string("allEvents"),
        ])
    }
}

private enum DefaultFixtureMode: String, CodeModeStringEnum {
    case selected = "wire-value"
    static let codeModeAliases: [String: Self] = ["alias": .selected]
}

// A compiled consumer of every default kind. Expansion snapshots cannot catch
// type inference failures or incorrect advertised defaults.
@BuiltInCodeMode(.calendarRead, path: "apple.calendar.defaultFixture")
private struct DefaultFixtureTool: BuiltInCodeModeTool {
    static let codeModeSummary = "Exercise generated decoding."
    static let codeModeTags: [String] = []
    static let codeModeExample = ""
    static let codeModeResultSummary = "JSON value"

    struct Arguments: Sendable {
        @ToolParam("Limit.") var limit: Int = -5
        @ToolParam("Ratio.") var ratio: Double = 0.5
        @ToolParam("Fraction.") var fraction: Float = 0.1
        @ToolParam("Enabled.") var enabled: Bool = true
        @ToolParam("Label.") var label: String = "hello"
        @ToolParam("Media type.") var mediaType: String = "image/png"
        @ToolParam("Mode.") var mode: DefaultFixtureMode = .selected
        @ToolParam("Start.") var start: Date
        @ToolParam("End.") var end: Date?
        var raw: [String: JSONValue]
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue { .null }
}

@Test func generatedDefaultsStayTypedAndAdvertiseTheirJSONValues() throws {
    let tool = DefaultFixtureTool()
    let decoded = try tool.decode(arguments: ["start": .string("2026-07-24T10:00:00.000Z")])
    #expect(decoded.limit == -5)
    #expect(decoded.ratio == 0.5)
    #expect(decoded.fraction == 0.1)
    #expect(decoded.enabled)
    #expect(decoded.label == "hello")
    #expect(decoded.mediaType == "image/png")
    #expect(decoded.mode == .selected)
    #expect(decoded.start == Date(timeIntervalSince1970: 1_784_887_200))
    #expect(decoded.end == nil)
    // Defaults must reach transitional raw bridges as well as typed consumers.
    #expect(decoded.raw["limit"] == .number(-5))
    #expect(decoded.raw["mode"] == .string("wire-value"))

    let fields = Dictionary(uniqueKeysWithValues: DefaultFixtureTool.codeModeArguments.map { ($0.name, $0) })
    let expected: [String: JSONValue] = [
        "limit": .number(-5), "ratio": .number(0.5), "fraction": .number(0.1),
        "enabled": .bool(true), "label": .string("hello"), "mode": .string("wire-value"),
        "mediaType": .string("image/png"),
    ]
    for (name, value) in expected {
        #expect(fields[name]?.defaultValue == value)
        #expect(fields[name]?.optional == true)
    }
    #expect(fields["label"]?.hint == "Label. Default: \"hello\".")
    #expect(fields["mode"]?.hint == "Mode. Default: \"wire-value\".")
    #expect(fields["limit"]?.hint == "Limit. Default: -5.")
    #expect(fields["fraction"]?.hint == "Fraction. Default: 0.1.")
    #expect(fields["mediaType"]?.hint == "Media type. Default: \"image/png\".")
    #expect(CapabilityRegistration(tool: tool).descriptor.requiredArguments == ["start"])

    let overridden = try tool.decode(arguments: [
        "start": .string("2026-07-24T11:00:00+01:00"), "limit": .number(8),
        "enabled": .bool(false), "label": .string("override"), "mode": .string("ALIAS"),
    ])
    #expect(overridden.start == decoded.start)
    #expect(overridden.limit == 8)
    #expect(overridden.enabled == false)
    #expect(overridden.label == "override")
    #expect(overridden.mode == .selected)
}

@Test func generatedRequiredDateUsesTheBridgeErrorPath() throws {
    for value: JSONValue? in [nil, .string(""), .string("soon")] {
        let arguments = value.map { ["start": $0] } ?? [:]
        do {
            _ = try DefaultFixtureTool().decode(arguments: arguments)
            Issue.record("Expected a required date error")
        } catch let error as BridgeError {
            #expect(error.diagnosticCode == "INVALID_ARGUMENTS")
            #expect(error.localizedDescription == (value == .string("soon")
                ? "calendar.read could not parse 'start' as an ISO 8601 timestamp: \"soon\". Use a form like 2026-07-24T10:00:00Z."
                : "calendar.read requires 'start'"))
        }
    }
}

@Test func resolvingWriteOnlyStatusDoesNotChangeItsMeaningUntilRequired() throws {
    let (context, sandbox) = try makeInvocationContext(permissionBroker: FixedPermissionBroker(statuses: [
        .calendarWriteOnly: .writeOnly, .calendar: .writeOnly,
    ]))
    defer { cleanup(sandbox) }
    #expect(context.resolvedPermission(for: .calendarWriteOnly) == .writeOnly)
    #expect(context.isPermissionValidated(.calendarWriteOnly) == false)
    try context.requirePermission(.calendarWriteOnly)
    #expect(context.isPermissionValidated(.calendarWriteOnly))
    // Requiring a permission must always observe and record its current status.
    try context.requirePermission(.calendarWriteOnly)
    #expect(context.allPermissionEvents().map(\.status) == [.writeOnly, .writeOnly, .writeOnly])

    do {
        try context.requirePermission(.calendar)
        Issue.record("Write-only access must not satisfy full calendar access")
    } catch let error as BridgeError {
        #expect(error.diagnosticCode == "PERMISSION_DENIED")
        #expect(error.localizedDescription == "Permission denied: calendar")
        #expect(context.isPermissionValidated(.calendar) == false)
    }
}

@Test(arguments: [
    (CapabilityID.locationPermissionRequest, PermissionKind.locationWhenInUse),
    (.notificationsPermissionRequest, .notifications),
    (.alarmPermissionRequest, .alarmKit),
    (.musicPermissionRequest, .music),
    (.speechPermissionRequest, .speechRecognition),
])
func permissionRequestHelpersReportDenialWithoutBeingPrechecked(capability: CapabilityID, permission: PermissionKind) throws {
    let registry = CapabilityRegistry(registrations: DefaultCapabilityLoader.loadAllRegistrations())
    let (context, sandbox) = try makeInvocationContext(permissionBroker: FixedPermissionBroker(
        statuses: [permission: .denied], requestStatuses: [permission: .denied]
    ))
    defer { cleanup(sandbox) }
    let result = try registry.invoke(capability.rawValue, arguments: [:], context: context)
    #expect((result.stringValue ?? result.objectValue?.string("status")) == "denied")
    #expect(context.allPermissionEvents().map(\.status) == [.denied])
}

@Test func speechStatusDoesNotRequestOrRequirePermission() throws {
    let registry = CapabilityRegistry(registrations: DefaultCapabilityLoader.loadAllRegistrations())
    let (context, sandbox) = try makeInvocationContext(permissionBroker: FixedPermissionBroker(
        statuses: [.speechRecognition: .notDetermined], requestStatuses: [.speechRecognition: .granted]
    ))
    defer { cleanup(sandbox) }
    let result = try registry.invoke(CapabilityID.speechStatus.rawValue, arguments: [:], context: context)
    #expect(result.objectValue?.string("status") == "notDetermined")
    #expect(context.allPermissionEvents().map(\.status) == [.notDetermined])
}

@Test func migratedToolHintsOnlyExplainWhatTypesCannot() throws {
    let bridges = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/CodeMode/Bridges")
    let tool = try Regex(#"(?s)@BuiltInCodeMode\(.*?(?=@BuiltInCodeMode|\z)"#)
    let hint = try Regex(#"@ToolParam\("([^"]*)"\)"#)
    var checked = 0
    for file in try FileManager.default.contentsOfDirectory(at: bridges, includingPropertiesForKeys: nil) where file.pathExtension == "swift" {
        let source = try String(contentsOf: file, encoding: .utf8)
        for match in source.matches(of: tool) {
            let definition = String(match.output[0].substring!)
            if definition.contains("var raw:") { continue }
            for annotation in definition.matches(of: hint) {
                let text = String(annotation.output[1].substring!)
                #expect(!text.hasPrefix("Optional"), "\(file.lastPathComponent): \(text)")
                #expect(!text.lowercased().contains("default"), "\(file.lastPathComponent): \(text)")
                #expect(!text.contains("ISO8601"), "\(file.lastPathComponent): \(text)")
                checked += 1
            }
        }
    }
    #expect(checked > 30)
}

@BuiltInCodeMode(.calendarRead, path: "apple.calendar.patchFixture")
private struct PatchFixtureTool: BuiltInCodeModeTool {
    static let codeModeSummary = "Exercise typed patches."
    static let codeModeTags: [String] = []
    static let codeModeExample = ""
    static let codeModeResultSummary = "JSON value"
    struct Arguments: Sendable {
        @ToolParam("Mode.") var mode: Patch<DefaultFixtureMode>
        @ToolParam("Date.") var date: Patch<Date>
    }
    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        switch arguments.mode {
        case .unchanged: return .string("unchanged")
        case .clear: return .null
        case let .set(mode): return .string(mode.rawValue)
        }
    }
}

@Test func patchesDecodeThroughRegistryIncludingConstrainedNullAndDates() throws {
    let registry = CapabilityRegistry(registrations: [CapabilityRegistration(tool: PatchFixtureTool())])
    let (context, sandbox) = try makeInvocationContext()
    defer { cleanup(sandbox) }
    #expect(try registry.invoke("calendar.read", arguments: [:], context: context) == .string("unchanged"))
    #expect(try registry.invoke("calendar.read", arguments: ["mode": .null], context: context) == .null)
    #expect(try registry.invoke("calendar.read", arguments: ["mode": .string("ALIAS")], context: context) == .string("wire-value"))
    let decoded = try PatchFixtureTool().decode(arguments: ["date": .string("2026-07-24T10:00:00.000Z")])
    guard case let .set(date) = decoded.date else { Issue.record("Expected a date patch"); return }
    #expect(date == Date(timeIntervalSince1970: 1_784_887_200))
    #expect(throws: (any Error).self) {
        _ = try registry.invoke("calendar.read", arguments: ["mode": .string("unknown")], context: context)
    }
    let reference = try #require(BridgeCatalog(registry: registry).allReferences().first)
    #expect(reference.nullableArguments == ["mode", "date"])
    #expect(reference.dts.contains("date?: string | null;"))
    #expect(reference.dts.contains("mode?: \"wire-value\" | \"alias\" | null;"))
}

@BuiltInCodeMode(.calendarWrite, path: "apple.calendar.dynamicPermissionFixture")
private struct DynamicPermissionFixtureTool: BuiltInCodeModeTool {
    static let codeModeSummary = "Exercise permission selection after decoding."
    static let codeModeTags: [String] = []
    static let codeModeExample = ""
    static let codeModeResultSummary = "JSON value"
    struct Arguments: Sendable {
        @ToolParam("Mode.") var mode: DefaultFixtureMode
    }
    func argumentDependentPermissions(for arguments: Arguments) -> [PermissionKind] { [.calendarWriteOnly] }
    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue { .null }
}

@Test func invalidDynamicPermissionArgumentsFailBeforeRequestingAccess() throws {
    let registration = CapabilityRegistration(tool: DynamicPermissionFixtureTool())
    let (context, sandbox) = try makeInvocationContext(permissionBroker: FixedPermissionBroker(
        statuses: [.calendarWriteOnly: .notDetermined], requestStatuses: [.calendarWriteOnly: .granted]
    ))
    defer { cleanup(sandbox) }
    // Invoke the generated handler directly: registry validation cannot mask a
    // regression that prompts before the generated tool decoder runs.
    #expect(throws: CodeModeFunctionError.invalidArguments("Argument mode must be one of wire-value, alias")) {
        _ = try registration.handler(["mode": .string("invalid")], context)
    }
    #expect(context.allPermissionEvents().isEmpty)
    _ = try registration.handler(["mode": .string("alias")], context)
    #expect(context.allPermissionEvents().contains { $0.permission == .calendarWriteOnly && $0.status == .granted })
}

@ToolResult
public struct TypedResultFixture {
    @ToolResult
    struct Child {
        let name: String
    }

    let child: Child
    @ToolField("May be absent.")
    var label: String?
    var dates: [Date]
    var counts: [String: Int?]
    var ratio: Double
    var fraction: Float
    var enabled: Bool
    var raw: JSONValue
}

@BuiltInCodeMode(.calendarRead, path: "apple.calendar.typedResultFixture")
private struct TypedResultFixtureTool: BuiltInCodeModeTool {
    static let codeModeSummary = "Exercise result composition."
    static let codeModeTags: [String] = []
    static let codeModeExample = ""
    struct Arguments: Sendable {}

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> [TypedResultFixture]? {
        [TypedResultFixture(
            child: .init(name: "nested"), label: nil,
            dates: [Date(timeIntervalSince1970: 0)], counts: ["one": 1, "missing": nil],
            ratio: 1.5, fraction: 0.25, enabled: true, raw: .array([.null])
        )]
    }
}

@Test func typedResultsEncodeThroughRegistrationAndDescribeTheirComposition() throws {
    let registration = CapabilityRegistration(tool: TypedResultFixtureTool())
    let (context, sandbox) = try makeInvocationContext()
    defer { cleanup(sandbox) }
    #expect(try registration.handler([:], context) == .array([.object([
        "child": .object(["name": .string("nested")]), "label": .null,
        "dates": .array([.string("1970-01-01T00:00:00Z")]),
        "counts": .object(["one": .number(1), "missing": .null]),
        "ratio": .number(1.5), "fraction": .number(0.25), "enabled": .bool(true),
        "raw": .array([.null]),
    ])]))
    let expected: CodeModeResultSchema = .nullable(.array(.object([
        .init(name: "child", schema: .object([.init(name: "name", schema: .string)])),
        .init(name: "label", schema: .nullable(.string), hint: "May be absent."),
        .init(name: "dates", schema: .array(.string)),
        .init(name: "counts", schema: .dictionary(.nullable(.number))),
        .init(name: "ratio", schema: .number),
        .init(name: "fraction", schema: .number),
        .init(name: "enabled", schema: .bool),
        .init(name: "raw", schema: .any),
    ])))
    #expect(registration.descriptor.resultSchema == expected)
    #expect(Optional<[TypedResultFixture]>.none.codeModeJSONValue == .null)
    let reference = try #require(BridgeCatalog(registry: CapabilityRegistry(registrations: [registration])).allReferences().first)
    #expect(reference.resultSchema == expected)
    #expect(reference.dts.contains("/** May be absent. */"))
    #expect(reference.dts.contains("label?: string | null;"))
    #expect(reference.dts.contains("dates: Array<string>;"))
    #expect(reference.dts.contains("counts: { [key: string]: number | null };"))
    #expect(reference.dts.contains("}> | null>"))
}

@Test func untypedResultsRetainTheirSummaryOverrideAndOmitTheirSchema() throws {
    let registry = CapabilityRegistry(registrations: DefaultCapabilityLoader.loadAllRegistrations())
    let reference = try #require(BridgeCatalog(registry: registry).reference(forJavaScriptName: "apple.fs.read"))
    #expect(JSONValue.codeModeResultSchema.summary == "JSON value")
    #expect(reference.resultSummary == "Object with path plus text or base64 field.")
    #expect(reference.resultSchema == nil)
    #expect(reference.dts.contains("Promise<CodeModeValue>"))
}
