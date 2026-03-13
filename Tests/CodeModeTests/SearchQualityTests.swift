import Foundation
import Testing
@testable import CodeMode

@Test func searchCanRunAgentStyleCatalogQueries() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let response = try await tools.searchJavaScriptAPI(
        JavaScriptAPISearchRequest(
            code: """
            async () => {
                const wanted = ["reminders", "create"];
                return api.references
                    .filter(ref => {
                        const haystack = [
                            ref.capability,
                            ...ref.jsNames,
                            ref.summary,
                            ref.example,
                            ...ref.tags
                        ].join(" ").toLowerCase();
                        return wanted.every(term => haystack.includes(term));
                    })
                    .map(ref => ({
                        capability: ref.capability,
                        jsName: ref.jsNames[0],
                        requiredArguments: ref.requiredArguments
                    }));
            }
            """
        )
    )

    let results = try #require(response.result?.arrayValue)
    #expect(results.contains(where: { $0.objectValue?.string("capability") == CapabilityID.remindersWrite.rawValue }))
}

@Test func searchThrowsSyntaxErrorsForInvalidJavaScript() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    do {
        _ = try await tools.searchJavaScriptAPI(
            JavaScriptAPISearchRequest(
                code: """
                async () => {
                    const value = ;
                    return value;
                }
                """
            )
        )
        Issue.record("Expected JS_SYNTAX_ERROR")
    } catch let error as CodeModeToolError {
        #expect(error.code == "JS_SYNTAX_ERROR")
    }
}

@Test func searchRejectsNonFunctionPrograms() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    do {
        _ = try await tools.searchJavaScriptAPI(
            JavaScriptAPISearchRequest(
                code: """
                ({ not: "a function" })
                """
            )
        )
        Issue.record("Expected INVALID_REQUEST")
    } catch let error as CodeModeToolError {
        #expect(error.code == "INVALID_REQUEST")
    }
}

@Test func canonicalToolDescriptionsExposeRecommendedNames() {
    #expect(CodeModeAgentToolDescriptions.all.map(\.name) == [
        "searchJavaScriptAPI",
        "executeJavaScript",
    ])
    #expect(CodeModeAgentToolDescriptions.searchJavaScriptAPI.description.contains("api.references"))
    #expect(CodeModeAgentToolDescriptions.searchJavaScriptAPI.description.contains("byJSName"))
    #expect(CodeModeAgentToolDescriptions.searchJavaScriptAPI.description.contains("current host platform"))
    #expect(CodeModeAgentToolDescriptions.searchJavaScriptAPI.description.contains("apple.fs.read"))
    #expect(CodeModeAgentToolDescriptions.executeJavaScript.description.contains("allowedCapabilities"))
    #expect(CodeModeAgentToolDescriptions.executeJavaScript.description.contains("apple.*"))
    #expect(CodeModeAgentToolDescriptions.executeJavaScript.description.contains("ios.alarm.*"))
}
