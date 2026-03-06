import Foundation
import Testing
@testable import CodeMode

@Test func visionAnalyzeValidatesRequiredPath() throws {
    let bridge = VisionBridge()
    let (context, sandbox) = try makeInvocationContext()
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.analyzeImage(arguments: [:], context: context)
        Issue.record("Expected vision.image.analyze to require path")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }
}

@Test func executeUsesVisionBridgeValidation() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            await ios.vision.analyzeImage({ features: ['text'] });
            return { ok: true };
            """,
            allowedCapabilities: [.visionImageAnalyze]
        )
    )

    #expect(observed.error?.code == "INVALID_ARGUMENTS")
}
