import Foundation
import Testing
@testable import CodeMode
import Security

@Test(.enabled(if: keychainIsAvailable, "no keychain entitlement in this test host (errSecMissingEntitlement)")) func keychainRoundTripWriteReadDelete() throws {
    let bridge = KeychainBridge(service: "CodeModeTests.\(UUID().uuidString)")
    let key = "token"

    _ = try bridge.write(arguments: [
        "key": .string(key),
        "value": .string("abc123"),
    ])

    let readValue = try bridge.read(arguments: ["key": .string(key)])
    let readObject = try requireObject(readValue)
    #expect(readObject.string("value") == "abc123")

    _ = try bridge.delete(arguments: ["key": .string(key)])
    let postDelete = try bridge.read(arguments: ["key": .string(key)])
    #expect(postDelete == .null)
}

@Test(.enabled(if: keychainIsAvailable, "no keychain entitlement in this test host (errSecMissingEntitlement)")) func keychainReadMissingValueReturnsNull() throws {
    let bridge = KeychainBridge(service: "CodeModeTests.\(UUID().uuidString)")
    let readValue = try bridge.read(arguments: ["key": .string("missing")])
    #expect(readValue == .null)
}

@Test func keychainValidatesRequiredKey() {
    let bridge = KeychainBridge(service: "CodeModeTests.\(UUID().uuidString)")

    do {
        _ = try bridge.write(arguments: ["value": .string("abc")])
        Issue.record("Expected keychain.write to fail without key")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }
}

@Test(.enabled(if: keychainIsAvailable, "no keychain entitlement in this test host (errSecMissingEntitlement)")) func executeUsesKeychainBridge() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            const key = 'execute-keychain-' + String(Date.now());
            await apple.keychain.set(key, 'value-from-execute');
            const read = await apple.keychain.get(key);
            await apple.keychain.delete(key);
            return { value: read ? read.value : null };
            """,
            allowedCapabilities: [.keychainWrite, .keychainRead, .keychainDelete]
        )
    )

    let payload = try requireJSONObject(from: try #require(observed.result))
    #expect(payload["value"] as? String == "value-from-execute")
}

@Test func keychainFailuresDescribeTheStatusInsteadOfPrintingIt() {
    // -34018 is the one host developers hit in their own unsigned test targets,
    // and the model must learn it is not retryable.
    let missing = KeychainBridge.failure("keychain.write", status: errSecMissingEntitlement)
    #expect(missing.localizedDescription.contains("no keychain entitlement"))
    #expect(missing.localizedDescription.contains("retrying will not help"))

    let other = KeychainBridge.failure("keychain.read", status: errSecDuplicateItem)
    #expect(other.localizedDescription.contains("keychain.read failed:"))
    #expect(other.localizedDescription.contains("(\(errSecDuplicateItem))"))
}
