import Foundation
import Testing
@testable import CodeMode

// MARK: - One ISO 8601 parser

@Test func iso8601ParsingAcceptsFractionalSeconds() {
    // `Date.toISOString()` in JavaScript always emits milliseconds, so this is
    // the spelling a model produces by default. A bare ISO8601DateFormatter
    // rejects it, and the bridges that used one silently substituted "now".
    #expect(CodeModeDate.parse("2026-07-24T10:00:00.000Z") != nil)
    #expect(CodeModeDate.parse("2026-07-24T10:00:00Z") != nil)
    #expect(CodeModeDate.parse("2026-07-24T10:00:00+01:00") != nil)
    #expect(CodeModeDate.parse("  2026-07-24T10:00:00Z  ") != nil)
    #expect(CodeModeDate.parse("not a date") == nil)
    #expect(CodeModeDate.parse("") == nil)
    #expect(CodeModeDate.parse(nil) == nil)
}

@Test func requiredDatesFailInsteadOfSubstitutingADefault() {
    #expect(throws: (any Error).self) {
        _ = try CodeModeDate.require("yesterday", argument: "start", capability: "calendar.read")
    }
    #expect(throws: (any Error).self) {
        _ = try CodeModeDate.require(nil, argument: "start", capability: "calendar.read")
    }
    // A present-but-unparseable optional is still an error; only absence defaults.
    #expect(throws: (any Error).self) {
        _ = try CodeModeDate.optional("soon", argument: "end", capability: "calendar.read")
    }
}

@Test func absentOptionalDatesStillFallBackToTheCallersDefault() throws {
    let absent = try CodeModeDate.optional(nil, argument: "end", capability: "calendar.read")
    #expect(absent == nil)
}

// MARK: - Network policy

@Test func standardPolicyBlocksBareSingleLabelHosts() {
    let policy = NetworkAccessPolicy.standard
    // These resolve onto the LAN through the DHCP search domain, exactly like
    // *.local, but previously fell through to "allowed".
    for host in ["router", "intranet", "wpad", "nas", "printer"] {
        let url = URL(string: "http://\(host)/admin")!
        #expect(policy.violationReason(for: url) != nil, "expected \(host) to be refused")
    }

    // Ordinary public hosts are unaffected.
    #expect(policy.violationReason(for: URL(string: "https://example.com/x")!) == nil)
    #expect(policy.violationReason(for: URL(string: "https://api.example.co.uk/x")!) == nil)
}

@Test func hostsCanStillAllowlistASingleLabelHost() {
    let policy = NetworkAccessPolicy(allowedHosts: ["router"])
    #expect(policy.violationReason(for: URL(string: "http://router/admin")!) == nil)
}

// MARK: - System UI destinations

@Test func webPresentationRespectsTheNetworkAccessPolicy() throws {
    let bridge = SystemUIBridge(networkAccessPolicy: .standard)
    let (context, sandbox) = try makeInvocationContext()
    defer { cleanup(sandbox) }

    // Opening a page in a browser was exempt from the policy governing fetch, so
    // a blocked origin could still be put in front of the user — or be the target
    // of a script-started OAuth flow.
    for capability in ["web", "auth"] {
        let arguments: [String: JSONValue] = ["url": .string("http://169.254.169.254/latest/meta-data")]
        do {
            if capability == "web" {
                _ = try bridge.presentWeb(arguments: arguments, context: context)
            } else {
                _ = try bridge.authenticateWeb(arguments: arguments, context: context)
            }
            Issue.record("Expected \(capability) presentation to be refused by the network policy")
        } catch {
            #expect(requireBridgeErrorCode(error) == "NETWORK_POLICY_VIOLATION")
        }
    }
}

// MARK: - Path containment

@Test func danglingSymlinksDoNotPassContainment() throws {
    let sandbox = try makeTestSandbox()
    defer { cleanup(sandbox) }

    let outsideRoot = sandbox.root.appendingPathComponent("outside", isDirectory: true)
    let policy = DefaultPathPolicy(
        config: PathPolicyConfig(tmpRoot: sandbox.tmp, cachesRoot: sandbox.caches, documentsRoot: sandbox.documents)
    )

    // The target deliberately does not exist: `fileExists` follows symlinks and
    // so reported the link as a *missing component*, which was re-appended to the
    // resolved ancestor and admitted instead of being resolved out of the root.
    let link = sandbox.tmp.appendingPathComponent("escape")
    try FileManager.default.createSymbolicLink(
        at: link,
        withDestinationURL: outsideRoot.appendingPathComponent("secret.txt")
    )

    #expect(throws: (any Error).self) {
        _ = try policy.resolve(path: "tmp:escape")
    }
}

@Test func allowedRootsAreReportedByTheDefaultPolicy() throws {
    let sandbox = try makeTestSandbox()
    defer { cleanup(sandbox) }

    let policy = DefaultPathPolicy(
        config: PathPolicyConfig(tmpRoot: sandbox.tmp, cachesRoot: sandbox.caches, documentsRoot: sandbox.documents)
    )
    let documentsRoot = try policy.resolve(path: "documents:")
    let tmpRoot = try policy.resolve(path: "tmp:")
    let insideTmp = try policy.resolve(path: "tmp:file.txt")

    #expect(policy.allowedRoots.count == 3)
    #expect(policy.isAllowedRoot(documentsRoot))
    #expect(policy.isAllowedRoot(tmpRoot))
    #expect(policy.isAllowedRoot(insideTmp) == false)
}

// MARK: - Diagnostics reach the stream

@Test func errorSeverityDiagnosticsAreEmittedToTheEventStream() {
    let received = LockedBox<[ToolDiagnostic]>([])
    let transcript = ExecutionTranscript { event in
        if case let .diagnostic(diagnostic) = event {
            received.set(received.get() + [diagnostic])
        }
    }

    transcript.record(diagnostic: ToolDiagnostic(severity: .info, code: "I", message: "info"))
    transcript.record(diagnostic: ToolDiagnostic(severity: .warning, code: "W", message: "warning"))
    // Previously filtered out, so a host watching the stream saw every diagnostic
    // except the ones that mattered most.
    transcript.record(diagnostic: ToolDiagnostic(severity: .error, code: "E", message: "error"))

    #expect(received.get().map(\.code) == ["I", "W", "E"])
}
