import Foundation
import Testing
@testable import CodeMode

// Cloudflare's central Code Mode insight is that models write markedly better
// code against real types. Before this the model got a flat `argumentTypes` map
// of six coarse cases plus a prose `resultSummary`; these tests pin the shape of
// what it gets now.

private func reference(
    capability: String = "fs.read",
    jsNames: [String] = ["apple.fs.read", "fs.promises.readFile"],
    required: [String] = ["path"],
    optional: [String] = ["encoding"],
    types: [String: CapabilityArgumentType] = ["path": .string, "encoding": .string],
    hints: [String: String] = ["path": "File path using allowed root prefix."],
    constraints: CapabilityArgumentConstraints = .init(allowedStringValues: ["encoding": ["utf8", "base64"]])
) -> JavaScriptAPIReference {
    JavaScriptAPIReference(
        capability: capability,
        jsNames: jsNames,
        summary: "Read a file.",
        tags: ["fs"],
        example: "await apple.fs.read({ path: 'tmp:x.txt' })",
        requiredArguments: required,
        optionalArguments: optional,
        argumentTypes: types,
        argumentHints: hints,
        argumentConstraints: constraints,
        resultSummary: "Object with path plus text or base64."
    )
}

@Test func declarationsTypeArgumentsAndCarryHintsAsDocComments() {
    let dts = TypeScriptDeclarations.declaration(for: reference())

    #expect(dts.contains("path: string;"))
    #expect(dts.contains("/** File path using allowed root prefix. */"))
    // Required vs optional is expressed in the type, not left to prose.
    #expect(dts.contains("encoding?:"))
    #expect(dts.contains("path?:") == false)
    #expect(dts.contains("Capability: fs.read"))
    #expect(dts.contains("Returns: Object with path plus text or base64."))
}

@Test func constrainedArgumentsBecomeStringLiteralUnions() {
    let dts = TypeScriptDeclarations.declaration(for: reference())
    // The constraint IS the type; a union beats `string` plus a prose hint the
    // model has to notice and obey.
    #expect(dts.contains(#"encoding?: "utf8" | "base64";"#))
}

@Test func nodeStyleAliasesAreDocumentedRatherThanMistypedAsObjectCalls() {
    let dts = TypeScriptDeclarations.declaration(for: reference())
    // `fs.promises.readFile` is positional, which the catalog cannot express, so
    // the generated signature must describe the namespaced helper and only
    // mention the alias.
    #expect(dts.contains("Aliases: fs.promises.readFile"))
    #expect(dts.contains("positional"))
}

@Test func dottedArgumentPathsBecomeNestedObjectTypes() {
    let nested = reference(
        capability: "network.fetch",
        jsNames: ["fetch"],
        required: ["url"],
        optional: ["options.method", "options.timeoutMs"],
        types: ["url": .string, "options.method": .string, "options.timeoutMs": .number],
        hints: ["options.method": "HTTP method; defaults to GET."],
        constraints: .none
    )
    let dts = TypeScriptDeclarations.declaration(for: nested)

    #expect(dts.contains("options?: {"))
    #expect(dts.contains("method?: string;"))
    #expect(dts.contains("timeoutMs?: number;"))
}

@Test func argumentlessHelpersTakeNoArgument() {
    let none = reference(
        capability: "location.permission.request",
        jsNames: ["apple.location.requestPermission"],
        required: [],
        optional: [],
        types: [:],
        hints: [:],
        constraints: .none
    )
    #expect(TypeScriptDeclarations.declaration(for: none).contains("(): Promise<CodeModeValue>"))
}

