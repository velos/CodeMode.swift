import Foundation

#if canImport(CoreLocation)
@preconcurrency import CoreLocation
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

#if canImport(Speech)
import Speech
#endif

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(MediaPlayer) && !os(macOS) && !os(watchOS)
import MediaPlayer
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
    /// How long a `request(for:)` waits on the system's TCC dialog before giving
    /// up and re-reading the status. This is a human-latency budget, and it is
    /// short: a user who takes longer than this leaves the caller reading the
    /// pre-prompt status.
    static let permissionPromptTimeoutSeconds: TimeInterval = 10

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
        case .speechRecognition:
            return speechRecognitionStatus()
        case .microphone:
            return microphoneStatus()
        case .music:
            return musicStatus()
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
        case .speechRecognition:
            return requestSpeechRecognitionPermission()
        case .microphone:
            return requestMicrophonePermission()
        case .music:
            return requestMusicPermission()
        }
    }

    private func locationStatus() -> PermissionStatus {
        #if canImport(CoreLocation)
        return Self.mapLocationAuthorization(CLLocationManager().authorizationStatus)
        #else
        return .unavailable
        #endif
    }

    #if canImport(CoreLocation)
    static func mapLocationAuthorization(_ status: CLAuthorizationStatus) -> PermissionStatus {
        switch status {
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
    }
    #endif

    private func contactsStatus() -> PermissionStatus {
        #if canImport(Contacts)
        switch CNContactStore.authorizationStatus(for: .contacts) {
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

    /// Reads HomeKit authorization *without* constructing a manager.
    ///
    /// Constructing `HMHomeManager` is itself what triggers the HomeKit TCC
    /// prompt, so the previous implementation put a user-facing dialog inside a
    /// status check — and `requestHomeKitPermission` called it twice, then built a
    /// third manager. A status query now answers from the shared manager if one
    /// already exists and otherwise fails closed with `.notDetermined`, which
    /// routes the caller through the request path where a prompt belongs.
    private func homeKitStatus() -> PermissionStatus {
        #if canImport(HomeKit)
        guard let manager = Self.existingHomeManager() else {
            return .notDetermined
        }
        return Self.mapHomeKitAuthorization(manager.authorizationStatus)
        #else
        return .unavailable
        #endif
    }

    #if canImport(HomeKit)
    /// Process-wide so repeated permission work reuses one manager instead of
    /// re-triggering the prompt.
    private static let homeManagerBox = LockedBox<HMHomeManager?>(nil)

    private static func existingHomeManager() -> HMHomeManager? {
        homeManagerBox.get()
    }

    /// Creates the shared manager if needed. This is the call that prompts.
    private static func makeHomeManager(delegate: HMHomeManagerDelegate) -> HMHomeManager {
        if let existing = homeManagerBox.get() {
            existing.delegate = delegate
            return existing
        }
        let manager = HMHomeManager()
        manager.delegate = delegate
        homeManagerBox.set(manager)
        return manager
    }

    private static func mapHomeKitAuthorization(_ status: HMHomeManagerAuthorizationStatus) -> PermissionStatus {
        if status.contains(.authorized) {
            return .granted
        }
        if status.contains(.restricted) {
            return .restricted
        }
        if status.contains(.determined) {
            return .notDetermined
        }
        return .unavailable
    }
    #endif

    private func speechRecognitionStatus() -> PermissionStatus {
        #if canImport(Speech)
        switch SFSpeechRecognizer.authorizationStatus() {
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

    private func microphoneStatus() -> PermissionStatus {
        #if canImport(AVFoundation)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
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

    private func musicStatus() -> PermissionStatus {
        #if canImport(MediaPlayer) && !os(macOS) && !os(watchOS)
        switch MPMediaLibrary.authorizationStatus() {
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
        return .notDetermined
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
        let delegate = LocationPermissionDelegate()

        if Thread.isMainThread {
            let manager = CLLocationManager()
            manager.delegate = delegate
            delegate.hold(manager)
            manager.requestWhenInUseAuthorization()
            // Cannot block main for the callback; the caller sees the pre-prompt
            // status and a later call observes the resolved one.
            return locationStatus()
        }

        // `CLLocationManager` delivers delegate callbacks on the run loop of the
        // thread that *created* it, and the bridge's GCD workers have none — so a
        // manager constructed here never called back, the wait below always burned
        // its full 10s, and the result was reported from a status re-read that
        // races the TCC write. Creating the manager, assigning the delegate, and
        // requesting all happen on main.
        //
        // async, not sync: the host may be blocking main waiting on our result, so
        // main.sync would deadlock. If main never runs this, the wait times out.
        DispatchQueue.main.async {
            let manager = CLLocationManager()
            manager.delegate = delegate
            delegate.hold(manager)
            manager.requestWhenInUseAuthorization()
        }

        guard delegate.wait(timeout: 10) == .success else {
            return locationStatus()
        }

        // Prefer the status the delegate callback carried over a fresh read,
        // which can still observe the pre-prompt value.
        return delegate.observedStatus().map(Self.mapLocationAuthorization) ?? locationStatus()
        #else
        return .unavailable
        #endif
    }

    private func requestContactsPermission() -> PermissionStatus {
        #if canImport(Contacts)
        let store = CNContactStore()
        CompletionWait.completion(timeout: Self.permissionPromptTimeoutSeconds) { complete in
            store.requestAccess(for: .contacts) { _, _ in complete() }
        }
        return contactsStatus()
        #else
        return .unavailable
        #endif
    }

    private func requestCalendarPermission() -> PermissionStatus {
        #if canImport(EventKit)
        let store = EKEventStore()
        CompletionWait.completion(timeout: Self.permissionPromptTimeoutSeconds) { complete in
            if #available(iOS 17.0, macOS 14.0, *) {
                store.requestFullAccessToEvents { _, _ in complete() }
            } else {
                store.requestAccess(to: .event) { _, _ in complete() }
            }
        }
        return calendarReadStatus()
        #else
        return .unavailable
        #endif
    }

    private func requestCalendarWritePermission() -> PermissionStatus {
        #if canImport(EventKit)
        let store = EKEventStore()
        CompletionWait.completion(timeout: Self.permissionPromptTimeoutSeconds) { complete in
            if #available(iOS 17.0, macOS 14.0, *) {
                store.requestWriteOnlyAccessToEvents { _, _ in complete() }
            } else {
                store.requestAccess(to: .event) { _, _ in complete() }
            }
        }
        return calendarWriteStatus()
        #else
        return .unavailable
        #endif
    }

    private func requestRemindersPermission() -> PermissionStatus {
        #if canImport(EventKit)
        let store = EKEventStore()
        CompletionWait.completion(timeout: Self.permissionPromptTimeoutSeconds) { complete in
            if #available(iOS 17.0, macOS 14.0, *) {
                store.requestFullAccessToReminders { _, _ in complete() }
            } else {
                store.requestAccess(to: .reminder) { _, _ in complete() }
            }
        }
        return remindersStatus()
        #else
        return .unavailable
        #endif
    }

    private func requestPhotoLibraryPermission() -> PermissionStatus {
        #if canImport(Photos)
        CompletionWait.completion(timeout: Self.permissionPromptTimeoutSeconds) { complete in
            if #available(iOS 14.0, macOS 11.0, *) {
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in complete() }
            } else {
                PHPhotoLibrary.requestAuthorization { _ in complete() }
            }
        }
        return photoLibraryStatus()
        #else
        return .unavailable
        #endif
    }

    private func requestNotificationsPermission() -> PermissionStatus {
        #if canImport(UserNotifications)
        CompletionWait.completion(timeout: Self.permissionPromptTimeoutSeconds) { complete in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
                complete()
            }
        }
        return notificationsStatus()
        #else
        return .unavailable
        #endif
    }

    private func requestHomeKitPermission() -> PermissionStatus {
        #if canImport(HomeKit)
        // One status read, not two, and one manager, not three: each construction
        // is a potential prompt.
        let current = homeKitStatus()
        if current != .notDetermined, Self.existingHomeManager() != nil {
            return current
        }

        let delegate = HomeKitPermissionDelegate()
        let manager = Self.makeHomeManager(delegate: delegate)
        _ = delegate.wait(timeout: Self.permissionPromptTimeoutSeconds)
        return Self.mapHomeKitAuthorization(manager.authorizationStatus)
        #else
        return .unavailable
        #endif
    }

    private func requestHealthKitPermission() -> PermissionStatus {
        healthKitStatus()
    }

    private func requestSpeechRecognitionPermission() -> PermissionStatus {
        #if canImport(Speech)
        let semaphore = DispatchSemaphore(value: 0)
        SFSpeechRecognizer.requestAuthorization { _ in
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        return speechRecognitionStatus()
        #else
        return .unavailable
        #endif
    }

    private func requestMicrophonePermission() -> PermissionStatus {
        #if canImport(AVFoundation)
        let semaphore = DispatchSemaphore(value: 0)
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        return microphoneStatus()
        #else
        return .unavailable
        #endif
    }

    private func requestMusicPermission() -> PermissionStatus {
        #if canImport(MediaPlayer) && !os(macOS) && !os(watchOS)
        let semaphore = DispatchSemaphore(value: 0)
        MPMediaLibrary.requestAuthorization { _ in
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        return musicStatus()
        #else
        return .unavailable
        #endif
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
    private let lock = NSLock()
    private var status: CLAuthorizationStatus?
    /// The manager is created inside a `DispatchQueue.main.async` block and would
    /// otherwise be released as soon as that block returns — before the callback
    /// it exists to receive. `CLLocationManager` does not retain its delegate, so
    /// the ownership runs the other way here.
    private var manager: CLLocationManager?

    func hold(_ manager: CLLocationManager) {
        lock.lock()
        self.manager = manager
        lock.unlock()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        lock.lock()
        status = manager.authorizationStatus
        lock.unlock()
        semaphore.signal()
    }

    func observedStatus() -> CLAuthorizationStatus? {
        lock.lock()
        defer { lock.unlock() }
        return status
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
