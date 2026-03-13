import Foundation
import Testing
@testable import CodeMode

@Test func searchFiltersCatalogWithJavaScript() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let response = try await tools.searchJavaScriptAPI(
        JavaScriptAPISearchRequest(
            code: """
            async () => {
                return api.references
                    .filter(ref => ref.tags.includes("reminders"))
                    .map(ref => ({ capability: ref.capability, jsNames: ref.jsNames }));
            }
            """
        )
    )

    let results = try #require(response.result?.arrayValue)
    #expect(results.isEmpty == false)
    #expect(results.contains(where: { $0.objectValue?.string("capability") == CapabilityID.remindersWrite.rawValue }))
}

@Test func searchSupportsDirectJavaScriptAliasLookup() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let response = try await tools.searchJavaScriptAPI(
        JavaScriptAPISearchRequest(
            code: """
            async () => {
                return api.byJSName["fs.promises.readFile"];
            }
            """
        )
    )

    let result = try #require(response.result?.objectValue)
    #expect(result.string("capability") == CapabilityID.fsRead.rawValue)
    #expect(result.array("jsNames")?.contains(.string("fs.promises.readFile")) == true)
}

@Test func searchUsesAppleNamespaceAndDropsStaleIOSAliases() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let response = try await tools.searchJavaScriptAPI(
        JavaScriptAPISearchRequest(
            code: """
            async () => {
                return {
                    apple: api.byJSName["apple.fs.read"] ?? null,
                    staleIOS: api.byJSName["ios.fs.read"] ?? null
                };
            }
            """
        )
    )

    let result = try #require(response.result?.objectValue)
    #expect(result.object("apple")?.string("capability") == CapabilityID.fsRead.rawValue)
    #expect(result["staleIOS"] == .null)
}

@Test func searchHidesUnsupportedCapabilitiesForCurrentHostPlatform() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let response = try await tools.searchJavaScriptAPI(
        JavaScriptAPISearchRequest(
            code: """
            async () => {
                return {
                    locationPermission: api.byCapability["location.permission.request"] ?? null,
                    alarmSchedule: api.byCapability["alarm.schedule"] ?? null
                };
            }
            """
        )
    )

    let result = try #require(response.result?.objectValue)
    let locationPermission = result["locationPermission"]
    let alarmSchedule = result["alarmSchedule"]

    if CapabilityPlatformSupport.isSupported(.locationPermissionRequest, for: .current) {
        #expect(locationPermission != .null)
    } else {
        #expect(locationPermission == .null)
    }

    if CapabilityPlatformSupport.isSupported(.alarmSchedule, for: .current) {
        #expect(alarmSchedule != .null)
    } else {
        #expect(alarmSchedule == .null)
    }
}

@Test func searchSupportsDirectCapabilityLookup() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let response = try await tools.searchJavaScriptAPI(
        JavaScriptAPISearchRequest(
            code: """
            async () => {
                return api.byCapability["calendar.write"];
            }
            """
        )
    )

    let result = try #require(response.result?.objectValue)
    #expect(result.string("capability") == CapabilityID.calendarWrite.rawValue)
    #expect(result.array("requiredArguments")?.contains(.string("title")) == true)
    #expect(result.array("requiredArguments")?.contains(.string("start")) == true)
    #expect(result.array("requiredArguments")?.contains(.string("end")) == true)
}

@Test func searchReturnsProjectedResults() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let response = try await tools.searchJavaScriptAPI(
        JavaScriptAPISearchRequest(
            code: """
            async () => {
                return api.references
                    .filter(ref => ref.capability.startsWith("fs."))
                    .slice(0, 3)
                    .map(ref => ({
                        capability: ref.capability,
                        helper: ref.jsNames[0],
                        requiredArguments: ref.requiredArguments
                    }));
            }
            """
        )
    )

    let results = try #require(response.result?.arrayValue)
    #expect(results.count == 3)
    #expect(results.allSatisfy { $0.objectValue?.string("capability")?.hasPrefix("fs.") == true })
}

@Test func searchRejectsEmptyInput() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    await #expect(throws: CodeModeToolError.self) {
        _ = try await tools.searchJavaScriptAPI(JavaScriptAPISearchRequest(code: ""))
    }
}

@Test func searchEmitsConsoleDiagnostics() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let response = try await tools.searchJavaScriptAPI(
        JavaScriptAPISearchRequest(
            code: """
            async () => {
                console.warn("searching reminders");
                return api.byCapability["reminders.write"];
            }
            """
        )
    )

    #expect(response.result?.objectValue?.string("capability") == CapabilityID.remindersWrite.rawValue)
    #expect(response.diagnostics.contains(where: {
        $0.code == "SEARCH_CONSOLE" && $0.message.contains("searching reminders")
    }))
}

