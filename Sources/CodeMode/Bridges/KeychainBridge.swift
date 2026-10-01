import Foundation
import Security

public final class KeychainBridge: @unchecked Sendable {
    private let service: String

    public init(service: String = "CodeMode") {
        self.service = service
    }

    /// A failure that says what went wrong, not just which OSStatus it was.
    ///
    /// "failed with status -34018" told neither the model nor the host
    /// developer anything. -34018 in particular — `errSecMissingEntitlement` —
    /// is a host configuration problem (no keychain access group; routine in an
    /// unsigned test bundle), and the model should know a retry cannot fix it.
    static func failure(_ operation: String, status: OSStatus) -> BridgeError {
        let description = (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
        if status == errSecMissingEntitlement {
            return .nativeFailure(
                "\(operation) failed: the host app has no keychain entitlement (\(status)). This is a host configuration issue — the app needs a keychain access group — and retrying will not help."
            )
        }
        return .nativeFailure("\(operation) failed: \(description) (\(status))")
    }

    public func read(arguments: [String: JSONValue]) throws -> JSONValue {
        guard let key = arguments.string("key"), key.isEmpty == false else {
            throw BridgeError.invalidArguments("keychain.read requires 'key'")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                throw BridgeError.nativeFailure("Unable to decode keychain value")
            }
            return .object(["key": .string(key), "value": .string(value)])
        case errSecItemNotFound:
            return .null
        default:
            throw Self.failure("keychain.read", status: status)
        }
    }

    public func write(arguments: [String: JSONValue]) throws -> JSONValue {
        guard let key = arguments.string("key"), key.isEmpty == false else {
            throw BridgeError.invalidArguments("keychain.write requires 'key'")
        }

        let value = arguments.string("value") ?? ""
        let valueData = Data(value.utf8)

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let attrs: [String: Any] = [
            kSecValueData as String: valueData,
        ]

        let status = SecItemAdd(baseQuery.merging(attrs) { _, new in new } as CFDictionary, nil)
        if status == errSecSuccess {
            return .object(["key": .string(key), "written": .bool(true)])
        }

        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw Self.failure("keychain.write", status: updateStatus)
            }
            return .object(["key": .string(key), "written": .bool(true)])
        }

        throw Self.failure("keychain.write", status: status)
    }

    public func delete(arguments: [String: JSONValue]) throws -> JSONValue {
        guard let key = arguments.string("key"), key.isEmpty == false else {
            throw BridgeError.invalidArguments("keychain.delete requires 'key'")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return .object(["key": .string(key), "deleted": .bool(true)])
        }

        throw Self.failure("keychain.delete", status: status)
    }
}
