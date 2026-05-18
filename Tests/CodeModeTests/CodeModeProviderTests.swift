import Foundation
import Testing
@testable import CodeMode

private struct ManualProvider: CodeModeProvider {
    let codeModePath = "myapp.api"

    func codeModeRegistrations() -> [CodeModeRegistration] {
        [
            CodeModeRegistration(
                capabilityKey: "myapp.api.doTheThing",
                jsPath: "myapp.api.doTheThing",
                title: "doTheThing",
                summary: "Do the thing.",
                tags: ["myapp", "api"],
                example: #"await myapp.api.doTheThing({ id: "123" })"#,
                requiredArguments: ["id"],
                argumentTypes: ["id": .string],
                argumentHints: ["id": "Thing identifier"],
                resultSummary: "Echoed identifier"
            ) { arguments, _ in
                .object([
                    "id": .string(try CodeModeArgumentDecoder.requireString("id", in: arguments)),
                    "done": .bool(true),
                ])
            },
            CodeModeRegistration(
                capabilityKey: "myapp.api.failInvalid",
                jsPath: "myapp.api.failInvalid",
                title: "failInvalid",
                summary: "Fail with custom invalid arguments.",
                example: "await myapp.api.failInvalid({})"
            ) { _, _ in
                throw CodeModeFunctionError.invalidArguments("Custom invalid argument")
            },
        ]
    }
}

@Test func customProviderAppearsInSearchCatalog() async throws {
    let (tools, sandbox) = try makeTools(codeModeProviders: [ManualProvider()])
    defer { cleanup(sandbox) }

    let response = try await tools.searchJavaScriptAPI(
        JavaScriptAPISearchRequest(
            code: """
            async () => {
                const ref = api.byJSName["myapp.api.doTheThing"];
                return {
                    capability: ref.capability,
                    jsNames: ref.jsNames,
                    summary: ref.summary,
                    requiredArguments: ref.requiredArguments,
                    argumentHints: ref.argumentHints
                };
            }
            """
        )
    )

    let result = try #require(response.result?.objectValue)
    #expect(result.string("capability") == "myapp.api.doTheThing")
    #expect(result.array("jsNames") == [.string("myapp.api.doTheThing")])
    #expect(result.string("summary") == "Do the thing.")
    #expect(result.array("requiredArguments") == [.string("id")])
    #expect(result.object("argumentHints")?.string("id") == "Thing identifier")
}

@Test func builtInCatalogUsesRegistrationJavaScriptNames() throws {
    let descriptor = CapabilityDescriptor(
        id: .weatherRead,
        title: "Weather",
        summary: "Read weather.",
        tags: ["weather"],
        example: "await custom.weather.current({ latitude: 0, longitude: 0 })",
        requiredArguments: ["latitude", "longitude"],
        resultSummary: "Weather payload"
    )
    let registry = CapabilityRegistry(
        registrations: [
            CapabilityRegistration(
                jsNames: ["custom.weather.current"],
                descriptor: descriptor
            ) { _, _ in
                .null
            },
        ]
    )

    let catalog = BridgeCatalog(registry: registry)
    let reference = try #require(catalog.reference(for: .weatherRead))
    #expect(reference.jsNames == ["custom.weather.current"])
    #expect(reference.summary == "Read weather.")
}

@Test func builtInRuntimeInstallsRegistrationBackedFallbackBindings() async throws {
    let descriptor = CapabilityDescriptor(
        id: .weatherRead,
        title: "Weather",
        summary: "Read weather.",
        tags: ["weather"],
        example: "await custom.weather.current({ latitude: 0, longitude: 0 })",
        requiredArguments: ["latitude", "longitude"],
        resultSummary: "Weather payload"
    )
    let registry = CapabilityRegistry(
        registrations: [
            CapabilityRegistration(
                jsNames: ["custom.weather.current"],
                descriptor: descriptor
            ) { arguments, _ in
                .object([
                    "latitude": arguments["latitude"] ?? .null,
                    "ok": .bool(true),
                ])
            },
        ]
    )
    let catalog = BridgeCatalog(registry: registry)
    let runtime = BridgeRuntime(registry: registry, catalog: catalog, config: .init())

    let call = runtime.makeExecutionCall(
        JavaScriptExecutionRequest(
            code: "return await custom.weather.current({ latitude: 12, longitude: 34 });",
            allowedCapabilities: [.weatherRead]
        )
    )
    let observed = await observe(call)
    let output = try #require(observed.result?.output?.objectValue)
    #expect(output["latitude"] == .number(12))
    #expect(output["ok"] == .bool(true))
}