@Test func executeRejectsDisallowedCapabilitiesAsToolError() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return await apple.fs.read({ path: 'tmp:blocked.txt' });",
            allowedCapabilities: []
        )
    )

    #expect(observed.result == nil)
    #expect(observed.error?.code == "CAPABILITY_DENIED")
    #expect(observed.events.contains(where: {
        if case .toolError(let error) = $0 {
            return error.code == "CAPABILITY_DENIED"
        }
        return false
    }))
}

@Test func executeEmitsSyntaxErrorsAsTerminalEvents() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "const value = ;",
            allowedCapabilities: []
        )
    )

    #expect(observed.result == nil)
    #expect(observed.error?.code == "JS_SYNTAX_ERROR")
    #expect(observed.error?.line != nil)
    #expect(observed.events.contains(where: {
        if case .syntaxError(let error) = $0 {
            return error.code == "JS_SYNTAX_ERROR"
        }
        return false
    }))
}

@Test func executeClassifiesMissingJavaScriptHelpers() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return await apple.fs.reed({ path: 'tmp:file.txt' });",
            allowedCapabilities: [.fsRead]
        )
    )

    #expect(observed.result == nil)
    #expect(observed.error?.code == "JS_API_NOT_FOUND")
    #expect(observed.error?.functionName == "apple.fs.reed")
    #expect(observed.error?.suggestions.contains("apple.fs.read") == true)
    #expect(observed.events.contains(where: {
        if case .functionNotFound(let error) = $0 {
            return error.code == "JS_API_NOT_FOUND"
        }
        return false
    }))
}

@Test func executeSurfacesThrownJavaScriptErrors() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "throw new Error('boom');",
            allowedCapabilities: []
        )
    )

    #expect(observed.result == nil)
    #expect(observed.error?.code == "JS_RUNTIME_ERROR")
    #expect(observed.error?.message.contains("boom") == true)
    #expect(observed.events.contains(where: {
        if case .thrownError(let error) = $0 {
            return error.message.contains("boom")
        }
        return false
    }))
}

@Test func executeKeepsGenericReferenceErrorsAsThrownErrors() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return missingVariable;",
            allowedCapabilities: []
        )
    )

    #expect(observed.result == nil)
    #expect(observed.error?.code == "JS_RUNTIME_ERROR")
    #expect(observed.events.contains(where: {
        if case .thrownError(let error) = $0 {
            return error.code == "JS_RUNTIME_ERROR"
        }
        return false
    }))
    #expect(observed.events.contains(where: {
        if case .functionNotFound = $0 {
            return true
        }
        return false
    }) == false)
}

@Test func pathTraversalIsBlockedAsToolError() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return await apple.fs.write({ path: 'tmp:../escape.txt', data: 'x' });",
            allowedCapabilities: [.fsWrite]
        )
    )

    #expect(observed.result == nil)
    #expect(observed.error?.code == "PATH_POLICY_VIOLATION")
}

@Test func appleFSAndNodeAliasesMatch() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            await apple.fs.write({ path: 'tmp:alias.txt', data: 'hello world' });
            const appleRead = await apple.fs.read({ path: 'tmp:alias.txt' });
            const nodeRead = await fs.promises.readFile('tmp:alias.txt', 'utf8');
            return { apple: appleRead.text, node: nodeRead };
            """,
            allowedCapabilities: [.fsWrite, .fsRead]
        )
    )

    let result = try #require(observed.result)
    let payload = try requireJSONObject(from: result)
    #expect(payload["apple"] as? String == "hello world")
    #expect(payload["node"] as? String == "hello world")
    #expect(observed.events.last == .finished)
}

@Test func executeSupportsLoopDrivenBridgeCalls() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            for (let i = 0; i < 5; i++) {
              await apple.fs.write({ path: `tmp:loop-${i}.txt`, data: `v${i}` });
            }
            const files = await apple.fs.list({ path: 'tmp:' });
            const loopFiles = files.filter(f => f.name.startsWith('loop-'));
            return { count: loopFiles.length };
            """,
            allowedCapabilities: [.fsWrite, .fsList]
        )
    )

    let payload = try requireJSONObject(from: try #require(observed.result))
    #expect((payload["count"] as? Int ?? 0) >= 5)
}

