import Foundation
import Testing
@testable import CodeMode

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