@Test func theWholeSurfaceIsNamespacedAndPlatformFiltered() async throws {
    let (tools, sandbox) = try makeTools(hostPlatform: .macOS)
    defer { cleanup(sandbox) }

    let surface = tools.typeDeclarations()

    #expect(surface.contains("declare const apple: {"))
    #expect(surface.contains("fs: {"))
    #expect(surface.contains("read(args: {"))
    // The Node-compat globals live in the hand-authored preamble, because their
    // positional convention is not something the catalog can describe.
    #expect(surface.contains("declare function fetch("))
    #expect(surface.contains("type CodeModeValue ="))
    // iOS-only helpers must not be declared for a macOS host.
    #expect(surface.contains("alarm: {") == false)
}

@Test func iOSOnlyHelpersAppearForAniOSHost() async throws {
    let (tools, sandbox) = try makeTools(hostPlatform: .iOS)
    defer { cleanup(sandbox) }
    #expect(tools.typeDeclarations().contains("alarm: {"))
}

@Test func everyCapabilityCarriesItsOwnDeclarationForSearchResults() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let references = tools.capabilities()
    #expect(references.isEmpty == false)
    #expect(references.allSatisfy { $0.dts.isEmpty == false })

    let read = try #require(references.first { $0.capability == "fs.read" })
    #expect(read.dts.contains("path: string;"))
}

@Test func searchCanReturnDeclarationsAsItsPayload() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    // Code-driven search stays the filter; the payload is now TypeScript.
    let response = try await tools.searchJavaScriptAPI(
        JavaScriptAPISearchRequest(
            code: """
            async () => {
                return api.references
                    .filter(ref => ref.tags.includes("filesystem"))
                    .map(ref => ref.dts)
                    .join("\\n\\n");
            }
            """
        )
    )
    let payload = try #require(response.result?.stringValue)
    #expect(payload.contains("declare const apple: {"))
    #expect(payload.contains("read(args: {"))
    #expect(payload.contains("path: string;"))
}

@Test func nodeAliasesCanPassTheOverwriteFlagTheDeclarationPromises() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    // fs.move/fs.copy now refuse an existing destination without an explicit
    // overwrite, so the Node-style aliases had to gain a way to pass one — the
    // preamble declares it, and this proves the runtime honours it.
    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            await apple.fs.write({ path: 'tmp:src.txt', data: 'source' });
            await apple.fs.write({ path: 'tmp:dst.txt', data: 'destination' });
            await fs.promises.copyFile('tmp:src.txt', 'tmp:dst.txt', { overwrite: true });
            return await fs.promises.readFile('tmp:dst.txt', 'utf8');
            """,
            allowedCapabilities: [.fsWrite, .fsRead, .fsCopy]
        )
    )

    #expect(observed.error == nil)
    #expect(observed.result?.output == .string("source"))
}

@Test(.enabled(if: keychainIsAvailable, "no keychain entitlement in this test host (errSecMissingEntitlement)")) func keychainHelpersAcceptTheObjectFormTheCatalogAdvertises() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    // The catalog declared `key: string` as an object argument while the wrapper
    // took a positional string, and its own example showed the positional form —
    // so code written from the metadata sent "[object Object]" as the key. Both
    // spellings now work, which is what makes the generated declaration true.
    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            await apple.keychain.set({ key: 'codemode-dts-test', value: 'object-form' });
            const viaObject = await apple.keychain.get({ key: 'codemode-dts-test' });
            const viaPositional = await apple.keychain.get('codemode-dts-test');
            await apple.keychain.delete({ key: 'codemode-dts-test' });
            return { viaObject: viaObject && viaObject.value, viaPositional: viaPositional && viaPositional.value };
            """,
            allowedCapabilities: [.keychainRead, .keychainWrite, .keychainDelete]
        )
    )

    #expect(observed.error == nil)
    let output = try #require(observed.result?.output?.objectValue)
    #expect(output.string("viaObject") == "object-form")
    #expect(output.string("viaPositional") == "object-form")
}

