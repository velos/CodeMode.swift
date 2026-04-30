import Foundation
import Testing
@testable import CodeMode

private final class RecordingCodeModeFileSystem: CodeModeFileSystem, @unchecked Sendable {
    private let base = LocalCodeModeFileSystem()
    private let lock = NSLock()
    private var recordedCalls: [String] = []

    var calls: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCalls
    }

    func listDirectory(at url: URL) throws -> [CodeModeFileSystemEntry] {
        record("listDirectory")
        return try base.listDirectory(at: url)
    }

    func readData(at url: URL) throws -> Data {
        record("readData")
        return try base.readData(at: url)
    }

    func writeData(_ data: Data, to url: URL) throws {
        record("writeData")
        try base.writeData(data, to: url)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        record("moveItem")
        try base.moveItem(at: sourceURL, to: destinationURL)
    }

    func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        record("copyItem")
        try base.copyItem(at: sourceURL, to: destinationURL)
    }

    func removeItem(at url: URL) throws {
        record("removeItem")
        try base.removeItem(at: url)
    }

    func attributesOfItem(at url: URL) throws -> CodeModeFileSystemAttributes {
        record("attributesOfItem")
        return try base.attributesOfItem(at: url)
    }

    func createDirectory(at url: URL, recursive: Bool) throws {
        record("createDirectory")
        try base.createDirectory(at: url, recursive: recursive)
    }

    func itemExists(at url: URL) -> Bool {
        record("itemExists")
        return base.itemExists(at: url)
    }

    func access(at url: URL) -> CodeModeFileSystemAccess {
        record("access")
        return base.access(at: url)
    }

    private func record(_ call: String) {
        lock.lock()
        recordedCalls.append(call)
        lock.unlock()
    }
}

@Test func fileSystemRoundTripOperations() throws {
    let fs = FileSystemBridge()
    let (context, sandbox) = try makeInvocationContext()
    defer { cleanup(sandbox) }

    _ = try fs.write(arguments: [
        "path": .string("tmp:notes/hello.txt"),
        "data": .string("hello bridge"),
    ], context: context)

    let readValue = try fs.read(arguments: [
        "path": .string("tmp:notes/hello.txt"),
        "encoding": .string("utf8"),
    ], context: context)

    let readObject = try requireObject(readValue)
    #expect(readObject.string("text") == "hello bridge")

    let exists = try fs.exists(arguments: ["path": .string("tmp:notes/hello.txt")], context: context)
    #expect(exists.boolValue == true)

    let stat = try fs.stat(arguments: ["path": .string("tmp:notes/hello.txt")], context: context)
    let statObject = try requireObject(stat)
    #expect((statObject.double("size") ?? 0) > 0)

    let access = try fs.access(arguments: ["path": .string("tmp:notes/hello.txt")], context: context)
    let accessObject = try requireObject(access)
    #expect(accessObject.bool("readable") == true)

    let listing = try fs.list(arguments: ["path": .string("tmp:notes")], context: context)
    let items = try requireArray(listing)
    #expect(items.contains(where: {
        $0.objectValue?.string("name") == "hello.txt"
    }))
}

@Test func fileSystemCopyMoveDeleteAndMkdir() throws {
    let fs = FileSystemBridge()
    let (context, sandbox) = try makeInvocationContext()
    defer { cleanup(sandbox) }

    _ = try fs.mkdir(arguments: ["path": .string("tmp:workspace/sub"), "recursive": .bool(true)], context: context)

    _ = try fs.write(arguments: [
        "path": .string("tmp:workspace/a.txt"),
        "data": .string("abc"),
    ], context: context)

    _ = try fs.copy(arguments: [
        "from": .string("tmp:workspace/a.txt"),
        "to": .string("tmp:workspace/b.txt"),
    ], context: context)

    _ = try fs.move(arguments: [
        "from": .string("tmp:workspace/b.txt"),
        "to": .string("tmp:workspace/c.txt"),
    ], context: context)

    let movedExists = try fs.exists(arguments: ["path": .string("tmp:workspace/c.txt")], context: context)
    #expect(movedExists.boolValue == true)

    do {
        _ = try fs.delete(arguments: ["path": .string("tmp:workspace")], context: context)
        Issue.record("Expected delete without recursive=true to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    _ = try fs.delete(arguments: ["path": .string("tmp:workspace"), "recursive": .bool(true)], context: context)
    let deleted = try fs.exists(arguments: ["path": .string("tmp:workspace")], context: context)
    #expect(deleted.boolValue == false)
}

@Test func fileSystemRejectsInvalidEncodingAndDisallowedRoot() throws {
    let fs = FileSystemBridge()
    let (context, sandbox) = try makeInvocationContext()
    defer { cleanup(sandbox) }

    _ = try fs.write(arguments: [
        "path": .string("tmp:none.txt"),
        "data": .string("x"),
    ], context: context)

    do {
        _ = try fs.read(arguments: ["path": .string("tmp:none.txt"), "encoding": .string("utf16")], context: context)
        Issue.record("Expected unsupported encoding failure")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    do {
        _ = try fs.exists(arguments: ["path": .string("/etc/hosts")], context: context)
        Issue.record("Expected path policy violation")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PATH_POLICY_VIOLATION")
    }
}

@Test func executeUsesConfiguredFileSystemOperations() async throws {
    let fileSystem = RecordingCodeModeFileSystem()
    let (tools, sandbox) = try makeTools(fileSystem: fileSystem)
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            await apple.fs.write({ path: 'tmp:custom-fs.txt', data: 'configured' });
            const text = await fs.promises.readFile('tmp:custom-fs.txt', 'utf8');
            const stat = await fs.promises.stat('tmp:custom-fs.txt');
            const entries = await fs.promises.readdir('tmp:');
            return { text, size: stat.size, count: entries.length };
            """,
            allowedCapabilities: [.fsWrite, .fsRead, .fsStat, .fsList]
        )
    )

    let payload = try requireJSONObject(from: try #require(observed.result))
    #expect(payload["text"] as? String == "configured")
    #expect((payload["size"] as? Double ?? 0) > 0)
    #expect((payload["count"] as? Int ?? 0) > 0)

    let calls = Set(fileSystem.calls)
    #expect(calls.isSuperset(of: ["createDirectory", "writeData", "readData", "attributesOfItem", "listDirectory"]))
}

@Test func executeUsesFileSystemBridge() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            await apple.fs.write({ path: 'tmp:execute-fs.txt', data: 'fs-from-execute' });
            const text = await fs.promises.readFile('tmp:execute-fs.txt', 'utf8');
            return { text };
            """,
            allowedCapabilities: [.fsWrite, .fsRead]
        )
    )

    let payload = try requireJSONObject(from: try #require(observed.result))
    #expect(payload["text"] as? String == "fs-from-execute")
}
