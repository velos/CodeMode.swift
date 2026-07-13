import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
import CodeModeAuthoring
import CodeModeMacros

private func codeModeTestMacros() -> [String: Macro.Type] {
    [
        "CodeMode": CodeModeMacro.self,
        "CodeModeParam": CodeModeParamMacro.self,
        "CodeModeResult": CodeModeResultMacro.self,
    ]
}

@CodeMode(path: "myapp.tasks.complete", description: "Mark a task complete.")
private struct ExampleTaskComplete: Sendable {
    struct Arguments {
        @CodeModeParam("Task identifier")
        var id: String

        @CodeModeParam("Optional completion note")
        var note: String?
    }

    @CodeModeResult("Completion payload")
    struct Result {
        var id: String
        var note: String?
        var completed: Bool
    }

    func call(arguments: Arguments) async throws -> Result {
        Result(id: arguments.id, note: arguments.note, completed: true)
    }
}

@CodeMode(path: "myapp.tasks.ping", description: "Ping the task system.")
private struct ExampleVoidTool: Sendable {
    struct Arguments {}

    func call(arguments: Arguments) throws {}
}

private struct FailingTaskTool: CodeModeProvider {
    var codeModePath: String { "myapp.tasks.fail" }

    func codeModeRegistrations() -> [CodeModeRegistration] {
        [
            CodeModeRegistration(
                capabilityKey: "myapp.tasks.fail",
                jsPath: "myapp.tasks.fail",
                title: "fail",
                summary: "Fail with custom invalid arguments.",
                example: "await myapp.tasks.fail({})"
            ) { _, _ in
                throw CodeModeFunctionError.invalidArguments("Custom invalid argument")
            },
        ]
    }
}

@Test func codeModeMacroToolRegistersDocsAndExecutes() async throws {
    let provider = ExampleTaskComplete()
    #expect(provider.codeModePath == "myapp.tasks.complete")

    let registrations = provider.codeModeRegistrations()
    let registration = try #require(registrations.first)
    #expect(registration.capabilityKey == "myapp.tasks.complete")
    #expect(registration.jsPath == "myapp.tasks.complete")
    #expect(registration.title == "complete")
    #expect(registration.summary == "Mark a task complete.")
    #expect(registration.tags == ["myapp.tasks"])
    #expect(registration.requiredArguments == ["id"])
    #expect(registration.optionalArguments == ["note"])
    #expect(registration.argumentTypes["id"] == .string)
    #expect(registration.argumentTypes["note"] == .string)
    #expect(registration.argumentHints["id"] == "Task identifier")
    #expect(registration.argumentHints["note"] == "Optional completion note")
    #expect(registration.resultSummary == "Completion payload")

    let tools = CodeModeAgentTools(config: CodeModeConfiguration(codeModeProviders: [provider]))
    let search = try await tools.searchJavaScriptAPI(
        JavaScriptAPISearchRequest(
            code: """
            async () => {
                const ref = api.byJSName["myapp.tasks.complete"];
                return {
                    capabilityKey: ref.capabilityKey,
                    summary: ref.summary,
                    requiredArguments: ref.requiredArguments,
                    optionalArguments: ref.optionalArguments,
                    argumentHints: ref.argumentHints,
                    resultSummary: ref.resultSummary
                };
            }
            """
        )
    )
    let reference = try #require(search.result?.objectValue)
    #expect(reference.string("capabilityKey") == "myapp.tasks.complete")
    #expect(reference.string("summary") == "Mark a task complete.")
    #expect(reference.array("requiredArguments") == [.string("id")])
    #expect(reference.array("optionalArguments") == [.string("note")])
    #expect(reference.object("argumentHints")?.string("id") == "Task identifier")
    #expect(reference.string("resultSummary") == "Completion payload")

    let call = try await tools.executeJavaScript(
        JavaScriptExecutionRequest(
            code: #"return await myapp.tasks.complete({ id: "task-123", note: "Done in app" });"#,
            allowedCapabilities: [],
            allowedCapabilityKeys: ["myapp.tasks.complete"]
        )
    )
    let observed = await observe(call)
    let output = try #require(observed.result?.output?.objectValue)
    #expect(output.string("id") == "task-123")
    #expect(output.string("note") == "Done in app")
    #expect(output.bool("completed") == true)
}

@Test func codeModeMacroToolSupportsVoidResult() async throws {
    let tools = CodeModeAgentTools(config: CodeModeConfiguration(codeModeProviders: [ExampleVoidTool()]))
    let call = try await tools.executeJavaScript(
        JavaScriptExecutionRequest(
            code: "return await myapp.tasks.ping({});",
            allowedCapabilities: [],
            allowedCapabilityKeys: ["myapp.tasks.ping"]
        )
    )
    let observed = await observe(call)
    #expect(observed.result?.output == .null)
}