@Test func reservedWordHelpersRenderAsValidMemberNames() async throws {
    let (tools, sandbox) = try makeTools(hostPlatform: .iOS)
    defer { cleanup(sandbox) }

    // `apple.keychain.delete` and the `export` helpers used to render as
    // `function delete(` / `function export(` — invalid TypeScript. As object
    // type members they are legal.
    let surface = tools.typeDeclarations()
    let reserved = ["break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete",
                    "do", "else", "enum", "export", "extends", "false", "finally", "for", "function", "if",
                    "import", "in", "instanceof", "new", "null", "return", "super", "switch", "this",
                    "throw", "true", "try", "typeof", "var", "void", "while", "with"]
    for word in reserved {
        #expect(surface.contains("function \(word)(") == false, "reserved word '\(word)' declared as a function")
    }
    #expect(surface.contains("delete(args: {"))
    #expect(surface.contains("declare namespace") == false)
}

// MARK: - Declarations follow the grant

@Test func typeDeclarationsFollowTheCapabilityGrant() async throws {
    let (granted, grantedSandbox) = try makeTools(capabilityGrant: .only([.fsRead, .fsList]), hostPlatform: .iOS)
    defer { cleanup(grantedSandbox) }
    let (open, openSandbox) = try makeTools(hostPlatform: .iOS)
    defer { cleanup(openSandbox) }

    let narrow = granted.typeDeclarations()
    let full = open.typeDeclarations()

    // Only what the host grants is advertised: never a helper the model would be
    // denied, and never 21k tokens of surface when two helpers are permitted.
    #expect(narrow.contains("read(args: {"))
    #expect(narrow.contains("list(args: {"))
    #expect(narrow.contains("keychain: {") == false)
    #expect(narrow.contains("write(args: {") == false)
    #expect(narrow.contains("declare function fetch("), "the preamble is always included")
    #expect(narrow.count * 10 < full.count)
}

@Test func typeDeclarationsCanBeNarrowedToAnExplicitSubset() async throws {
    let (tools, sandbox) = try makeTools(hostPlatform: .iOS)
    defer { cleanup(sandbox) }

    let subset = tools.typeDeclarations(for: [.keychainRead])
    #expect(subset.contains("keychain: {"))
    #expect(subset.contains("get(args: {"))
    // Not `fs: {` — the always-included preamble declares the Node `fs` shim.
    #expect(subset.contains("read(args: {") == false)
}

@Test func anUnrestrictedGrantDeclaresTheWholeSurface() async throws {
    let (tools, sandbox) = try makeTools(hostPlatform: .iOS)
    defer { cleanup(sandbox) }
    let declared = tools.typeDeclarations()
    for reference in tools.capabilities() {
        let leaf = reference.jsNames.first { $0.contains(".") && !$0.hasPrefix("fs.promises.") }?
            .split(separator: ".").last.map(String.init)
        if let leaf {
            #expect(declared.contains("\(leaf)("), "missing \(reference.capability)")
        }
    }
}

// MARK: - Codable compatibility

@Test func referencesEncodedBeforeDtsExistedStillDecode() throws {
    // The shape a host cached before this branch: no `dts` key. The synthesized
    // decoder threw keyNotFound on it.
    let legacy = #"{"capability":"fs.read","capabilityKey":"fs.read","builtInCapability":"fs.read","jsNames":["apple.fs.read"],"summary":"Read a file.","tags":[],"example":"","requiredArguments":["path"],"optionalArguments":[],"argumentTypes":{"path":"string"},"argumentHints":{},"argumentConstraints":{"allowedStringValues":{}},"resultSummary":"Object."}"#
    let decoded = try JSONDecoder().decode(JavaScriptAPIReference.self, from: Data(legacy.utf8))
    #expect(decoded.capability == "fs.read")
    // Regenerated rather than left empty.
    #expect(decoded.dts.contains("read(args: {"))
    #expect(decoded.dts.contains("path: string;"))
}

@Test func referencesRoundTripThroughCodableUnchanged() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }
    let original = tools.capabilities()
    let decoded = try JSONDecoder().decode([JavaScriptAPIReference].self, from: JSONEncoder().encode(original))
    #expect(decoded == original)
}
