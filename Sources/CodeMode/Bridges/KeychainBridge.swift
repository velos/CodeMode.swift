import Foundation
import Security

public final class KeychainBridge: @unchecked Sendable {
    private let service: String

    public init(service: String = "CodeMode") {
        self.service = service
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
            throw BridgeError.nativeFailure("keychain.read failed with status \(status)")
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
                throw BridgeError.nativeFailure("keychain.write update failed with status \(updateStatus)")
            }
            return .object(["key": .string(key), "written": .bool(true)])
        }

        throw BridgeError.nativeFailure("keychain.write failed with status \(status)")
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

        throw BridgeError.nativeFailure("keychain.delete failed with status \(status)")
    }
}