@Test func codeModeMacroToolRequiresAllowedCapabilityKey() async throws {
    let tools = CodeModeAgentTools(config: CodeModeConfiguration(codeModeProviders: [ExampleTaskComplete()]))

    let deniedCall = try await tools.executeJavaScript(
        JavaScriptExecutionRequest(
            code: #"return await myapp.tasks.complete({ id: "task-123" });"#,
            allowedCapabilities: []
        )
    )
    let denied = await observe(deniedCall)
    let deniedError = try #require(denied.error)
    #expect(deniedError.code == "CAPABILITY_DENIED")
    #expect(deniedError.capabilityKey == "myapp.tasks.complete")
}

@Test func customProviderFunctionErrorsRemainStructured() async throws {
    let tools = CodeModeAgentTools(config: CodeModeConfiguration(codeModeProviders: [FailingTaskTool()]))
    let call = try await tools.executeJavaScript(
        JavaScriptExecutionRequest(
            code: "return await myapp.tasks.fail({});",
            allowedCapabilities: [],
            allowedCapabilityKeys: ["myapp.tasks.fail"]
        )
    )
    let observed = await observe(call)
    let error = try #require(observed.error)
    #expect(error.code == "INVALID_ARGUMENTS")
    #expect(error.message == "Custom invalid argument")
    #expect(error.capabilityKey == "myapp.tasks.fail")
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

@Test func codeModeMacroExpansionGeneratesToolProviderConformance() {
    assertMacroExpansion(
        """
        @CodeMode(path: "macro.api.greet", description: "Greet a person.")
        struct Demo: Sendable {
            struct Arguments {
                @CodeModeParam("Person name")
                var name: String

                @CodeModeParam("Whether to add emphasis")
                var excited: Bool?
            }

            @CodeModeResult("Greeting payload")
            struct Result {
                var greeting: String
                var excited: Bool?
            }

            func call(arguments: Arguments) async throws -> Result {
                Result(greeting: "Hello", excited: arguments.excited)
            }
        }
        """,
        expandedSource:
        """
        struct Demo: Sendable {
            struct Arguments {
                var name: String
                var excited: Bool?
            }
            struct Result {
                var greeting: String
                var excited: Bool?
            }

            func call(arguments: Arguments) async throws -> Result {
                Result(greeting: "Hello", excited: arguments.excited)
            }
        }

        extension Demo: CodeModeProvider {
            var codeModePath: String {
                "macro.api.greet"
            }

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
                        argumentHints: ["name": "Person name", "excited": "Whether to add emphasis"],
                        resultSummary: "Greeting payload",
                        handler: { arguments, _ in
                            try CodeModeAsyncBridge.run {
                                let decodedArguments = Arguments(
                                    name: try CodeModeArgumentDecoder.require("name", as: String.self, in: arguments),
                                    excited: try CodeModeArgumentDecoder.optional("excited", as: Bool.self, in: arguments)
                                )
                                let result = try await self.call(arguments: decodedArguments)
                                return .object([
                                    "greeting": CodeModeValueEncoder.encode(result.greeting),
                                    "excited": CodeModeValueEncoder.encode(result.excited)
                                ])
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

@Test func codeModeMacroExpansionSupportsEmptyArgumentsAndVoid() {
    assertMacroExpansion(
        """
        @CodeMode(path: "macro.api.ping", description: "Ping.")
        struct Ping: Sendable {
            struct Arguments {}

            func call(arguments: Arguments) throws {}
        }
        """,
        expandedSource:
        """
        struct Ping: Sendable {
            struct Arguments {}

            func call(arguments: Arguments) throws {}
        }

        extension Ping: CodeModeProvider {
            var codeModePath: String {
                "macro.api.ping"
            }

            func codeModeRegistrations() -> [CodeModeRegistration] {
                [
                    CodeModeRegistration(
                        capabilityKey: CodeModeCapabilityKey(rawValue: "macro.api.ping"),
                        jsPath: "macro.api.ping",
                        title: "ping",
                        summary: "Ping.",
                        tags: ["macro.api"],
                        example: "await macro.api.ping({})",
                        requiredArguments: [],
                        optionalArguments: [],
                        argumentTypes: [:],
                        argumentHints: [:],
                        resultSummary: "null",
                        handler: { arguments, _ in
                            try CodeModeAsyncBridge.run {
                                let decodedArguments = Arguments()
                                try self.call(arguments: decodedArguments)
                                return .null
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
        @CodeMode(path: "bad-path", description: "Bad.")
        struct Demo: Sendable {
            struct Arguments {}
            func call(arguments: Arguments) throws {}
        }
        """,
        expandedSource:
        """
        struct Demo: Sendable {
            struct Arguments {}
            func call(arguments: Arguments) throws {}
        }
        """,
        diagnostics: [
            DiagnosticSpec(message: "@CodeMode requires a valid dotted JavaScript path", line: 1, column: 1),
        ],
        macros: codeModeTestMacros()
    )
}

@Test func codeModeMacroExpansionDiagnosesMissingArguments() {
    assertMacroExpansion(
        """
        @CodeMode(path: "macro.api.bad", description: "Bad.")
        struct Demo: Sendable {
            func call(arguments: Arguments) throws {}
        }
        """,
        expandedSource:
        """
        struct Demo: Sendable {
            func call(arguments: Arguments) throws {}
        }
        """,
        diagnostics: [
            DiagnosticSpec(message: "@CodeMode requires a nested Arguments struct", line: 1, column: 1),
        ],
        macros: codeModeTestMacros()
    )
}

@Test func codeModeMacroExpansionDiagnosesUnsupportedPropertyType() {
    assertMacroExpansion(
        """
        @CodeMode(path: "macro.api.bad", description: "Bad.")
        struct Demo: Sendable {
            struct Arguments {
                @CodeModeParam("Bad")
                var date: Date
            }

            func call(arguments: Arguments) throws {}
        }
        """,
        expandedSource:
        """
        struct Demo: Sendable {
            struct Arguments {
                var date: Date
            }

            func call(arguments: Arguments) throws {}
        }
        """,
        diagnostics: [
            DiagnosticSpec(message: "@CodeMode does not support property type 'Date'", line: 5, column: 13),
        ],
        macros: codeModeTestMacros()
    )
}

@Test func codeModeMacroExpansionDiagnosesComputedProperty() {
    assertMacroExpansion(
        """
        @CodeMode(path: "macro.api.bad", description: "Bad.")
        struct Demo: Sendable {
            struct Arguments {
                var id: String { "x" }
            }

            func call(arguments: Arguments) throws {}
        }
        """,
        expandedSource:
        """
        struct Demo: Sendable {
            struct Arguments {
                var id: String { "x" }
            }

            func call(arguments: Arguments) throws {}
        }
        """,
        diagnostics: [
            DiagnosticSpec(message: "@CodeMode does not support computed properties", line: 4, column: 13),
        ],
        macros: codeModeTestMacros()
    )
}

@Test func codeModeMacroExpansionDiagnosesNonThrowingCall() {
    assertMacroExpansion(
        """
        @CodeMode(path: "macro.api.bad", description: "Bad.")
        struct Demo: Sendable {
            struct Arguments {}
            func call(arguments: Arguments) {}
        }
        """,
        expandedSource:
        """
        struct Demo: Sendable {
            struct Arguments {}
            func call(arguments: Arguments) {}
        }
        """,
        diagnostics: [
            DiagnosticSpec(message: "@CodeMode call(arguments:) must be throws or async throws", line: 4, column: 10),
        ],
        macros: codeModeTestMacros()
    )
}

@Test func codeModeMacroExpansionDiagnosesGenericType() {
    assertMacroExpansion(
        """
        @CodeMode(path: "macro.api.bad", description: "Bad.")
        struct Demo<T>: Sendable {
            struct Arguments {}
            func call(arguments: Arguments) throws {}
        }
        """,
        expandedSource:
        """
        struct Demo<T>: Sendable {
            struct Arguments {}
            func call(arguments: Arguments) throws {}
        }
        """,
        diagnostics: [
            DiagnosticSpec(message: "@CodeMode does not support generic types", line: 1, column: 1),
        ],
        macros: codeModeTestMacros()
    )
}

@Test func codeModeMacroExpansionDiagnosesOverloadedCall() {
    assertMacroExpansion(
        """
        @CodeMode(path: "macro.api.bad", description: "Bad.")
        struct Demo: Sendable {
            struct Arguments {}
            func call(arguments: Arguments) throws {}
            func call(arguments: Arguments, extra: String) throws {}
        }
        """,
        expandedSource:
        """
        struct Demo: Sendable {
            struct Arguments {}
            func call(arguments: Arguments) throws {}
            func call(arguments: Arguments, extra: String) throws {}
        }
        """,
        diagnostics: [
            DiagnosticSpec(message: "@CodeMode requires exactly one call(arguments:) method", line: 1, column: 1),
        ],
        macros: codeModeTestMacros()
    )
}

@Test func codeModeMacroExpansionDiagnosesDefaultCallArgument() {
    assertMacroExpansion(
        """
        @CodeMode(path: "macro.api.bad", description: "Bad.")
        struct Demo: Sendable {
            struct Arguments {}
            func call(arguments: Arguments = Arguments()) throws {}
        }
        """,
        expandedSource:
        """
        struct Demo: Sendable {
            struct Arguments {}
            func call(arguments: Arguments = Arguments()) throws {}
        }
        """,
        diagnostics: [
            DiagnosticSpec(message: "@CodeMode call(arguments:) does not support default or variadic parameters", line: 4, column: 15),
        ],
        macros: codeModeTestMacros()
    )
}
