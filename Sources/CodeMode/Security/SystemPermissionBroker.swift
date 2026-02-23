import Foundation

#if canImport(CoreLocation)
import CoreLocation
#endif

#if canImport(Contacts)
import Contacts
#endif

#if canImport(EventKit)
import EventKit
#endif

public final class SystemPermissionBroker: PermissionBroker, @unchecked Sendable {
    public init() {}

    public func status(for permission: PermissionKind) -> PermissionStatus {
        switch permission {
        case .locationWhenInUse:
            return locationStatus()
        case .contacts:
            return contactsStatus()
        case .calendar:
            return calendarReadStatus()
        case .calendarWriteOnly:
            return calendarWriteStatus()
        case .reminders:
            return remindersStatus()
        }
    }

    public func request(for permission: PermissionKind) -> PermissionStatus {
        switch permission {
        case .locationWhenInUse:
            return requestLocationPermission()
        case .contacts:
            return requestContactsPermission()
        case .calendar:
            return requestCalendarPermission()
        case .calendarWriteOnly:
            return requestCalendarWritePermission()
        case .reminders:
            return requestRemindersPermission()
        }
    }

    private func locationStatus() -> PermissionStatus {
        #if canImport(CoreLocation)
        let manager = CLLocationManager()
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unavailable
        }
        #else
        return .unavailable
        #endif
    }

    private func contactsStatus() -> PermissionStatus {
        #if canImport(Contacts)
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unavailable
        }
        #else
        return .unavailable
        #endif
    }

    private func calendarReadStatus() -> PermissionStatus {
        #if canImport(EventKit)
        if #available(iOS 17.0, macOS 14.0, *) {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess:
                return .granted
            case .writeOnly:
                return .writeOnly
            case .denied:
                return .denied
            case .restricted:
                return .restricted
            case .notDetermined:
                return .notDetermined
            @unknown default:
                return .unavailable
            }
        }

        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        case .fullAccess, .writeOnly:
            return .granted
        @unknown default:
            return .unavailable
        }
        #else
        return .unavailable
        #endif
    }

    private func calendarWriteStatus() -> PermissionStatus {
        #if canImport(EventKit)
        if #available(iOS 17.0, macOS 14.0, *) {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess, .writeOnly:
                return .granted
            case .denied:
                return .denied
            case .restricted:
                return .restricted
            case .notDetermined:
                return .notDetermined
            @unknown default:
                return .unavailable
            }
        }

        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        case .fullAccess, .writeOnly:
            return .granted
        @unknown default:
            return .unavailable
        }
        #else
        return .unavailable
        #endif
    }

    private func remindersStatus() -> PermissionStatus {
        #if canImport(EventKit)
        if #available(iOS 17.0, macOS 14.0, *) {
            switch EKEventStore.authorizationStatus(for: .reminder) {
            case .fullAccess, .writeOnly:
                return .granted
            case .denied:
                return .denied
            case .restricted:
                return .restricted
            case .notDetermined:
                return .notDetermined
            @unknown default:
                return .unavailable
            }
        }

        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .authorized:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        case .fullAccess, .writeOnly:
            return .granted
        @unknown default:
            return .unavailable
        }
        #else
        return .unavailable
        #endif
    }

    private func requestLocationPermission() -> PermissionStatus {
        #if canImport(CoreLocation) && os(iOS)
        let manager = CLLocationManager()
        let delegate = LocationPermissionDelegate()
        manager.delegate = delegate

        DispatchQueue.main.sync {
            manager.requestWhenInUseAuthorization()
        }

        _ = delegate.wait(timeout: 10)
        return locationStatus()
        #else
        return .unavailable
        #endif
    }

    private func requestContactsPermission() -> PermissionStatus {
        #if canImport(Contacts)
        let semaphore = DispatchSemaphore(value: 0)
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { _, _ in
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        return contactsStatus()
        #else
        return .unavailable
        #endif
    }

    private func requestCalendarPermission() -> PermissionStatus {
        #if canImport(EventKit)
        let store = EKEventStore()
        let semaphore = DispatchSemaphore(value: 0)

        if #available(iOS 17.0, macOS 14.0, *) {
            store.requestFullAccessToEvents { _, _ in
                semaphore.signal()
            }
        } else {
            store.requestAccess(to: .event) { _, _ in
                semaphore.signal()
            }
        }

        _ = semaphore.wait(timeout: .now() + 10)
        return calendarReadStatus()
        #else
        return .unavailable
        #endif
    }

    private func requestCalendarWritePermission() -> PermissionStatus {
        #if canImport(EventKit)
        let store = EKEventStore()
        let semaphore = DispatchSemaphore(value: 0)

        if #available(iOS 17.0, macOS 14.0, *) {
            store.requestWriteOnlyAccessToEvents { _, _ in
                semaphore.signal()
            }
        } else {
            store.requestAccess(to: .event) { _, _ in
                semaphore.signal()
            }
        }

        _ = semaphore.wait(timeout: .now() + 10)
        return calendarWriteStatus()
        #else
        return .unavailable
        #endif
    }

    private func requestRemindersPermission() -> PermissionStatus {
        #if canImport(EventKit)
        let store = EKEventStore()
        let semaphore = DispatchSemaphore(value: 0)

        if #available(iOS 17.0, macOS 14.0, *) {
            store.requestFullAccessToReminders { _, _ in
                semaphore.signal()
            }
        } else {
            store.requestAccess(to: .reminder) { _, _ in
                semaphore.signal()
            }
        }

        _ = semaphore.wait(timeout: .now() + 10)
        return remindersStatus()
        #else
        return .unavailable
        #endif
    }
}

#if canImport(CoreLocation) && os(iOS)
private final class LocationPermissionDelegate: NSObject, CLLocationManagerDelegate {
    private let semaphore = DispatchSemaphore(value: 0)

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        semaphore.signal()
    }

    func wait(timeout: TimeInterval) -> DispatchTimeoutResult {
        semaphore.wait(timeout: .now() + timeout)
    }
}
#endif
