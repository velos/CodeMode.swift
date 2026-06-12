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

@Test func everyBuiltInJavaScriptNameInvokesRegistrationOwnedCapabilityAndPrunesUnsupportedNames() async throws {
    let invocations = SynchronizedBox<[String]>([])
    let allRegistrations = DefaultCapabilityLoader.loadAllRegistrations()
    let fakeRegistrations = allRegistrations.map { registration in
        CapabilityRegistration(
            jsNames: registration.jsNames,
            descriptor: registration.descriptor
        ) { _, _ in
            invocations.mutate { $0.append(registration.descriptor.id.rawValue) }
            return fakeRuntimeValue(for: registration.descriptor.id)
        }
    }
    let checks = fakeRegistrations
        .flatMap { registration in
            registration.jsNames.map { jsName in
                BuiltInJavaScriptBindingCheck(
                    jsName: jsName,
                    descriptor: registration.descriptor
                )
            }
        }
        .sorted { $0.jsName < $1.jsName }

    #expect(checks.isEmpty == false)

    let registry = CapabilityRegistry(registrations: fakeRegistrations)
    let catalog = BridgeCatalog(registry: registry)
    let permissionBroker = FixedPermissionBroker(
        statuses: Dictionary(uniqueKeysWithValues: PermissionKind.allCases.map { ($0, PermissionStatus.granted) })
    )
    let runtime = BridgeRuntime(
        registry: registry,
        catalog: catalog,
        config: .init(permissionBroker: permissionBroker, hostPlatform: .iOS)
    )
    let statements = checks.map { check in
        """
        try {
            await \(javaScriptInvocation(for: check.jsName, descriptor: check.descriptor));
        } catch (error) {
            failures.push({
                jsName: \(jsonString(check.jsName)),
                code: error && error.code ? String(error.code) : null,
                message: error && error.message ? String(error.message) : String(error)
            });
        }
        """
    }.joined(separator: "\n")

    let call = runtime.makeExecutionCall(
        JavaScriptExecutionRequest(
            code: """
            const failures = [];
            \(statements)
            return { failures };
            """,
            allowedCapabilities: Array(CapabilityID.allCases),
            timeoutMs: 20_000
        )
    )
    let observed = await observe(call)
    let output = try #require(observed.result?.output?.objectValue)
    #expect(output.array("failures") == [])
    #expect(invocations.get() == checks.map { $0.descriptor.id.rawValue })

    let macRegistrations = CapabilityPlatformSupport.filter(fakeRegistrations, for: .macOS)
    let unsupportedMacNames = CapabilityPlatformSupport.unsupportedJavaScriptNames(from: fakeRegistrations, for: .macOS)
    #expect(unsupportedMacNames.isEmpty == false)

    let macRegistry = CapabilityRegistry(registrations: macRegistrations)
    let macRuntime = BridgeRuntime(
        registry: macRegistry,
        catalog: BridgeCatalog(registry: macRegistry),
        config: .init(permissionBroker: permissionBroker, hostPlatform: .macOS),
        unsupportedBuiltInJavaScriptNames: unsupportedMacNames
    )
    let unsupportedChecks = unsupportedMacNames
        .sorted()
        .map { name in "\(jsonString(name)): __typeOfPath(\(jsonString(name)))" }
        .joined(separator: ",\n")
    let macCall = macRuntime.makeExecutionCall(
        JavaScriptExecutionRequest(
            code: """
            function __typeOfPath(path) {
                const parts = String(path).split('.').filter(function(part){ return part.length > 0; });
                let value = globalThis;
                for (let i = 0; i < parts.length; i++) {
                    if (!value || typeof value[parts[i]] === 'undefined') return 'undefined';
                    value = value[parts[i]];
                }
                return typeof value;
            }
            return {
            \(unsupportedChecks)
            };
            """,
            allowedCapabilities: []
        )
    )
    let macObserved = await observe(macCall)
    let macOutput = try #require(macObserved.result?.output?.objectValue)
    for name in unsupportedMacNames {
        #expect(macOutput[name] == .string("undefined"))
    }
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

private struct BuiltInJavaScriptBindingCheck {
    var jsName: String
    var descriptor: CapabilityDescriptor
}

private func javaScriptInvocation(for jsName: String, descriptor: CapabilityDescriptor) -> String {
    switch jsName {
    case "fetch":
        return #"fetch("https://example.com", {})"#
    case "fs.promises.readFile":
        return #"fs.promises.readFile("tmp:input.txt", "utf8")"#
    case "fs.promises.writeFile":
        return #"fs.promises.writeFile("tmp:output.txt", "data", "utf8")"#
    case "fs.promises.readdir":
        return #"fs.promises.readdir("tmp:")"#
    case "fs.promises.stat":
        return #"fs.promises.stat("tmp:input.txt")"#
    case "fs.promises.access":
        return #"fs.promises.access("tmp:input.txt")"#
    case "fs.promises.mkdir":
        return #"fs.promises.mkdir("tmp:folder", { recursive: true })"#
    case "fs.promises.rm":
        return #"fs.promises.rm("tmp:input.txt", { recursive: true })"#
    case "fs.promises.rename":
        return #"fs.promises.rename("tmp:from.txt", "tmp:to.txt")"#
    case "fs.promises.copyFile":
        return #"fs.promises.copyFile("tmp:from.txt", "tmp:to.txt")"#
    case "apple.keychain.get":
        return #"apple.keychain.get("sample-key")"#
    case "apple.keychain.set":
        return #"apple.keychain.set("sample-key", "sample-value")"#
    case "apple.keychain.delete":
        return #"apple.keychain.delete("sample-key")"#
    case "apple.location.getPermissionStatus",
         "apple.location.requestPermission",
         "apple.location.getCurrentPosition":
        return "\(jsName)()"
    default:
        return "\(jsName)(\(jsonLiteral(sampleArguments(for: descriptor))))"
    }
}

private func sampleArguments(for descriptor: CapabilityDescriptor) -> JSONValue {
    let fields = descriptor.requiredArguments.reduce(into: [String: JSONValue]()) { result, name in
        result[name] = sampleArgumentValue(name: name, type: descriptor.argumentTypes[name])
    }
    return .object(fields)
}

private func sampleArgumentValue(name: String, type: CapabilityArgumentType?) -> JSONValue {
    switch name {
    case "url":
        return .string("https://example.com")
    case "path":
        return .string("tmp:input.txt")
    case "from":
        return .string("tmp:from.txt")
    case "to":
        return .string("tmp:to.txt")
    case "key":
        return .string("sample-key")
    case "latitude":
        return .number(37.7749)
    case "longitude":
        return .number(-122.4194)
    case "start":
        return .string("2026-01-01T00:00:00Z")
    case "end":
        return .string("2026-01-01T01:00:00Z")
    case "title":
        return .string("Sample")
    case "identifier", "localIdentifier", "recordName", "subscriptionID", "productID", "paymentRequestID",
         "accessoryIdentifier", "characteristicType", "type", "name":
        return .string("sample-id")
    case "recordType":
        return .string("Task")
    case "fields":
        if type == .array {
            return .array([
                .object([
                    "id": .string("name"),
                    "label": .string("Name"),
                ]),
            ])
        }
        return .object(["title": .string("Sample")])
    case "categories":
        return .array([
            .object([
                "identifier": .string("task"),
                "actions": .array([
                    .object([
                        "identifier": .string("done"),
                        "title": .string("Done"),
                    ]),
                ]),
            ]),
        ])
    case "buttons":
        return .array([
            .object([
                "id": .string("ok"),
                "title": .string("OK"),
            ]),
        ])
    case "activityType":
        return .string("delivery")
    case "attributes", "contentState", "parameters":
        return .object([:])
    case "origin":
        return .object(["latitude": .number(37.7749), "longitude": .number(-122.4194)])
    case "destination":
        return .object(["latitude": .number(37.7849), "longitude": .number(-122.4094)])
    case "address":
        return .string("1 Market St, San Francisco, CA")
    case "query", "term", "input", "prompt":
        return .string("sample")
    case "productIDs":
        return .array([.string("product.sample")])
    case "confirmed":
        return .bool(true)
    case "action":
        return .string("play")
    default:
        break
    }

    switch type {
    case .string:
        return .string("sample")
    case .number:
        return .number(1)
    case .bool:
        return .bool(true)
    case .object:
        return .object([:])
    case .array:
        return .array([])
    case .any, .none:
        return .string("sample")
    }
}

private func fakeRuntimeValue(for capability: CapabilityID) -> JSONValue {
    switch capability {
    case .networkFetch:
        return .object([
            "ok": .bool(true),
            "status": .number(200),
            "statusText": .string("OK"),
            "headers": .object([:]),
            "bodyText": .string("{}"),
            "bodyBase64": .string("e30="),
        ])
    case .fsRead:
        return .object([
            "path": .string("tmp:input.txt"),
            "text": .string("sample"),
            "base64": .string("c2FtcGxl"),
        ])
    case .fsList:
        return .array([])
    case .fsStat:
        return .object([
            "path": .string("tmp:input.txt"),
            "isDirectory": .bool(false),
            "size": .number(0),
        ])
    default:
        return .object(["ok": .bool(true)])
    }
}

private func jsonLiteral(_ value: JSONValue) -> String {
    guard let data = try? JSONEncoder.codeModeBridge.encode(value),
          let string = String(data: data, encoding: .utf8)
    else {
        return "{}"
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
