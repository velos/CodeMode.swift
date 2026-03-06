import Foundation

#if canImport(AlarmKit)
import AlarmKit
#endif

#if canImport(SwiftUI)
import SwiftUI
#endif

public final class AlarmBridge: @unchecked Sendable {
    private static let scheduledAlarms = LockedBox<[String: [String: JSONValue]]>([:])

    public init() {}

    public func requestPermission(context: BridgeInvocationContext) throws -> JSONValue {
        let requested = context.permissionBroker.request(for: .alarmKit)
        context.recordPermission(.alarmKit, status: requested)
        return .object([
            "status": .string(requested.rawValue),
            "granted": .bool(requested == .granted),
        ])
    }

    public func read(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let status = resolvePermission(context: context)
        guard status == .granted else {
            throw BridgeError.permissionDenied(.alarmKit)
        }

        let limit = max(1, arguments.int("limit") ?? 50)
        let alarms = Array(Self.scheduledAlarms.get().values.prefix(limit))
        return .array(alarms.map(JSONValue.object))
    }

    public func schedule(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard let title = arguments.string("title"), title.isEmpty == false else {
            throw BridgeError.invalidArguments("alarm.schedule requires title")
        }

        let status = resolvePermission(context: context)
        guard status == .granted else {
            throw BridgeError.permissionDenied(.alarmKit)
        }

        let requestedIdentifier = arguments.string("identifier")
        let alarmID = UUID(uuidString: requestedIdentifier ?? "") ?? UUID()
        let fireDate = isoDate(arguments.string("fireDate"))
        let fallbackSeconds = arguments.double("secondsFromNow") ?? 60
        let secondsFromNow: TimeInterval
        if let fireDate {
            secondsFromNow = max(1, fireDate.timeIntervalSinceNow)
        } else {
            secondsFromNow = max(1, fallbackSeconds)
        }

        #if canImport(AlarmKit) && canImport(SwiftUI) && os(iOS)
        if #available(iOS 26.0, *) {
            try runScheduleNative(alarmID: alarmID, title: title, secondsFromNow: secondsFromNow)
            let snapshot = scheduledAlarmSnapshot(
                id: alarmID.uuidString,
                title: title,
                secondsFromNow: secondsFromNow,
                fireDate: fireDate
            )
            upsertScheduledAlarm(snapshot)

            return .object([
                "identifier": .string(alarmID.uuidString),
                "scheduled": .bool(true),
                "title": .string(title),
            ])
        }
        #endif

        _ = title
        throw BridgeError.unsupportedPlatform("AlarmKit")
    }

    public func cancel(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let status = resolvePermission(context: context)
        guard status == .granted else {
            throw BridgeError.permissionDenied(.alarmKit)
        }

        let known = Self.scheduledAlarms.get()
        let targets: [String]
        if let identifier = arguments.string("identifier"), identifier.isEmpty == false {
            targets = [identifier]
        } else if let identifiers = arguments.array("identifiers")?.compactMap(\.stringValue), identifiers.isEmpty == false {
            targets = identifiers
        } else {
            targets = Array(known.keys)
        }

        #if canImport(AlarmKit) && os(iOS)
        if #available(iOS 26.0, *) {
            let uuids = targets.compactMap(UUID.init(uuidString:))
            try runCancelNative(alarmIDs: uuids)
            removeScheduledAlarms(ids: targets)

            return .object([
                "deleted": .bool(true),
                "count": .number(Double(targets.count)),
            ])
        }
        #endif

        throw BridgeError.unsupportedPlatform("AlarmKit")
    }

    private func resolvePermission(context: BridgeInvocationContext) -> PermissionStatus {
        context.resolvedPermission(for: .alarmKit)
    }

    private func scheduledAlarmSnapshot(id: String, title: String, secondsFromNow: TimeInterval, fireDate: Date?) -> [String: JSONValue] {
        [
            "identifier": .string(id),
            "title": .string(title),
            "secondsFromNow": .number(secondsFromNow),
            "fireDate": .string(fireDate?.ISO8601Format() ?? ""),
            "scheduledAt": .string(Date().ISO8601Format()),
        ]
    }

    private func upsertScheduledAlarm(_ alarm: [String: JSONValue]) {
        guard let id = alarm["identifier"]?.stringValue else { return }
        var current = Self.scheduledAlarms.get()
        current[id] = alarm
        Self.scheduledAlarms.set(current)
    }

    private func removeScheduledAlarms(ids: [String]) {
        var current = Self.scheduledAlarms.get()
        for id in ids {
            current.removeValue(forKey: id)
        }
        Self.scheduledAlarms.set(current)
    }

    private func isoDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }

    #if canImport(AlarmKit) && canImport(SwiftUI) && os(iOS)
    @available(iOS 26.0, *)
    private func runScheduleNative(alarmID: UUID, title: String, secondsFromNow: TimeInterval) throws {
        let semaphore = DispatchSemaphore(value: 0)
        let errorBox = LockedBox<Error?>(nil)

        Task {
            do {
                let stopButton = AlarmButton(text: "Stop")
                let alert = AlarmPresentation.Alert(
                    title: LocalizedStringResource(stringLiteral: title),
                    stopButton: stopButton
                )

                let attributes = AlarmAttributes(
                    presentation: AlarmPresentation(alert: alert),
                    metadata: BridgeAlarmMetadata(),
                    tintColor: .blue
                )

                let duration = Alarm.CountdownDuration(
                    preAlert: 0,
                    postAlert: max(1, Int(secondsFromNow.rounded()))
                )

                let configuration = AlarmManager.AlarmConfiguration<BridgeAlarmMetadata>(
                    countdownDuration: duration,
                    attributes: attributes
                )

                _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
            } catch {
                errorBox.set(error)
            }

            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 15) == .timedOut {
            throw BridgeError.timeout(milliseconds: 15_000)
        }

        if let error = errorBox.get() {
            throw BridgeError.nativeFailure("alarm.schedule failed: \(error.localizedDescription)")
        }
    }

    @available(iOS 26.0, *)
    private func runCancelNative(alarmIDs: [UUID]) throws {
        let semaphore = DispatchSemaphore(value: 0)
        let errorBox = LockedBox<Error?>(nil)

        Task {
            do {
                for alarmID in alarmIDs {
                    try await AlarmManager.shared.stop(id: alarmID)
                }
            } catch {
                errorBox.set(error)
            }

            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 15) == .timedOut {
            throw BridgeError.timeout(milliseconds: 15_000)
        }

        if let error = errorBox.get() {
            throw BridgeError.nativeFailure("alarm.cancel failed: \(error.localizedDescription)")
        }
    }

    @available(iOS 26.0, *)
    private struct BridgeAlarmMetadata: AlarmMetadata {}
    #endif
}
