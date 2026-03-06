import Foundation
import Testing
@testable import CodeMode

@Test func mediaMetadataValidatesRequiredPath() throws {
    let bridge = MediaBridge()
    let (context, sandbox) = try makeInvocationContext()
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.metadata(arguments: [:], context: context)
        Issue.record("Expected metadata to require path")
    } catch {
        #if canImport(AVFoundation)
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
        #else
        #expect(requireBridgeErrorCode(error) == "UNSUPPORTED_PLATFORM")
        #endif
    }
}

@Test func mediaExtractFrameValidatesRequiredPath() throws {
    let bridge = MediaBridge()
    let (context, sandbox) = try makeInvocationContext()
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.extractFrame(arguments: [:], context: context)
        Issue.record("Expected extractFrame to require path")
    } catch {
        #if canImport(AVFoundation) && canImport(ImageIO) && canImport(CoreGraphics)
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
        #else
        #expect(requireBridgeErrorCode(error) == "UNSUPPORTED_PLATFORM")
        #endif
    }
}

@Test func mediaTranscodeValidatesRequiredPath() throws {
    let bridge = MediaBridge()
    let (context, sandbox) = try makeInvocationContext()
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.transcode(arguments: [:], context: context)
        Issue.record("Expected transcode to require path")
    } catch {
        #if canImport(AVFoundation)
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
        #else
        #expect(requireBridgeErrorCode(error) == "UNSUPPORTED_PLATFORM")
        #endif
    }
}

@Test func executeUsesMediaBridgeValidation() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            await ios.media.metadata({});
            return { ok: true };
            """,
            allowedCapabilities: [.mediaMetadataRead]
        )
    )

    #if canImport(AVFoundation)
    #expect(observed.error?.code == "INVALID_ARGUMENTS")
    #else
    #expect(observed.error?.code == "UNSUPPORTED_PLATFORM")
    #endif
}
