import Foundation

#if canImport(HomeKit)
import HomeKit
#endif

public final class HomeBridge: @unchecked Sendable {
    public init() {}

    public func read(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let status = resolvePermission(context: context)
        guard status == .granted else {
            throw BridgeError.permissionDenied(.homeKit)
        }

        #if canImport(HomeKit)
        let includeCharacteristics = arguments.bool("includeCharacteristics") ?? false
        let homeLimit = max(1, arguments.int("limit") ?? 10)
        let manager = try waitForHomeManager()

        let homes = manager.homes.prefix(homeLimit).map { home in
            JSONValue.object([
                "identifier": .string(home.uniqueIdentifier.uuidString),
                "name": .string(home.name),
                "rooms": .array(home.rooms.map { .string($0.name) }),
                "accessories": .array(home.accessories.map { accessory in
                    .object([
                        "identifier": .string(accessory.uniqueIdentifier.uuidString),
                        "name": .string(accessory.name),
                        "isReachable": .bool(accessory.isReachable),
                        "category": .string(accessory.category.categoryType),
                        "room": .string(accessory.room?.name ?? ""),
                        "services": .array(accessory.services.map { service in
                            var servicePayload: [String: JSONValue] = [
                                "serviceType": .string(service.serviceType),
                                "name": .string(service.name),
                            ]

                            if includeCharacteristics {
                                servicePayload["characteristics"] = .array(service.characteristics.map { characteristic in
                                    .object([
                                        "characteristicType": .string(characteristic.characteristicType),
                                        "isReadable": .bool(characteristic.properties.contains(HMCharacteristicPropertyReadable)),
                                        "isWritable": .bool(characteristic.properties.contains(HMCharacteristicPropertyWritable)),
                                        "value": JSONValue(any: characteristic.value),
                                    ])
                                })
                            }

                            return .object(servicePayload)
                        }),
                    ])
                }),
            ])
        }

        return .array(Array(homes))
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("HomeKit")
        #endif
    }

    public func write(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard let accessoryIdentifier = arguments.string("accessoryIdentifier"), accessoryIdentifier.isEmpty == false else {
            throw BridgeError.invalidArguments("home.write requires accessoryIdentifier")
        }
        guard let characteristicType = arguments.string("characteristicType"), characteristicType.isEmpty == false else {
            throw BridgeError.invalidArguments("home.write requires characteristicType")
        }
        guard let value = arguments["value"] else {
            throw BridgeError.invalidArguments("home.write requires value")
        }

        let status = resolvePermission(context: context)
        guard status == .granted else {
            throw BridgeError.permissionDenied(.homeKit)
        }

        #if canImport(HomeKit)
        let manager = try waitForHomeManager()
        let serviceTypeFilter = arguments.string("serviceType")

        guard let accessory = manager.homes
            .flatMap(\.accessories)
            .first(where: { $0.uniqueIdentifier.uuidString == accessoryIdentifier })
        else {
            throw BridgeError.invalidArguments("home.write could not find accessory \(accessoryIdentifier)")
        }

        let services = accessory.services.filter { service in
            guard let serviceTypeFilter else { return true }
            return service.serviceType == serviceTypeFilter
        }

        guard let characteristic = services
            .flatMap(\.characteristics)
            .first(where: { $0.characteristicType == characteristicType })
        else {
            throw BridgeError.invalidArguments("home.write could not find characteristic \(characteristicType)")
        }

        let objcValue = try toHomeKitValue(value, characteristicType: characteristicType)
        let semaphore = DispatchSemaphore(value: 0)
        let writeError = LockedBox<Error?>(nil)

        characteristic.writeValue(objcValue) { error in
            writeError.set(error)
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 10) == .timedOut {
            throw BridgeError.timeout(milliseconds: 10_000)
        }

        if let writeError = writeError.get() {
            throw BridgeError.nativeFailure("home.write failed: \(writeError.localizedDescription)")
        }

        return .object([
            "accessoryIdentifier": .string(accessoryIdentifier),
            "characteristicType": .string(characteristicType),
            "written": .bool(true),
        ])
        #else
        _ = arguments
        _ = value
        throw BridgeError.unsupportedPlatform("HomeKit")
        #endif
    }

    private func resolvePermission(context: BridgeInvocationContext) -> PermissionStatus {
        let status = context.permissionBroker.status(for: .homeKit)
        context.recordPermission(.homeKit, status: status)
        if status == .notDetermined {
            let requested = context.permissionBroker.request(for: .homeKit)
            context.recordPermission(.homeKit, status: requested)
            return requested
        }

        return status
    }

    #if canImport(HomeKit)
    private func toHomeKitValue(_ value: JSONValue, characteristicType: String) throws -> Any {
        switch value {
        case let .bool(value):
            return NSNumber(value: value)
        case let .number(value):
            return NSNumber(value: value)
        case let .string(value):
            return value
        case .null:
            return NSNull()
        case .object, .array:
            throw BridgeError.invalidArguments("home.write value for \(characteristicType) must be string/number/bool/null")
        }
    }

    private func waitForHomeManager(timeout: TimeInterval = 10) throws -> HMHomeManager {
        let delegate = HomeManagerLoadDelegate()
        let manager = HMHomeManager()
        manager.delegate = delegate

        if delegate.wait(timeout: timeout) == .timedOut {
            throw BridgeError.timeout(milliseconds: Int(timeout * 1_000))
        }

        return manager
    }
    #endif
}

#if canImport(HomeKit)
private final class HomeManagerLoadDelegate: NSObject, HMHomeManagerDelegate {
    private let semaphore = DispatchSemaphore(value: 0)
    private var hasSignaled = false
    private let lock = NSLock()

    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        _ = manager
        signalIfNeeded()
    }

    func wait(timeout: TimeInterval) -> DispatchTimeoutResult {
        semaphore.wait(timeout: .now() + timeout)
    }

    private func signalIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard hasSignaled == false else { return }
        hasSignaled = true
        semaphore.signal()
    }
}
#endif
