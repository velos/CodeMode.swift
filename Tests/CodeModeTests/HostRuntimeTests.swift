import Foundation
import Testing
@testable import CodeMode

@Test func searchFindsReminderCapabilities() async throws {
    let (host, sandbox) = try makeHost()
    defer { cleanup(sandbox) }

    let response = try await host.search(
        SearchRequest(
            mode: .discover,
            query: "create reminder",
            limit: 10
        )
    )

    #expect(response.items.isEmpty == false)
    #expect(response.items.contains(where: { $0.capability == .remindersWrite }))
}

@Test func searchSupportsTagFiltering() async throws {
    let (host, sandbox) = try makeHost()
    defer { cleanup(sandbox) }

    let response = try await host.search(
        SearchRequest(mode: .discover, query: "media", limit: 20, tags: ["media"])
    )

    #expect(response.items.isEmpty == false)
    #expect(response.items.allSatisfy { $0.tags.contains("media") })
}

@Test func searchDescribeReturnsCapabilityDetails() async throws {
    let (host, sandbox) = try makeHost()
    defer { cleanup(sandbox) }

    let response = try await host.search(
        SearchRequest(mode: .describe, capability: .calendarWrite)
    )

    #expect(response.diagnostics.isEmpty)
    #expect(response.detail?.capability == .calendarWrite)
    #expect(response.detail?.requiredArguments.contains("title") == true)
    #expect(response.detail?.requiredArguments.contains("start") == true)
    #expect(response.detail?.requiredArguments.contains("end") == true)
    #expect(response.detail?.argumentTypes["start"] == .string)
}

@Test func searchDescribeRequiresCapability() async throws {
    let (host, sandbox) = try makeHost()
    defer { cleanup(sandbox) }

    let response = try await host.search(
        SearchRequest(mode: .describe)
    )

    #expect(response.items.isEmpty)
    #expect(response.detail == nil)
    #expect(response.diagnostics.contains(where: { $0.code == "INVALID_REQUEST" }))
}

@Test func executeRejectsDisallowedCapabilities() async throws {
    let (host, sandbox) = try makeHost()
    defer { cleanup(sandbox) }

    let response = try await host.execute(
        ExecuteRequest(
            code: "return await ios.fs.read({ path: 'tmp:blocked.txt' });",
            allowedCapabilities: []
        )
    )

    #expect(response.diagnostics.contains(where: { $0.code == "CAPABILITY_DENIED" }))
}

@Test func executeSurfacesJavaScriptRejection() async throws {
    let (host, sandbox) = try makeHost()
    defer { cleanup(sandbox) }

    let response = try await host.execute(
        ExecuteRequest(
            code: "throw new Error('boom');",
            allowedCapabilities: [.fsRead]
        )
    )

    #expect(response.diagnostics.contains(where: { $0.message.contains("boom") }))
}

@Test func pathTraversalIsBlocked() async throws {
    let (host, sandbox) = try makeHost()
    defer { cleanup(sandbox) }

    let response = try await host.execute(
        ExecuteRequest(
            code: "return await ios.fs.write({ path: 'tmp:../escape.txt', data: 'x' });",
            allowedCapabilities: [.fsWrite]
        )
    )

    #expect(response.diagnostics.contains(where: { $0.code == "PATH_POLICY_VIOLATION" }))
}

@Test func iosFSAndNodeAliasesMatch() async throws {
    let (host, sandbox) = try makeHost()
    defer { cleanup(sandbox) }

    let response = try await host.execute(
        ExecuteRequest(
            code: """
            await ios.fs.write({ path: 'tmp:alias.txt', data: 'hello world' });
            const iosRead = await ios.fs.read({ path: 'tmp:alias.txt' });
            const nodeRead = await fs.promises.readFile('tmp:alias.txt', 'utf8');
            return { ios: iosRead.text, node: nodeRead };
            """,
            allowedCapabilities: [.fsWrite, .fsRead]
        )
    )

    #expect(response.diagnostics.isEmpty)

    let payload = try requireJSONObject(from: response)
    #expect(payload["ios"] as? String == "hello world")
    #expect(payload["node"] as? String == "hello world")
}

