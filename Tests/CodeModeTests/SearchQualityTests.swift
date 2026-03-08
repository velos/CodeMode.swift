import Foundation
import Testing
@testable import CodeMode

private struct SearchExpectation {
    var query: String
    var expected: CapabilityID
    var maxRank: Int
}

private struct SearchQualityFailure: Error, CustomStringConvertible {
    var description: String
}

@Test func searchAgentStyleQueriesHitExpectedCapabilityWindows() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let expectations: [SearchExpectation] = [
        .init(query: "call api", expected: .networkFetch, maxRank: 3),
        .init(query: "read secret", expected: .keychainRead, maxRank: 3),
        .init(query: "store auth token", expected: .keychainWrite, maxRank: 3),
        .init(query: "delete secret", expected: .keychainDelete, maxRank: 3),
        .init(query: "gps coordinates", expected: .locationRead, maxRank: 3),
        .init(query: "request location permission", expected: .locationPermissionRequest, maxRank: 3),
        .init(query: "current weather forecast", expected: .weatherRead, maxRank: 3),
        .init(query: "list calendar events", expected: .calendarRead, maxRank: 3),
        .init(query: "create calendar event", expected: .calendarWrite, maxRank: 3),
        .init(query: "todo list", expected: .remindersRead, maxRank: 3),
        .init(query: "add todo", expected: .remindersWrite, maxRank: 3),
        .init(query: "list contacts", expected: .contactsRead, maxRank: 3),
        .init(query: "find contact", expected: .contactsSearch, maxRank: 3),
        .init(query: "browse photo library", expected: .photosRead, maxRank: 3),
        .init(query: "export photo asset", expected: .photosExport, maxRank: 3),
        .init(query: "ocr image", expected: .visionImageAnalyze, maxRank: 3),
        .init(query: "request notification permission", expected: .notificationsPermissionRequest, maxRank: 3),
        .init(query: "schedule local alert", expected: .notificationsSchedule, maxRank: 3),
        .init(query: "list pending notifications", expected: .notificationsPendingRead, maxRank: 3),
        .init(query: "cancel pending notification", expected: .notificationsPendingDelete, maxRank: 3),
        .init(query: "request alarm permission", expected: .alarmPermissionRequest, maxRank: 3),
        .init(query: "list alarms", expected: .alarmRead, maxRank: 3),
        .init(query: "set wake up alarm", expected: .alarmSchedule, maxRank: 3),
        .init(query: "cancel alarm", expected: .alarmCancel, maxRank: 3),
        .init(query: "request health access", expected: .healthPermissionRequest, maxRank: 3),
        .init(query: "read heart rate data", expected: .healthRead, maxRank: 3),
        .init(query: "write step count sample", expected: .healthWrite, maxRank: 3),
        .init(query: "list smart home devices", expected: .homeRead, maxRank: 3),
        .init(query: "turn off light", expected: .homeWrite, maxRank: 5),
        .init(query: "read video metadata", expected: .mediaMetadataRead, maxRank: 3),
        .init(query: "make video thumbnail", expected: .mediaFrameExtract, maxRank: 3),
        .init(query: "convert mov to mp4", expected: .mediaTranscode, maxRank: 3),
        .init(query: "list files in tmp", expected: .fsList, maxRank: 3),
        .init(query: "read file contents", expected: .fsRead, maxRank: 3),
        .init(query: "write json file", expected: .fsWrite, maxRank: 3),
        .init(query: "rename file", expected: .fsMove, maxRank: 3),
        .init(query: "copy file", expected: .fsCopy, maxRank: 3),
        .init(query: "remove folder recursively", expected: .fsDelete, maxRank: 3),
        .init(query: "file info metadata", expected: .fsStat, maxRank: 3),
        .init(query: "create folder", expected: .fsMkdir, maxRank: 3),
        .init(query: "does file exist", expected: .fsExists, maxRank: 3),
        .init(query: "check if file is writable", expected: .fsAccess, maxRank: 3),
    ]

    var failures: [String] = []
    var top3Hits = 0
    var top3Total = 0
    var top5Hits = 0
    var top5Total = 0

    for expectation in expectations {
        let response = try await tools.searchJavaScriptAPI(
            JavaScriptAPISearchRequest(query: expectation.query, limit: expectation.maxRank)
        )

        let matches = response.matches.map(\.capability)
        let hit = matches.prefix(expectation.maxRank).contains(expectation.expected)

        if expectation.maxRank == 3 {
            top3Total += 1
            if hit { top3Hits += 1 }
        } else {
            top5Total += 1
            if hit { top5Hits += 1 }
        }

        if hit == false {
            failures.append(
                """
                query=\(expectation.query)
                expected=\(expectation.expected.rawValue)
                maxRank=\(expectation.maxRank)
                got=\(matches.map(\.rawValue).joined(separator: ", "))
                """
            )
        }
    }

    if failures.isEmpty == false {
        throw SearchQualityFailure(
            description: """
            search recall regression
            top3=\(top3Hits)/\(top3Total)
            top5=\(top5Hits)/\(top5Total)

            \(failures.joined(separator: "\n\n"))
            """
        )
    }
}

@Test func canonicalToolDescriptionsExposeRecommendedNames() {
    #expect(CodeModeAgentToolDescriptions.all.map(\.name) == [
        "searchJavaScriptAPI",
        "executeJavaScript",
    ])
    #expect(CodeModeAgentToolDescriptions.searchJavaScriptAPI.description.contains("discover"))
    #expect(CodeModeAgentToolDescriptions.executeJavaScript.description.contains("allowedCapabilities"))
}
