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
    #expect(decoded.raw["span"] == .string("futureEvents"))
    #expect(decoded.raw["identifier"] == .string("E1"))
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