@Test func metadataOnlyBuiltInHelpersInstallFromRegistrationMetadata() async throws {
    let metadataOnlyPrefixes = [
        "apple.vision.",
        "apple.notifications.",
        "ios.alarm.",
        "apple.health.",
        "apple.home.",
        "apple.media.",
        "apple.cloudkit.",
        "apple.speech.",
        "apple.appIntents.",
        "apple.foundationModels.",
        "apple.activity.",
        "apple.maps.",
        "apple.music.",
        "apple.wallet.",
        "apple.storekit.",
        "apple.fs.",
    ]
    func isMetadataOnly(_ jsName: String) -> Bool {
        metadataOnlyPrefixes.contains { jsName.hasPrefix($0) }
    }

    let registrations = DefaultCapabilityLoader.loadAllRegistrations()
        .compactMap { registration -> CapabilityRegistration? in
            let jsNames = registration.jsNames.filter(isMetadataOnly)
            guard jsNames.isEmpty == false else {
                return nil
            }
            return CapabilityRegistration(
                jsNames: jsNames,
                descriptor: registration.descriptor
            ) { _, _ in
                .object(["capability": .string(registration.descriptor.id.rawValue)])
            }
        }
    let jsNames = registrations.flatMap(\.jsNames).sorted()

    #expect(jsNames.isEmpty == false)
    for jsName in jsNames {
        #expect(RuntimeJavaScript.bootstrap.contains(jsName) == false)
    }

    let registry = CapabilityRegistry(registrations: registrations)
    let catalog = BridgeCatalog(registry: registry)
    let runtime = BridgeRuntime(registry: registry, catalog: catalog, config: .init(hostPlatform: .iOS))
    let checks = jsNames
        .map { name in "\(jsonString(name)): typeof \(name) === 'function'" }
        .joined(separator: ",\n")

    let call = runtime.makeExecutionCall(
        JavaScriptExecutionRequest(
            code: """
            return {
            \(checks)
            };
            """,
            allowedCapabilities: []
        )
    )
    let observed = await observe(call)
    let output = try #require(observed.result?.output?.objectValue)

    for jsName in jsNames {
        #expect(output[jsName] == .bool(true))
    }

    let macRuntime = BridgeRuntime(
        registry: registry,
        catalog: catalog,
        config: .init(hostPlatform: .macOS),
        unsupportedBuiltInJavaScriptNames: CapabilityPlatformSupport.unsupportedJavaScriptNames(
            from: registrations,
            for: .macOS
        )
    )
    let macCall = macRuntime.makeExecutionCall(
        JavaScriptExecutionRequest(
            code: """
            return {
                alarm: (typeof ios === 'undefined' || typeof ios.alarm === 'undefined') ? 'undefined' : typeof ios.alarm.schedule,
                cloudkit: typeof apple.cloudkit.queryRecords
            };
            """,
            allowedCapabilities: []
        )
    )
    let macObserved = await observe(macCall)
    let macOutput = try #require(macObserved.result?.output?.objectValue)
    #expect(macOutput["alarm"] == .string("undefined"))
    #expect(macOutput["cloudkit"] == .string("function"))
}