@Test func executeSupportsLoopDrivenBridgeCalls() async throws {
    let (host, sandbox) = try makeHost()
    defer { cleanup(sandbox) }

    let response = try await host.execute(
        ExecuteRequest(
            code: """
            let total = 0;
            for (let i = 0; i < 5; i++) {
              await ios.fs.write({ path: `tmp:loop-${i}.txt`, data: `v${i}` });
            }
            const files = await ios.fs.list({ path: 'tmp:' });
            const loopFiles = files.filter(f => f.name.startsWith('loop-'));
            return { count: loopFiles.length };
            """,
            allowedCapabilities: [.fsWrite, .fsList]
        )
    )

    #expect(response.diagnostics.isEmpty)
    let payload = try requireJSONObject(from: response)
    #expect((payload["count"] as? Int ?? 0) >= 5)
}

@Test func executeSupportsPromiseAllAndNodeAlias() async throws {
    let (host, sandbox) = try makeHost()
    defer { cleanup(sandbox) }

    let response = try await host.execute(
        ExecuteRequest(
            code: """
            const names = ['a', 'b', 'c', 'd'];
            await Promise.all(names.map((n, i) => fs.promises.writeFile(`tmp:${n}.txt`, `item-${i}`, 'utf8')));
            const values = await Promise.all(names.map((n) => fs.promises.readFile(`tmp:${n}.txt`, 'utf8')));
            return { names, values, combined: values.join('|') };
            """,
            allowedCapabilities: [.fsWrite, .fsRead]
        )
    )

    #expect(response.diagnostics.isEmpty)
    let payload = try requireJSONObject(from: response)
    let values = payload["values"] as? [String] ?? []
    #expect(values.count == 4)
    #expect(payload["combined"] as? String == "item-0|item-1|item-2|item-3")
}

@Test func executeCapturesConsoleLogs() async throws {
    let (host, sandbox) = try makeHost()
    defer { cleanup(sandbox) }

    let response = try await host.execute(
        ExecuteRequest(
            code: """
            console.log('first-log');
            console.warn('second-log');
            return { ok: true };
            """,
            allowedCapabilities: []
        )
    )

    #expect(response.diagnostics.isEmpty)
    #expect(response.logs.contains(where: { $0.message.contains("first-log") }))
    #expect(response.logs.contains(where: { $0.message.contains("second-log") }))
}

@Test func executeTimesOutOnUnresolvedPromise() async throws {
    let (host, sandbox) = try makeHost()
    defer { cleanup(sandbox) }

    let response = try await host.execute(
        ExecuteRequest(
            code: """
            await new Promise(() => {});
            return { never: true };
            """,
            allowedCapabilities: [],
            timeoutMs: 50
        )
    )

    #expect(response.diagnostics.contains(where: { $0.code == "EXECUTION_TIMEOUT" }))
}

@Test func executeRecordsPermissionEvents() async throws {
    let broker = FixedPermissionBroker(statuses: [.locationWhenInUse: .denied])
    let (host, sandbox) = try makeHost(permissionBroker: broker)
    defer { cleanup(sandbox) }

    let response = try await host.execute(
        ExecuteRequest(
            code: "return await ios.location.getCurrentPosition();",
            allowedCapabilities: [.locationRead]
        )
    )

    #expect(response.diagnostics.contains(where: { $0.code == "PERMISSION_DENIED" }))
    #expect(response.permissionEvents.contains(where: { $0.permission == .locationWhenInUse }))
}

@Test func executeInvalidArgumentsIncludesUsageHint() async throws {
    let (host, sandbox) = try makeHost()
    defer { cleanup(sandbox) }

    let response = try await host.execute(
        ExecuteRequest(
            code: "return await ios.weather.getCurrentWeather({ latitude: 37.77 });",
            allowedCapabilities: [.weatherRead]
        )
    )

    #expect(response.diagnostics.contains(where: { $0.code == "INVALID_ARGUMENTS" }))
    #expect(response.diagnostics.contains(where: { $0.message.contains("Hint:") }))
    #expect(response.diagnostics.contains(where: { $0.message.contains("required: latitude:number, longitude:number") }))
}
