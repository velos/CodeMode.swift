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

    #expect(surface.contains("declare namespace apple {"))
    #expect(surface.contains("namespace fs {"))
    #expect(surface.contains("function read(args: {"))
    // The Node-compat globals live in the hand-authored preamble, because their
    // positional convention is not something the catalog can describe.
    #expect(surface.contains("declare function fetch("))
    #expect(surface.contains("type CodeModeValue ="))
    // iOS-only helpers must not be declared for a macOS host.
    #expect(surface.contains("namespace alarm {") == false)
}

@Test func iOSOnlyHelpersAppearForAniOSHost() async throws {
    let (tools, sandbox) = try makeTools(hostPlatform: .iOS)
    defer { cleanup(sandbox) }
    #expect(tools.typeDeclarations().contains("namespace alarm {"))
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
    #expect(payload.contains("function apple_fs_read(args: {"))
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

@Test func keychainHelpersAcceptTheObjectFormTheCatalogAdvertises() async throws {
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
