import Foundation

#if canImport(HealthKit)
import HealthKit
#endif

public final class HealthBridge: @unchecked Sendable {
    #if canImport(HealthKit)
    private let healthStore = HKHealthStore()
    #endif

    public init() {}

    public func requestPermission(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try preflightPermission(context: context)

        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            throw BridgeError.unsupportedPlatform("HealthKit")
        }

        let readNames = arguments.array("readTypes")?.compactMap(\.stringValue) ?? []
        let writeNames = arguments.array("writeTypes")?.compactMap(\.stringValue) ?? []

        let readTypes = try requestedReadTypes(from: readNames.isEmpty ? ["stepCount"] : readNames)
        let writeTypes = try requestedWriteTypes(from: writeNames)
        try ensureAuthorization(toShare: writeTypes, read: readTypes, context: context, forceRequest: true)

        // `requestAuthorization`'s `success` means the sheet flow completed, not
        // that anything was granted — HealthKit deliberately refuses to disclose
        // read authorization so an app cannot infer a health condition from a
        // denial. Reporting `granted: true` here was a fabrication that left the
        // transcript claiming access while reads returned []. Share types are the
        // only ones with an answerable status, so those are the only ones
        // reported.
        return .object([
            "status": .string("completed"),
            "authorizationFlowCompleted": .bool(true),
            "readTypes": .array(readNames.map(JSONValue.string)),
            "writeTypes": .array(writeNames.map(JSONValue.string)),
            "writeAuthorization": .object(writeAuthorizationStatuses(for: writeNames)),
            "readAuthorizationDisclosed": .bool(false),
            "note": .string("HealthKit does not disclose read authorization. An empty health.read result may mean the user denied that type rather than that no samples exist."),
        ])
        #else
        _ = arguments
        _ = context
        throw BridgeError.unsupportedPlatform("HealthKit")
        #endif
    }

    public func read(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try preflightPermission(context: context)

        guard let type = arguments.string("type"), type.isEmpty == false else {
            throw BridgeError.invalidArguments("health.read requires type")
        }

        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            throw BridgeError.unsupportedPlatform("HealthKit")
        }

        let spec = try readSpec(for: type)
        let startDate = parseISODate(arguments.string("start")) ?? Date().addingTimeInterval(-86_400)
        let endDate = parseISODate(arguments.string("end")) ?? Date()
        let limit = max(1, arguments.int("limit") ?? 50)
        let unitOverride = arguments.string("unit")

        try ensureAuthorization(toShare: [], read: [spec.objectType], context: context)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let sortDescriptors = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        let samples = try querySamples(
            sampleType: spec.sampleType,
            predicate: predicate,
            limit: limit,
            sortDescriptors: sortDescriptors
        )

        let payload = samples.map { sample in
            serializeReadSample(sample: sample, spec: spec, unitOverride: unitOverride)
        }
        return .array(payload)
        #else
        _ = arguments
        _ = context
        _ = type
        throw BridgeError.unsupportedPlatform("HealthKit")
        #endif
    }

    public func write(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try preflightPermission(context: context)

        guard let type = arguments.string("type"), type.isEmpty == false else {
            throw BridgeError.invalidArguments("health.write requires type")
        }
        guard let value = arguments.double("value") else {
            throw BridgeError.invalidArguments("health.write requires numeric value")
        }

        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            throw BridgeError.unsupportedPlatform("HealthKit")
        }

        let spec = try writeSpec(for: type)
        let startDate = parseISODate(arguments.string("start")) ?? Date()
        let endDate = parseISODate(arguments.string("end")) ?? startDate

        guard endDate >= startDate else {
            throw BridgeError.invalidArguments("health.write requires end >= start")
        }

        let unit = try resolveUnit(
            override: arguments.string("unit"),
            fallback: spec.defaultUnit
        )
        let quantityType = HKObjectType.quantityType(forIdentifier: spec.identifier)
        guard let quantityType else {
            throw BridgeError.invalidArguments("health.write type \(type) is not available on this platform")
        }

        try ensureAuthorization(toShare: [quantityType], read: [], context: context)

        let quantity = HKQuantity(unit: unit, doubleValue: value)
        let sample = HKQuantitySample(type: quantityType, quantity: quantity, start: startDate, end: endDate)
        try save(sample: sample)

        return .object([
            "identifier": .string(sample.uuid.uuidString),
            "type": .string(spec.name),
            "value": .number(value),
            "unit": .string(unit.unitString),
            "startDate": .string(startDate.ISO8601Format()),
            "endDate": .string(endDate.ISO8601Format()),
            "written": .bool(true),
        ])
        #else
        _ = arguments
        _ = context
        _ = type
        _ = value
        throw BridgeError.unsupportedPlatform("HealthKit")
        #endif
    }

    private func preflightPermission(context: BridgeInvocationContext) throws {
        let status = context.permissionBroker.status(for: .healthKit)
        context.recordPermission(.healthKit, status: status)

        switch status {
        case .denied, .restricted:
            throw BridgeError.permissionDenied(.healthKit)
        case .notDetermined:
            break
        case .granted, .writeOnly, .unavailable:
            break
        }
    }

    private func parseISODate(_ value: String?) -> Date? {
        CodeModeDate.parse(value)
    }

    #if canImport(HealthKit)
    private struct HealthReadSpec {
        var name: String
        var sampleType: HKSampleType
        var objectType: HKObjectType
        var quantityIdentifier: HKQuantityTypeIdentifier?
        var defaultUnit: HKUnit?
        var isCategory: Bool
        var isWorkout: Bool
    }

    private struct HealthWriteSpec {
        var name: String
        var identifier: HKQuantityTypeIdentifier
        var defaultUnit: HKUnit
    }

    private func readSpec(for type: String) throws -> HealthReadSpec {
        let key = normalize(type)

        switch key {
        case "stepcount":
            guard let quantityType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
                throw BridgeError.invalidArguments("health.read type stepCount is not available on this platform")
            }
            return .init(
                name: "stepCount",
                sampleType: quantityType,
                objectType: quantityType,
                quantityIdentifier: .stepCount,
                defaultUnit: .count(),
                isCategory: false,
                isWorkout: false
            )
        case "heartrate":
            guard let quantityType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
                throw BridgeError.invalidArguments("health.read type heartRate is not available on this platform")
            }
            return .init(
                name: "heartRate",
                sampleType: quantityType,
                objectType: quantityType,
                quantityIdentifier: .heartRate,
                defaultUnit: HKUnit.count().unitDivided(by: .minute()),
                isCategory: false,
                isWorkout: false
            )
        case "activeenergyburned":
            guard let quantityType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
                throw BridgeError.invalidArguments("health.read type activeEnergyBurned is not available on this platform")
            }
            return .init(
                name: "activeEnergyBurned",
                sampleType: quantityType,
                objectType: quantityType,
                quantityIdentifier: .activeEnergyBurned,
                defaultUnit: .kilocalorie(),
                isCategory: false,
                isWorkout: false
            )
        case "bodymass":
            guard let quantityType = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
                throw BridgeError.invalidArguments("health.read type bodyMass is not available on this platform")
            }
            return .init(
                name: "bodyMass",
                sampleType: quantityType,
                objectType: quantityType,
                quantityIdentifier: .bodyMass,
                defaultUnit: .gramUnit(with: .kilo),
                isCategory: false,
                isWorkout: false
            )
        case "distancewalkingrunning":
            guard let quantityType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) else {
                throw BridgeError.invalidArguments("health.read type distanceWalkingRunning is not available on this platform")
            }
            return .init(
                name: "distanceWalkingRunning",
                sampleType: quantityType,
                objectType: quantityType,
                quantityIdentifier: .distanceWalkingRunning,
                defaultUnit: .meter(),
                isCategory: false,
                isWorkout: false
            )
        case "sleepanalysis":
            guard let categoryType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
                throw BridgeError.invalidArguments("health.read type sleepAnalysis is not available on this platform")
            }
            return .init(
                name: "sleepAnalysis",
                sampleType: categoryType,
                objectType: categoryType,
                quantityIdentifier: nil,
                defaultUnit: nil,
                isCategory: true,
                isWorkout: false
            )
        case "workout", "workouts":
            let workoutType = HKObjectType.workoutType()
            return .init(
                name: "workout",
                sampleType: workoutType,
                objectType: workoutType,
                quantityIdentifier: nil,
                defaultUnit: nil,
                isCategory: false,
                isWorkout: true
            )
        default:
            throw BridgeError.invalidArguments(
                "Unsupported health.read type '\(type)'. Supported: stepCount, heartRate, activeEnergyBurned, bodyMass, distanceWalkingRunning, sleepAnalysis, workout"
            )
        }
    }

    private func writeSpec(for type: String) throws -> HealthWriteSpec {
        let key = normalize(type)

        switch key {
        case "stepcount":
            return .init(name: "stepCount", identifier: .stepCount, defaultUnit: .count())
        case "heartrate":
            return .init(name: "heartRate", identifier: .heartRate, defaultUnit: HKUnit.count().unitDivided(by: .minute()))
        case "activeenergyburned":
            return .init(name: "activeEnergyBurned", identifier: .activeEnergyBurned, defaultUnit: .kilocalorie())
        case "bodymass":
            return .init(name: "bodyMass", identifier: .bodyMass, defaultUnit: .gramUnit(with: .kilo))
        case "distancewalkingrunning":
            return .init(name: "distanceWalkingRunning", identifier: .distanceWalkingRunning, defaultUnit: .meter())
        default:
            throw BridgeError.invalidArguments(
                "Unsupported health.write type '\(type)'. Supported writable types: stepCount, heartRate, activeEnergyBurned, bodyMass, distanceWalkingRunning"
            )
        }
    }

    private func requestedReadTypes(from names: [String]) throws -> Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        for name in names {
            let spec = try readSpec(for: name)
            types.insert(spec.objectType)
        }
        return types
    }

    private func requestedWriteTypes(from names: [String]) throws -> Set<HKSampleType> {
        var types: Set<HKSampleType> = []
        for name in names {
            let spec = try writeSpec(for: name)
            guard let quantityType = HKObjectType.quantityType(forIdentifier: spec.identifier) else {
                throw BridgeError.invalidArguments("health.write type \(name) is not available on this platform")
            }
            types.insert(quantityType)
        }
        return types
    }

    /// Per-type share authorization, which is the only part HealthKit answers
    /// honestly. Read authorization is deliberately undisclosed by the framework.
    private func writeAuthorizationStatuses(for names: [String]) -> [String: JSONValue] {
        var statuses: [String: JSONValue] = [:]
        for name in names {
            guard let spec = try? writeSpec(for: name),
                  let quantityType = HKObjectType.quantityType(forIdentifier: spec.identifier)
            else {
                continue
            }
            statuses[name] = .string(Self.shareStatusName(healthStore.authorizationStatus(for: quantityType)))
        }
        return statuses
    }

    /// `.granted` only when every requested share type is actually authorized;
    /// otherwise `.notDetermined`, because HealthKit will not say more.
    private func resolvedShareAuthorization(for toShare: Set<HKSampleType>) -> PermissionStatus {
        guard toShare.isEmpty == false else {
            return .notDetermined
        }
        let allShared = toShare.allSatisfy { healthStore.authorizationStatus(for: $0) == .sharingAuthorized }
        return allShared ? .granted : .notDetermined
    }

    private static func shareStatusName(_ status: HKAuthorizationStatus) -> String {
        switch status {
        case .sharingAuthorized:
            return PermissionStatus.granted.rawValue
        case .sharingDenied:
            return PermissionStatus.denied.rawValue
        case .notDetermined:
            return PermissionStatus.notDetermined.rawValue
        @unknown default:
            return PermissionStatus.unavailable.rawValue
        }
    }

    private func ensureAuthorization(
        toShare: Set<HKSampleType>,
        read: Set<HKObjectType>,
        context: BridgeInvocationContext,
        forceRequest: Bool = false
    ) throws {
        if forceRequest {
            context.recordPermission(.healthKit, status: .notDetermined)
            let granted = try requestAuthorization(toShare: toShare, read: read)
            let resolved: PermissionStatus = granted ? .granted : .denied
            context.recordPermission(.healthKit, status: resolved)
            guard granted else {
                throw BridgeError.permissionDenied(.healthKit)
            }
            return
        }

        let requestStatus = try authorizationRequestStatus(toShare: toShare, read: read)
        switch requestStatus {
        case .unnecessary:
            // `.unnecessary` means "there is nothing left to ask the user", not
            // "access was granted" — for read types the user may well have
            // denied. Record what is actually known: granted only when every
            // share type says so, otherwise leave it undetermined rather than
            // writing a granted claim into the transcript.
            context.recordPermission(.healthKit, status: resolvedShareAuthorization(for: toShare))
        case .shouldRequest, .unknown:
            context.recordPermission(.healthKit, status: .notDetermined)
            let granted = try requestAuthorization(toShare: toShare, read: read)
            let resolved: PermissionStatus = granted ? .granted : .denied
            context.recordPermission(.healthKit, status: resolved)
            guard granted else {
                throw BridgeError.permissionDenied(.healthKit)
            }
        @unknown default:
            context.recordPermission(.healthKit, status: .unavailable)
            throw BridgeError.nativeFailure("Unknown HealthKit authorization status")
        }
    }

    private func authorizationRequestStatus(
        toShare: Set<HKSampleType>,
        read: Set<HKObjectType>
    ) throws -> HKAuthorizationRequestStatus {
        let semaphore = DispatchSemaphore(value: 0)
        let status = LockedBox<HKAuthorizationRequestStatus?>(nil)
        let errorBox = LockedBox<Error?>(nil)

        healthStore.getRequestStatusForAuthorization(toShare: toShare, read: read) { requestStatus, error in
            if let error {
                errorBox.set(error)
            } else {
                status.set(requestStatus)
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 15) == .timedOut {
            throw BridgeError.timeout(milliseconds: 15_000)
        }

        if let error = errorBox.get() {
            throw BridgeError.nativeFailure("health.requestStatus failed: \(error.localizedDescription)")
        }

        return status.get() ?? .unknown
    }

    private func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKObjectType>) throws -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let result = LockedBox<Bool>(false)
        let errorBox = LockedBox<Error?>(nil)

        healthStore.requestAuthorization(toShare: toShare, read: read) { success, error in
            result.set(success)
            if let error {
                errorBox.set(error)
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 15) == .timedOut {
            throw BridgeError.timeout(milliseconds: 15_000)
        }

        if let error = errorBox.get() {
            throw BridgeError.nativeFailure("health.requestAuthorization failed: \(error.localizedDescription)")
        }

        return result.get()
    }

    private func querySamples(
        sampleType: HKSampleType,
        predicate: NSPredicate?,
        limit: Int,
        sortDescriptors: [NSSortDescriptor]
    ) throws -> [HKSample] {
        let semaphore = DispatchSemaphore(value: 0)
        let samplesBox = LockedBox<[HKSample]>([])
        let errorBox = LockedBox<Error?>(nil)

        let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: limit, sortDescriptors: sortDescriptors) { _, samples, error in
            if let error {
                errorBox.set(error)
            } else {
                samplesBox.set(samples ?? [])
            }
            semaphore.signal()
        }
        healthStore.execute(query)

        if semaphore.wait(timeout: .now() + 15) == .timedOut {
            throw BridgeError.timeout(milliseconds: 15_000)
        }

        if let error = errorBox.get() {
            throw BridgeError.nativeFailure("health.read query failed: \(error.localizedDescription)")
        }

        return samplesBox.get()
    }

    private func save(sample: HKSample) throws {
        let semaphore = DispatchSemaphore(value: 0)
        let successBox = LockedBox<Bool>(false)
        let errorBox = LockedBox<Error?>(nil)

        healthStore.save(sample) { success, error in
            successBox.set(success)
            if let error {
                errorBox.set(error)
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 15) == .timedOut {
            throw BridgeError.timeout(milliseconds: 15_000)
        }

        if let error = errorBox.get() {
            throw BridgeError.nativeFailure("health.write failed: \(error.localizedDescription)")
        }

        guard successBox.get() else {
            throw BridgeError.nativeFailure("health.write failed: save returned false")
        }
    }

    private func serializeReadSample(sample: HKSample, spec: HealthReadSpec, unitOverride: String?) -> JSONValue {
        var payload: [String: JSONValue] = [
            "identifier": .string(sample.uuid.uuidString),
            "type": .string(spec.name),
            "startDate": .string(sample.startDate.ISO8601Format()),
            "endDate": .string(sample.endDate.ISO8601Format()),
            "source": .string(sample.sourceRevision.source.name),
        ]

        if spec.isWorkout, let workout = sample as? HKWorkout {
            payload["activityType"] = .number(Double(workout.workoutActivityType.rawValue))
            payload["durationSeconds"] = .number(workout.duration)
            payload["totalEnergyBurnedKCal"] = .number(workoutActiveEnergyBurnedKCal(workout))
            payload["totalDistanceMeters"] = .number(workout.totalDistance?.doubleValue(for: .meter()) ?? 0)
            return .object(payload)
        }

        if spec.isCategory, let category = sample as? HKCategorySample {
            payload["value"] = .number(Double(category.value))
            return .object(payload)
        }

        if let quantitySample = sample as? HKQuantitySample, let defaultUnit = spec.defaultUnit {
            let unit = (try? resolveUnit(override: unitOverride, fallback: defaultUnit)) ?? defaultUnit
            payload["value"] = .number(quantitySample.quantity.doubleValue(for: unit))
            payload["unit"] = .string(unit.unitString)
        }

        return .object(payload)
    }

    private func workoutActiveEnergyBurnedKCal(_ workout: HKWorkout) -> Double {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
              let quantity = workout.statistics(for: quantityType)?.sumQuantity()
        else {
            return 0
        }
        return quantity.doubleValue(for: .kilocalorie())
    }

    private func resolveUnit(override: String?, fallback: HKUnit) throws -> HKUnit {
        guard let override, override.isEmpty == false else {
            return fallback
        }

        let key = normalize(override)
        switch key {
        case "count":
            return .count()
        case "bpm", "countperminute", "count/min":
            return HKUnit.count().unitDivided(by: .minute())
        case "kcal", "kilocalorie":
            return .kilocalorie()
        case "kg", "kilogram":
            return .gramUnit(with: .kilo)
        case "m", "meter", "metre":
            return .meter()
        default:
            throw BridgeError.invalidArguments("Unsupported HealthKit unit '\(override)'")
        }
    }
    #endif

    private func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }
}