@Test func executeSupportsPromiseAllAndNodeAlias() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            const names = ['a', 'b', 'c', 'd'];
            await Promise.all(names.map((n, i) => fs.promises.writeFile(`tmp:${n}.txt`, `item-${i}`, 'utf8')));
            const values = await Promise.all(names.map((n) => fs.promises.readFile(`tmp:${n}.txt`, 'utf8')));
            return { names, values, combined: values.join('|') };
            """,
            allowedCapabilities: [.fsWrite, .fsRead]
        )
    )

    let payload = try requireJSONObject(from: try #require(observed.result))
    let values = payload["values"] as? [String] ?? []
    #expect(values.count == 4)
    #expect(payload["combined"] as? String == "item-0|item-1|item-2|item-3")
}

@Test func executeStreamsConsoleLogsBeforeFinish() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            console.log('first-log');
            console.warn('second-log');
            return { ok: true };
            """,
            allowedCapabilities: []
        )
    )

    let logMessages = observed.events.compactMap { event -> String? in
        if case .log(let entry) = event {
            return entry.message
        }
        return nil
    }

    #expect(logMessages.contains(where: { $0.contains("first-log") }))
    #expect(logMessages.contains(where: { $0.contains("second-log") }))
    #expect(observed.events.last == .finished)
}

@Test func executeReturnsNilOutputWhenScriptOmitsReturnValue() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            const value = 42;
            console.log('ran', value);
            """,
            allowedCapabilities: []
        )
    )

    let result = try #require(observed.result)
    #expect(result.output == nil)
    #expect(observed.events.last == .finished)
}

@Test func executeTimesOutOnUnresolvedPromise() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            await new Promise(() => {});
            return { never: true };
            """,
            allowedCapabilities: [],
            timeoutMs: 50
        )
    )

    #expect(observed.result == nil)
    #expect(observed.error?.code == "EXECUTION_TIMEOUT")
}

@Test func executeRecordsPermissionEventsOnFailures() async throws {
    let broker = FixedPermissionBroker(statuses: [.locationWhenInUse: .denied])
    let (tools, sandbox) = try makeTools(permissionBroker: broker)
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return await apple.location.getCurrentPosition();",
            allowedCapabilities: [.locationRead]
        )
    )

    #expect(observed.result == nil)
    #expect(observed.error?.code == "PERMISSION_DENIED")
    #expect(observed.error?.permissionEvents.contains(where: { $0.permission == .locationWhenInUse }) == true)
}

@Test func executeInvalidArgumentsIncludeStructuredSuggestions() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return await apple.weather.getCurrentWeather({ latitude: 37.77 });",
            allowedCapabilities: [.weatherRead]
        )
    )

    #expect(observed.result == nil)
    #expect(observed.error?.code == "INVALID_ARGUMENTS")
    #expect(observed.error?.suggestions.contains(where: { $0.contains("latitude:number") }) == true)
    #expect(observed.error?.suggestions.contains(where: { $0.contains("Example:") }) == true)
}

@Test func executeCanBeCancelledExplicitly() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let call = try await tools.executeJavaScript(
        JavaScriptExecutionRequest(
            code: """
            await new Promise(() => {});
            return { never: true };
            """,
            allowedCapabilities: []
        )
    )

    call.cancel()
    let observed = await observe(call)

    #expect(observed.result == nil)
    #expect(observed.error?.code == "CANCELLED")
    #expect(observed.events.contains(where: {
        if case .toolError(let error) = $0 {
            return error.code == "CANCELLED"
        }
        return false
    }))
}

@Test func executeCancelsWhenAwaitingTaskIsCancelled() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let call = try await tools.executeJavaScript(
        JavaScriptExecutionRequest(
            code: """
            await new Promise(() => {});
            return { never: true };
            """,
            allowedCapabilities: []
        )
    )

    let waiter = Task<Result<JavaScriptExecutionResult, CodeModeToolError>, Never> {
        do {
            return .success(try await call.result)
        } catch let error as CodeModeToolError {
            return .failure(error)
        } catch {
            return .failure(CodeModeToolError(code: "INTERNAL_FAILURE", message: error.localizedDescription))
        }
    }

    await Task.yield()
    waiter.cancel()
    let waiterResult = await waiter.value

    switch waiterResult {
    case .success:
        #expect(Bool(false))
    case let .failure(error):
        #expect(error.code == "CANCELLED")
    }

    let observed = await observe(call)
    #expect(observed.result == nil)
    #expect(observed.error?.code == "CANCELLED")
}