@Test func platformPruningCanUseRegistrationJavaScriptNames() throws {
    let descriptor = CapabilityDescriptor(
        id: .calendarUIPresentNewEvent,
        title: "Present New Event",
        summary: "Present a new event editor.",
        tags: ["calendar", "ui"],
        example: "await custom.calendar.presentNewEvent({ title: \"Plan\" })"
    )
    let registration = CapabilityRegistration(
        jsNames: ["custom.calendar.presentNewEvent"],
        descriptor: descriptor
    ) { _, _ in
        .null
    }

    #expect(
        CapabilityPlatformSupport.unsupportedJavaScriptNames(
            from: [registration],
            for: .macOS
        ) == ["custom.calendar.presentNewEvent"]
    )
    #expect(
        CapabilityPlatformSupport.unsupportedJavaScriptNames(
            from: [registration],
            for: .iOS
        ).isEmpty
    )
}

private func jsonString(_ value: String) -> String {
    guard let data = try? JSONEncoder.codeModeBridge.encode(value),
          let string = String(data: data, encoding: .utf8)
    else {
        return "\"\""
    }
    return string
}

@Test func customProviderRequiresAllowedCapabilityKey() async throws {
    let (tools, sandbox) = try makeTools(codeModeProviders: [ManualProvider()])
    defer { cleanup(sandbox) }

    let deniedCall = try await tools.executeJavaScript(
        JavaScriptExecutionRequest(
            code: #"return await myapp.api.doTheThing({ id: "123" });"#,
            allowedCapabilities: []
        )
    )
    let denied = await observe(deniedCall)
    let deniedError = try #require(denied.error)
    #expect(deniedError.code == "CAPABILITY_DENIED")
    #expect(deniedError.capabilityKey == "myapp.api.doTheThing")

    let allowedCall = try await tools.executeJavaScript(
        JavaScriptExecutionRequest(
            code: #"return await myapp.api.doTheThing({ id: "123" });"#,
            allowedCapabilities: [],
            allowedCapabilityKeys: ["myapp.api.doTheThing"]
        )
    )
    let allowed = await observe(allowedCall)
    let result = try #require(allowed.result?.output?.objectValue)
    #expect(result.string("id") == "123")
    #expect(result.bool("done") == true)
}

@Test func builtInCapabilitiesCanBeAllowedByCapabilityKey() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let call = try await tools.executeJavaScript(
        JavaScriptExecutionRequest(
            code: #"return await apple.keychain.get("missing-provider-key-test");"#,
            allowedCapabilities: [],
            allowedCapabilityKeys: [CapabilityID.keychainRead.codeModeKey]
        )
    )
    let observed = await observe(call)
    #expect(observed.result?.output == .null)
}

@Test func customProviderFunctionErrorsRemainStructured() async throws {
    let (tools, sandbox) = try makeTools(codeModeProviders: [ManualProvider()])
    defer { cleanup(sandbox) }

    let call = try await tools.executeJavaScript(
        JavaScriptExecutionRequest(
            code: "return await myapp.api.failInvalid({});",
            allowedCapabilities: [],
            allowedCapabilityKeys: ["myapp.api.failInvalid"]
        )
    )
    let observed = await observe(call)
    let error = try #require(observed.error)
    #expect(error.code == "INVALID_ARGUMENTS")
    #expect(error.message == "Custom invalid argument")
    #expect(error.capabilityKey == "myapp.api.failInvalid")
}

@Test func builtInAndCustomProvidersCoexist() async throws {
    let (tools, sandbox) = try makeTools(codeModeProviders: [ManualProvider()])
    defer { cleanup(sandbox) }

    let response = try await tools.searchJavaScriptAPI(
        JavaScriptAPISearchRequest(
            code: """
            async () => {
                return {
                    custom: api.byJSName["myapp.api.doTheThing"].capability,
                    builtIn: api.byJSName["apple.weather.getCurrentWeather"].capability
                };
            }
            """
        )
    )

    let result = try #require(response.result?.objectValue)
    #expect(result.string("custom") == "myapp.api.doTheThing")
    #expect(result.string("builtIn") == CapabilityID.weatherRead.rawValue)
}
