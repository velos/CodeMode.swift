import Foundation
import Testing
@testable import CodeMode

// MARK: - JavaScriptExecutionRequest decoding (Fix 2/3)

private func decodeRequest(_ json: String) throws -> JavaScriptExecutionRequest {
    try JSONDecoder().decode(JavaScriptExecutionRequest.self, from: Data(json.utf8))
}

@Test func executionRequestDecodesTimeoutFromNumericString() throws {
    // The exact shape that was failing in the field: timeoutMs quoted, and
    // allowedCapabilityKeys / context omitted.
    let request = try decodeRequest(#"""
    {"allowedCapabilities":["calendar.write"],"code":"return 1;","timeoutMs":"10000"}
    """#)
    #expect(request.timeoutMs == 10_000)
    #expect(request.allowedCapabilities == [.calendarWrite])
    #expect(request.allowedCapabilityKeys.isEmpty)
}

@Test func executionRequestDecodesTimeoutFromNumber() throws {
    let request = try decodeRequest(#"{"code":"return 1;","allowedCapabilities":[],"timeoutMs":5000}"#)
    #expect(request.timeoutMs == 5_000)
}

@Test func executionRequestTreatsOmittedOptionalsAsDefaults() throws {
    // Only the two schema-required fields present.
    let request = try decodeRequest(#"{"code":"return 1;","allowedCapabilities":["fs.read"]}"#)
    #expect(request.timeoutMs == 10_000)
    #expect(request.allowedCapabilityKeys.isEmpty)
    #expect(request.context == ExecutionContext())
    #expect(request.allowedCapabilities == [.fsRead])
}

@Test func executionRequestTreatsNullTimeoutAsDefault() throws {
    let request = try decodeRequest(#"{"code":"return 1;","allowedCapabilities":[],"timeoutMs":null}"#)
    #expect(request.timeoutMs == 10_000)
}

@Test func executionRequestReportsUnknownCapabilityClearly() {
    do {
        _ = try decodeRequest(#"{"code":"return 1;","allowedCapabilities":["calendar.write","calendarWrite","not.a.cap"]}"#)
        Issue.record("Expected decoding to throw on unknown capability IDs")
    } catch {
        let message = "\(error)"
        // The good spelling must not appear; the two bad ones must, by name.
        #expect(message.contains("calendarWrite"))
        #expect(message.contains("not.a.cap"))
    }
}

@Test func executionRequestRejectsNonNumericTimeout() {
    #expect(throws: (any Error).self) {
        _ = try decodeRequest(#"{"code":"return 1;","allowedCapabilities":[],"timeoutMs":"soon"}"#)
    }
}

@Test func executionRequestRoundTripsThroughCodable() throws {
    let original = JavaScriptExecutionRequest(
        code: "return 1;",
        allowedCapabilities: [.fsRead, .networkFetch],
        allowedCapabilityKeys: ["custom.tool"],
        timeoutMs: 7_500,
        context: ExecutionContext(userID: "u", sessionID: "s")
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(JavaScriptExecutionRequest.self, from: data)
    #expect(decoded == original)
}

// MARK: - Registry argument coercion (Fix 1)

/// A synthetic capability whose handler echoes the (already-normalized) arguments
/// it receives, so tests can observe coercion end-to-end.
private func makeEchoRegistry(argumentTypes: [String: CapabilityArgumentType]) -> CapabilityRegistry {
    let descriptor = CapabilityDescriptor(
        id: .fsRead,
        title: "Echo",
        summary: "Echoes received arguments",
        tags: ["test"],
        example: "noop",
        optionalArguments: Array(argumentTypes.keys.filter { $0.contains(".") == false }),
        argumentTypes: argumentTypes
    )
    return CapabilityRegistry(
        registrations: [
            CapabilityRegistration(descriptor: descriptor) { args, _ in .object(args) }
        ]
    )
}

@Test func registryCoercesNumericStringToNumber() throws {
    let registry = makeEchoRegistry(argumentTypes: ["count": .number])
    let (context, sandbox) = try makeInvocationContext(allowedCapabilities: [.fsRead])
    defer { cleanup(sandbox) }

    let result = try registry.invoke(
        CapabilityID.fsRead.rawValue,
        arguments: ["count": .string(" 20 ")],
        context: context
    )
    #expect(result.objectValue?["count"] == .number(20))
}

@Test func registryCoercesBoolStringsCaseInsensitively() throws {
    let registry = makeEchoRegistry(argumentTypes: ["flag": .bool])
    let (context, sandbox) = try makeInvocationContext(allowedCapabilities: [.fsRead])
    defer { cleanup(sandbox) }

    for (input, expected) in [("true", true), ("TRUE", true), ("False", false)] {
        let result = try registry.invoke(
            CapabilityID.fsRead.rawValue,
            arguments: ["flag": .string(input)],
            context: context
        )
        #expect(result.objectValue?["flag"] == .bool(expected))
    }
}

@Test func registryDoesNotCoerceNonBooleanStringsOrBadNumbers() throws {
    let registry = makeEchoRegistry(argumentTypes: ["count": .number, "flag": .bool])
    let (context, sandbox) = try makeInvocationContext(allowedCapabilities: [.fsRead])
    defer { cleanup(sandbox) }

    // "yes"/"1"/"0" are intentionally NOT booleans, so validation still rejects them
    // (safety gates like `confirmed` keep requiring an explicit true/false).
    for bad in ["yes", "1", "0"] {
        #expect(throws: (any Error).self) {
            _ = try registry.invoke(CapabilityID.fsRead.rawValue, arguments: ["flag": .string(bad)], context: context)
        }
    }
    // A non-numeric string stays rejected too.
    #expect(throws: (any Error).self) {
        _ = try registry.invoke(CapabilityID.fsRead.rawValue, arguments: ["count": .string("abc")], context: context)
    }
}

@Test func registryCoercesNestedDottedNumericString() throws {
    let registry = makeEchoRegistry(argumentTypes: ["options": .object, "options.timeoutMs": .number])
    let (context, sandbox) = try makeInvocationContext(allowedCapabilities: [.fsRead])
    defer { cleanup(sandbox) }

    let result = try registry.invoke(
        CapabilityID.fsRead.rawValue,
        arguments: ["options": .object(["timeoutMs": .string("5000")])],
        context: context
    )
    #expect(result.objectValue?["options"]?.objectValue?["timeoutMs"] == .number(5000))
}
