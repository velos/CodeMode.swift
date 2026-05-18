import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
import CodeModeAuthoring
import CodeModeMacros

private func codeModeTestMacros() -> [String: Macro.Type] {
    [
        "CodeMode": CodeModeMacro.self,
        "CodeModeDescription": CodeModeDescriptionMacro.self,
        "CodeModeName": CodeModeNameMacro.self,
        "CodeModeParam": CodeModeParamMacro.self,
        "CodeModeResult": CodeModeResultMacro.self,
    ]
}

@CodeMode(path: "macro.api")
private struct RuntimeMacroProvider: Sendable {
    @CodeModeDescription("Greet a person.")
    @CodeModeParam("name", "Person name")
    @CodeModeResult("Greeting")
    func greet(name: String, excited: Bool?) async throws -> String {
        "Hello, \(name)\(excited == true ? "!" : ".")"
    }
}

@Test func codeModeMacroProviderRegistersAndExecutes() async throws {
    let provider = RuntimeMacroProvider()
    #expect(provider.codeModePath == "macro.api")

    let registrations = provider.codeModeRegistrations()
    let registration = try #require(registrations.first)
    #expect(registration.capabilityKey == "macro.api.greet")
    #expect(registration.jsPath == "macro.api.greet")
    #expect(registration.requiredArguments == ["name"])
    #expect(registration.optionalArguments == ["excited"])
    #expect(registration.argumentTypes["name"] == .string)
    #expect(registration.argumentTypes["excited"] == .bool)
    #expect(registration.argumentHints["name"] == "Person name")

    let tools = CodeModeAgentTools(config: CodeModeConfiguration(codeModeProviders: [provider]))
    let call = try await tools.executeJavaScript(
        JavaScriptExecutionRequest(
            code: #"return await macro.api.greet({ name: "Ada", excited: true });"#,
            allowedCapabilities: [],
            allowedCapabilityKeys: ["macro.api.greet"]
        )
    )
    let observed = await observe(call)
    #expect(observed.result?.output == .string("Hello, Ada!"))
}

private struct ObservedExecution {
    let result: JavaScriptExecutionResult?
    let error: CodeModeToolError?
}

private func observe(_ call: JavaScriptExecutionCall) async -> ObservedExecution {
    do {
        return ObservedExecution(result: try await call.result, error: nil)
    } catch let error as CodeModeToolError {
        return ObservedExecution(result: nil, error: error)
    } catch {
        return ObservedExecution(
            result: nil,
            error: CodeModeToolError(code: "UNEXPECTED", message: error.localizedDescription)
        )
    }
}

@Test func codeModeMacroExpansionGeneratesProviderConformance() {
    assertMacroExpansion(
        """
        @CodeMode(path: "macro.api")
        struct Demo: Sendable {
            @CodeModeDescription("Greet a person.")
            @CodeModeParam("name", "Person name")
            @CodeModeResult("Greeting")
            func greet(name: String, excited: Bool?) async throws -> String {
                "Hello"
            }
        }
        """,
        expandedSource:
        """
        struct Demo: Sendable {
            func greet(name: String, excited: Bool?) async throws -> String {
                "Hello"
            }
        }

        extension Demo: CodeModeProvider {
            var codeModePath: String { "macro.api" }

            func codeModeRegistrations() -> [CodeModeRegistration] {
                [
                    CodeModeRegistration(
                        capabilityKey: CodeModeCapabilityKey(rawValue: "macro.api.greet"),
                        jsPath: "macro.api.greet",
                        title: "greet",
                        summary: "Greet a person.",
                        tags: ["macro.api"],
                        example: "await macro.api.greet({})",
                        requiredArguments: ["name"],
                        optionalArguments: ["excited"],
                        argumentTypes: ["name": CapabilityArgumentType.string, "excited": CapabilityArgumentType.bool],
                        argumentHints: ["name": "Person name"],
                        resultSummary: "Greeting",
                        handler: { arguments, _ in
                            try CodeModeAsyncBridge.run {
                                let name = try CodeModeArgumentDecoder.require("name", as: String.self, in: arguments)
                                let excited = try CodeModeArgumentDecoder.optional("excited", as: Bool.self, in: arguments)
                                let result = try await self.greet(name: name, excited: excited)
                                return CodeModeValueEncoder.encode(result)
                            }
                        }
                    )
                ]
            }
        }
        """,
        macros: codeModeTestMacros()
    )
}

@Test func codeModeMacroExpansionDiagnosesInvalidPath() {
    assertMacroExpansion(
        """
        @CodeMode(path: "bad-path")
        struct Demo: Sendable {
        }
        """,
        expandedSource:
        """
        struct Demo: Sendable {
        }
        """,
        diagnostics: [
            DiagnosticSpec(message: "@CodeMode requires a valid dotted JavaScript path", line: 1, column: 1),
        ],
        macros: codeModeTestMacros()
    )
}
