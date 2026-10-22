import Foundation
import Testing
@testable import CodeMode

@Test func macroGeneratedDecodeCanonicalizesConstrainedValues() throws {
    let tool = CalendarDeleteEventTool(eventKit: EventKitBridge())

    let decoded = try tool.decode(arguments: [
        "identifier": .string("E1"),
        "span": .string("FUTURE_EVENTS"),
    ])
    #expect(decoded.identifier == "E1")
    #expect(decoded.span == .futureEvents)
}

@Test func macroGeneratedDecodeRejectsMissingRequiredAndUnknownConstrainedValues() {
    let tool = CalendarDeleteEventTool(eventKit: EventKitBridge())

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

@Test func macroGeneratedMetadataMatchesHandWrittenBaseline() throws {
    // The EventKit domain was first migrated with hand-written metadata and
    // then converted to @BuiltInCodeMode; pin the identity pieces so a macro
    // regression cannot silently change the advertised surface.
    let registration = try #require(
        DefaultCapabilityLoader.loadAllRegistrations().first { $0.descriptor.id == .remindersWrite }
    )
    #expect(registration.jsNames == [
        "apple.reminders.createReminder",
        "apple.reminders.updateReminder",
        "apple.reminders.completeReminder",
    ])
    #expect(registration.descriptor.requiredPermissions == [.reminders])
    #expect(registration.descriptor.requiredArguments.isEmpty)
    #expect(registration.descriptor.optionalArguments.first == "operation")
    #expect(registration.descriptor.argumentTypes["priority"] == .number)
    #expect(registration.descriptor.argumentConstraints.allowedStringValues["operation"] == ["create", "update", "complete"])
    #expect(registration.descriptor.argumentHints["identifier"] == "EventKit calendarItemIdentifier to update or complete.")
}

private enum DefaultFixtureMode: String, CodeModeStringEnum {
    case selected = "wire-value"
    static let codeModeAliases: [String: Self] = ["alias": .selected]
}

// A compiled consumer of every default kind. Expansion snapshots cannot catch
// type inference failures or incorrect advertised defaults.
@BuiltInCodeMode(.calendarRead, path: "apple.calendar.defaultFixture")
private struct DefaultFixtureTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Defaults fixture"
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

@Test func invalidDynamicPermissionArgumentsFailBeforeRequestingAccess() throws {
    let tool = CalendarWriteEventTool(eventKit: EventKitBridge())
    let (context, sandbox) = try makeInvocationContext(permissionBroker: FixedPermissionBroker(
        statuses: [.calendarWriteOnly: .notDetermined], requestStatuses: [.calendarWriteOnly: .granted]
    ))
    defer { cleanup(sandbox) }
    // Exercise the generated handler directly: registry validation already
    // rejects this, but argument-dependent hooks must remain safe on their own.
    #expect(throws: CodeModeFunctionError.invalidArguments("Argument operation must be one of create, update")) {
        _ = try CapabilityRegistration(tool: tool).handler(["operation": .string("invalid")], context)
    }
    #expect(context.allPermissionEvents().isEmpty)
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
