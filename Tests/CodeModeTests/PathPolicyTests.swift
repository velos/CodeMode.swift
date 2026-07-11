import Foundation
import Testing
@testable import CodeMode

private func makePolicy(_ sandbox: TestSandbox, appGroupRoot: URL? = nil) -> DefaultPathPolicy {
    DefaultPathPolicy(
        config: PathPolicyConfig(
            tmpRoot: sandbox.tmp,
            cachesRoot: sandbox.caches,
            documentsRoot: sandbox.documents,
            appGroupRoot: appGroupRoot
        )
    )
}

private func expectPathViolation(_ body: () throws -> URL) {
    do {
        let url = try body()
        Issue.record("Expected PATH_POLICY_VIOLATION, resolved to \(url.path)")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PATH_POLICY_VIOLATION")
    }
}

@Test func pathPolicyRejectsEmptyAndWhitespacePaths() throws {
    let sandbox = try makeTestSandbox()
    defer { cleanup(sandbox) }
    let policy = makePolicy(sandbox)

    expectPathViolation { try policy.resolve(path: "") }
    expectPathViolation { try policy.resolve(path: "   \n") }
}

@Test func pathPolicyResolvesRelativePathsUnderTmp() throws {
    let sandbox = try makeTestSandbox()
    defer { cleanup(sandbox) }
    let policy = makePolicy(sandbox)

    let url = try policy.resolve(path: "notes.txt")
    #expect(url.path.hasPrefix(sandbox.tmp.resolvingSymlinksInPath().path))
    #expect(url.lastPathComponent == "notes.txt")
}

@Test func pathPolicyResolvesScopedPathsToTheirRoots() throws {
    let sandbox = try makeTestSandbox()
    defer { cleanup(sandbox) }
    let policy = makePolicy(sandbox)

    let tmpRoot = sandbox.tmp.resolvingSymlinksInPath().path
    let cachesRoot = sandbox.caches.resolvingSymlinksInPath().path
    let documentsRoot = sandbox.documents.resolvingSymlinksInPath().path

    #expect(try policy.resolve(path: "tmp:a.txt").path == tmpRoot + "/a.txt")
    #expect(try policy.resolve(path: "caches:sub/b.txt").path == cachesRoot + "/sub/b.txt")
    #expect(try policy.resolve(path: "documents:c.txt").path == documentsRoot + "/c.txt")
}

@Test func pathPolicyResolvesAppGroupScopeOnlyWhenConfigured() throws {
    let sandbox = try makeTestSandbox()
    defer { cleanup(sandbox) }

    let appGroup = sandbox.root.appendingPathComponent("appGroup", isDirectory: true)
    try FileManager.default.createDirectory(at: appGroup, withIntermediateDirectories: true)

    let configured = makePolicy(sandbox, appGroupRoot: appGroup)
    let url = try configured.resolve(path: "appGroup:shared.txt")
    #expect(url.path == appGroup.resolvingSymlinksInPath().path + "/shared.txt")

    // Without a configured app-group root the scope prefix is not recognized;
    // the whole string falls back to a tmp-relative literal file name.
    let unconfigured = makePolicy(sandbox)
    let fallback = try unconfigured.resolve(path: "appGroup:shared.txt")
    #expect(fallback.path.hasPrefix(sandbox.tmp.resolvingSymlinksInPath().path))
}

@Test func pathPolicyAllowsAbsolutePathsInsideAllowedRoots() throws {
    let sandbox = try makeTestSandbox()
    defer { cleanup(sandbox) }
    let policy = makePolicy(sandbox)

    let inside = sandbox.documents.appendingPathComponent("report.pdf").path
    let url = try policy.resolve(path: inside)
    #expect(url.path == sandbox.documents.resolvingSymlinksInPath().path + "/report.pdf")
}

@Test func pathPolicyRejectsAbsolutePathsOutsideAllowedRoots() throws {
    let sandbox = try makeTestSandbox()
    defer { cleanup(sandbox) }
    let policy = makePolicy(sandbox)

    expectPathViolation { try policy.resolve(path: "/etc/passwd") }
    expectPathViolation { try policy.resolve(path: sandbox.root.appendingPathComponent("outside.txt").path) }
}

@Test func pathPolicyRejectsDotDotEscapes() throws {
    let sandbox = try makeTestSandbox()
    defer { cleanup(sandbox) }
    let policy = makePolicy(sandbox)

    expectPathViolation { try policy.resolve(path: "tmp:../escaped.txt") }
    expectPathViolation { try policy.resolve(path: "documents:a/../../escaped.txt") }
    expectPathViolation { try policy.resolve(path: "../escaped.txt") }
}

@Test func pathPolicyAllowsDotDotThatStaysInsideAllowedRoots() throws {
    let sandbox = try makeTestSandbox()
    defer { cleanup(sandbox) }
    let policy = makePolicy(sandbox)

    let url = try policy.resolve(path: "tmp:a/../b.txt")
    #expect(url.path == sandbox.tmp.resolvingSymlinksInPath().path + "/b.txt")
}

@Test func pathPolicyResolvesNonexistentNestedPaths() throws {
    let sandbox = try makeTestSandbox()
    defer { cleanup(sandbox) }
    let policy = makePolicy(sandbox)

    let url = try policy.resolve(path: "tmp:new/nested/dir/file.txt")
    #expect(url.path == sandbox.tmp.resolvingSymlinksInPath().path + "/new/nested/dir/file.txt")
}

@Test func pathPolicyRejectsSymlinksEscapingAllowedRoots() throws {
    let sandbox = try makeTestSandbox()
    defer { cleanup(sandbox) }
    let policy = makePolicy(sandbox)

    let outside = sandbox.root.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    let link = sandbox.tmp.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

    expectPathViolation { try policy.resolve(path: "tmp:link/secret.txt") }
    expectPathViolation { try policy.resolve(path: "tmp:link") }
}

@Test func pathPolicyAllowsSymlinksBetweenAllowedRoots() throws {
    let sandbox = try makeTestSandbox()
    defer { cleanup(sandbox) }
    let policy = makePolicy(sandbox)

    let link = sandbox.tmp.appendingPathComponent("docs-link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: sandbox.documents)

    let url = try policy.resolve(path: "tmp:docs-link/file.txt")
    #expect(url.path == sandbox.documents.resolvingSymlinksInPath().path + "/file.txt")
}
