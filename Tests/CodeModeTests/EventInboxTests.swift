import Foundation
import Testing
@testable import CodeMode

@Test func boundedEventInboxAppendsReadsAndEvictsPerSource() throws {
    let inbox = BoundedCodeModeEventInbox(maxEventsPerSource: 2)
    let oldDate = Date(timeIntervalSince1970: 1_000)
    let newDate = Date(timeIntervalSince1970: 2_000)

    try inbox.appendEvent(CodeModeInboxEvent(id: "cloud-1", source: "cloudkit.subscription", timestamp: oldDate, payload: .object(["recordName": .string("old")])))
    try inbox.appendEvent(CodeModeInboxEvent(id: "cloud-2", source: "cloudkit.subscription", timestamp: newDate, payload: .object(["recordName": .string("new")])))
    try inbox.appendEvent(CodeModeInboxEvent(id: "notification-1", source: "notifications.response", payload: .object(["actionIdentifier": .string("open")])))
    try inbox.appendEvent(CodeModeInboxEvent(
        id: "cloud-3",
        source: "cloudkit.subscription",
        payload: .object(["recordName": .string("latest")]),
        metadata: ["subscriptionID": .string("tasks")]
    ))

    let cloudEvents = try requireArray(inbox.readEvents(source: "cloudkit.subscription", arguments: ["limit": .number(10)]))
    #expect(cloudEvents.count == 2)

    let newest = try #require(cloudEvents.first?.objectValue)
    #expect(newest["id"]?.stringValue == "cloud-3")
    #expect(newest["source"]?.stringValue == "cloudkit.subscription")
    #expect(newest["payload"]?.objectValue?["recordName"]?.stringValue == "latest")
    #expect(newest["metadata"]?.objectValue?["subscriptionID"]?.stringValue == "tasks")

    let oldestRemaining = try #require(cloudEvents.last?.objectValue)
    #expect(oldestRemaining["id"]?.stringValue == "cloud-2")

    let notificationEvents = try requireArray(inbox.readEvents(source: "notifications.response", arguments: [:]))
    #expect(notificationEvents.count == 1)
    #expect(notificationEvents.first?.objectValue?["id"]?.stringValue == "notification-1")
}

@Test func boundedEventInboxHonorsReadLimitAndRejectsInvalidInput() throws {
    let inbox = BoundedCodeModeEventInbox(maxEventsPerSource: 5)
    try inbox.appendEvent(CodeModeInboxEvent(id: "1", source: "storekit.transaction", payload: .object([:])))
    try inbox.appendEvent(CodeModeInboxEvent(id: "2", source: "storekit.transaction", payload: .object([:])))

    let limited = try requireArray(inbox.readEvents(source: "storekit.transaction", arguments: ["limit": .number(1)]))
    #expect(limited.compactMap { $0.objectValue?["id"]?.stringValue } == ["2"])

    do {
        _ = try inbox.readEvents(source: "storekit.transaction", arguments: ["limit": .number(0)])
        Issue.record("Expected invalid inbox limit to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    do {
        try inbox.appendEvent(CodeModeInboxEvent(source: "   ", payload: .null))
        Issue.record("Expected empty source append to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }
}

@Test func unavailableEventInboxAppendAndReadReportUnsupportedPlatform() throws {
    let inbox = UnavailableCodeModeEventInbox()

    do {
        try inbox.appendEvent(CodeModeInboxEvent(source: "cloudkit.subscription", payload: .object([:])))
        Issue.record("Expected append on unavailable inbox to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "UNSUPPORTED_PLATFORM")
    }

    do {
        _ = try inbox.readEvents(source: "cloudkit.subscription", arguments: [:])
        Issue.record("Expected read on unavailable inbox to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "UNSUPPORTED_PLATFORM")
    }
}
