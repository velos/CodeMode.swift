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

#if canImport(Photos)
import Photos
#endif

#if canImport(UserNotifications)
import UserNotifications
#endif

#if canImport(AlarmKit)
import AlarmKit
#endif

#if canImport(HealthKit)
import HealthKit
#endif

#if canImport(HomeKit)
import HomeKit
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
        case .photoLibrary:
            return photoLibraryStatus()
        case .notifications:
            return notificationsStatus()
        case .alarmKit:
            return alarmKitStatus()
        case .healthKit:
            return healthKitStatus()
        case .homeKit:
            return homeKitStatus()
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
        case .photoLibrary:
            return requestPhotoLibraryPermission()
        case .notifications:
            return requestNotificationsPermission()
        case .alarmKit:
            return requestAlarmKitPermission()
        case .healthKit:
            return requestHealthKitPermission()
        case .homeKit:
            return requestHomeKitPermission()
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

    private func photoLibraryStatus() -> PermissionStatus {
        #if canImport(Photos)
        if #available(iOS 14.0, macOS 11.0, *) {
            switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
            case .authorized, .limited:
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

        switch PHPhotoLibrary.authorizationStatus() {
        case .authorized:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        case .limited:
            return .granted
        @unknown default:
            return .unavailable
        }
        #else
        return .unavailable
        #endif
    }

    private func notificationsStatus() -> PermissionStatus {
        #if canImport(UserNotifications)
        let semaphore = DispatchSemaphore(value: 0)
        let resolved = LockedBox<PermissionStatus>(.unavailable)

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                resolved.set(.granted)
            case .denied:
                resolved.set(.denied)
            case .notDetermined:
                resolved.set(.notDetermined)
            @unknown default:
                resolved.set(.unavailable)
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 10)
        return resolved.get()
        #else
        return .unavailable
        #endif
    }

    private func homeKitStatus() -> PermissionStatus {
        #if canImport(HomeKit)
        switch HMHomeManager.authorizationStatus() {
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

    private func healthKitStatus() -> PermissionStatus {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailable
        }
        return .granted
        #else
        return .unavailable
        #endif
    }

    private func alarmKitStatus() -> PermissionStatus {
        #if canImport(AlarmKit) && os(iOS)
        if #available(iOS 26.0, *) {
            return mapAlarmAuthorizationDescription(String(describing: AlarmManager.shared.authorizationState))
        }
        return .unavailable
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

    private func requestPhotoLibraryPermission() -> PermissionStatus {
        #if canImport(Photos)
        let semaphore = DispatchSemaphore(value: 0)

        if #available(iOS 14.0, macOS 11.0, *) {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
                semaphore.signal()
            }
        } else {
            PHPhotoLibrary.requestAuthorization { _ in
                semaphore.signal()
            }
        }

        _ = semaphore.wait(timeout: .now() + 10)
        return photoLibraryStatus()
        #else
        return .unavailable
        #endif
    }

    private func requestNotificationsPermission() -> PermissionStatus {
        #if canImport(UserNotifications)
        let semaphore = DispatchSemaphore(value: 0)

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 10)
        return notificationsStatus()
        #else
        return .unavailable
        #endif
    }

    private func requestHomeKitPermission() -> PermissionStatus {
        #if canImport(HomeKit)
        if homeKitStatus() != .notDetermined {
            return homeKitStatus()
        }

        let delegate = HomeKitPermissionDelegate()
        let manager = HMHomeManager()
        manager.delegate = delegate
        _ = delegate.wait(timeout: 10)
        return homeKitStatus()
        #else
        return .unavailable
        #endif
    }

    private func requestHealthKitPermission() -> PermissionStatus {
        healthKitStatus()
    }

    private func requestAlarmKitPermission() -> PermissionStatus {
        #if canImport(AlarmKit) && os(iOS)
        if #available(iOS 26.0, *) {
            let current = alarmKitStatus()
            if current != .notDetermined {
                return current
            }

            let semaphore = DispatchSemaphore(value: 0)
            let requested = LockedBox<PermissionStatus>(.unavailable)

            Task {
                do {
                    let state = try await AlarmManager.shared.requestAuthorization()
                    requested.set(mapAlarmAuthorizationDescription(String(describing: state)))
                } catch {
                    requested.set(.denied)
                }
                semaphore.signal()
            }

            if semaphore.wait(timeout: .now() + 15) == .timedOut {
                return .unavailable
            }

            return requested.get()
        }

        return .unavailable
        #else
        return .unavailable
        #endif
    }

    private func mapAlarmAuthorizationDescription(_ description: String) -> PermissionStatus {
        let value = description.replacingOccurrences(of: " ", with: "").lowercased()
        if value.contains("authorized") {
            return .granted
        }
        if value.contains("denied") {
            return .denied
        }
        if value.contains("notdetermined") {
            return .notDetermined
        }
        return .unavailable
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

#if canImport(HomeKit)
private final class HomeKitPermissionDelegate: NSObject, HMHomeManagerDelegate {
    private let semaphore = DispatchSemaphore(value: 0)

    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        _ = manager
        semaphore.signal()
    }

    func wait(timeout: TimeInterval) -> DispatchTimeoutResult {
        semaphore.wait(timeout: .now() + timeout)
    }
}
#endif
