import Foundation

#if canImport(UIKit) && (os(iOS) || os(visionOS))
@preconcurrency import Contacts
@preconcurrency import ContactsUI
@preconcurrency import EventKit
@preconcurrency import EventKitUI
@preconcurrency import PhotosUI
@preconcurrency import UIKit
@preconcurrency import UniformTypeIdentifiers

public final class UIKitSystemUIPresenter: SystemUIPresenter, @unchecked Sendable {
    private static let defaultTimeoutMs = 300_000

    private let presentingViewControllerProvider: @Sendable () -> UIViewController?
    private let coordinatorLock = NSLock()
    private var retainedCoordinators: [UUID: AnyObject] = [:]

    public init(presentingViewController: @escaping @Sendable () -> UIViewController?) {
        self.presentingViewControllerProvider = presentingViewController
    }

    public func presentNewCalendarEvent(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let timeoutMs = Self.defaultTimeoutMs
        let formatter = ISO8601DateFormatter()
        let token = UUID()

        return try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                let presenter = try self.requirePresenter()
                let store = EKEventStore()
                let event = EKEvent(eventStore: store)
                event.title = arguments.string("title") ?? ""
                event.notes = arguments.string("notes")
                event.location = arguments.string("location")

                let startDate = arguments.string("start").flatMap { formatter.date(from: $0) } ?? Date()
                event.startDate = startDate
                event.endDate = arguments.string("end").flatMap { formatter.date(from: $0) }
                    ?? Calendar.current.date(byAdding: .hour, value: 1, to: startDate)
                    ?? startDate
                event.calendar = store.defaultCalendarForNewEvents

                let controller = EKEventEditViewController()
                controller.eventStore = store
                controller.event = event

                let coordinator = CalendarEventEditCoordinator { [weak self] action, event in
                    var object: [String: JSONValue] = [
                        "action": .string(self?.actionString(action) ?? "unknown"),
                    ]
                    if action == .saved, let event {
                        object["identifier"] = .string(event.eventIdentifier ?? "")
                        object["title"] = .string(event.title ?? "")
                    }
                    self?.releaseCoordinator(token)
                    complete(.success(.object(object)))
                }
                self.retainCoordinator(coordinator, token: token)
                controller.editViewDelegate = coordinator
                presenter.present(controller, animated: true)
            } catch let error as BridgeError {
                complete(.failure(error))
            } catch {
                complete(.failure(.nativeFailure(error.localizedDescription)))
            }
        }
    }

    public func pickPhotos(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let mediaType = arguments.string("mediaType")?.lowercased() ?? "any"
        let limit = max(1, arguments.int("limit") ?? 1)
        let outputDirectory = arguments.string("outputDirectory") ?? "tmp:"
        let outputURL = try context.pathPolicy.resolve(path: outputDirectory)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        let token = UUID()

        let results: [PhotoPickerSelection] = try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                let presenter = try self.requirePresenter()
                var configuration = PHPickerConfiguration()
                configuration.selectionLimit = limit
                switch mediaType {
                case "image", "photo":
                    configuration.filter = .images
                case "video":
                    configuration.filter = .videos
                default:
                    configuration.filter = nil
                }

                let controller = PHPickerViewController(configuration: configuration)
                let coordinator = PhotoPickerCoordinator { [weak self] results in
                    self?.releaseCoordinator(token)
                    complete(.success(results.map { PhotoPickerSelection(result: $0) }))
                }
                self.retainCoordinator(coordinator, token: token)
                controller.delegate = coordinator
                presenter.present(controller, animated: true)
            } catch let error as BridgeError {
                complete(.failure(error))
            } catch {
                complete(.failure(.nativeFailure(error.localizedDescription)))
            }
        }

        var exported: [JSONValue] = []
        exported.reserveCapacity(results.count)
        for (index, result) in results.enumerated() {
            try context.checkCancellation()
            exported.append(
                try exportPickerResult(
                    result,
                    index: index,
                    mediaType: mediaType,
                    outputDirectory: outputURL,
                    timeoutMs: timeoutMs,
                    context: context
                )
            )
        }
        return .array(exported)
    }

    public func pickContacts(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let mode = arguments.string("mode")?.lowercased() ?? "single"
        let displayedPropertyKeys = arguments.array("displayedPropertyKeys")?.compactMap(\.stringValue)
        let token = UUID()

        return try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                let presenter = try self.requirePresenter()
                let controller = CNContactPickerViewController()
                controller.displayedPropertyKeys = displayedPropertyKeys
                controller.predicateForSelectionOfContact = NSPredicate(value: true)

                if mode == "multiple" {
                    let coordinator = ContactMultiplePickerCoordinator { [weak self] contacts in
                        self?.releaseCoordinator(token)
                        complete(.success(.array(contacts.map { self?.mapContact($0) ?? .null })))
                    }
                    self.retainCoordinator(coordinator, token: token)
                    controller.delegate = coordinator
                } else {
                    let coordinator = ContactSinglePickerCoordinator { [weak self] contacts in
                        self?.releaseCoordinator(token)
                        complete(.success(.array(contacts.map { self?.mapContact($0) ?? .null })))
                    }
                    self.retainCoordinator(coordinator, token: token)
                    controller.delegate = coordinator
                }

                presenter.present(controller, animated: true)
            } catch let error as BridgeError {
                complete(.failure(error))
            } catch {
                complete(.failure(.nativeFailure(error.localizedDescription)))
            }
        }
    }

    private func runUIOperation<T: Sendable>(
        timeoutMs: Int,
        onTimeout: (@Sendable () -> Void)? = nil,
        start: @escaping @MainActor @Sendable (@escaping @Sendable (Result<T, BridgeError>) -> Void) -> Void
    ) throws -> T {
        if Thread.isMainThread {
            throw BridgeError.nativeFailure("System UI helpers cannot block the main thread")
        }

        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = LockedBox<Result<T, BridgeError>?>(nil)

        DispatchQueue.main.async {
            start { result in
                resultBox.set(result)
                semaphore.signal()
            }
        }

        if semaphore.wait(timeout: .now() + .milliseconds(timeoutMs)) == .timedOut {
            onTimeout?()
            throw BridgeError.timeout(milliseconds: timeoutMs)
        }

        guard let result = resultBox.get() else {
            throw BridgeError.nativeFailure("System UI operation produced no result")
        }
        return try result.get()
    }

    @MainActor private func requirePresenter() throws -> UIViewController {
        guard let presenter = presentingViewControllerProvider() else {
            throw BridgeError.uiPresenterUnavailable
        }
        return topMostPresenter(from: presenter)
    }

    @MainActor private func topMostPresenter(from root: UIViewController) -> UIViewController {
        var current = root
        while let presented = current.presentedViewController {
            current = presented
        }
        return current
    }

    private func retainCoordinator(_ coordinator: AnyObject, token: UUID) {
        coordinatorLock.lock()
        retainedCoordinators[token] = coordinator
        coordinatorLock.unlock()
    }

    private func releaseCoordinator(_ token: UUID) {
        coordinatorLock.lock()
        retainedCoordinators[token] = nil
        coordinatorLock.unlock()
    }

    private func actionString(_ action: EKEventEditViewAction) -> String {
        switch action {
        case .canceled:
            return "cancelled"
        case .saved:
            return "saved"
        case .deleted:
            return "deleted"
        @unknown default:
            return "unknown"
        }
    }

    private func exportPickerResult(
        _ result: PhotoPickerSelection,
        index: Int,
        mediaType: String,
        outputDirectory: URL,
        timeoutMs: Int,
        context: BridgeInvocationContext
    ) throws -> JSONValue {
        guard let typeIdentifier = preferredTypeIdentifier(for: result.itemProvider, mediaType: mediaType) else {
            throw BridgeError.nativeFailure("photos.ui.pick could not find an exportable type for selected item \(index)")
        }

        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = LockedBox<Result<URL, Error>?>(nil)
        result.itemProvider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { sourceURL, error in
            if let error {
                resultBox.set(.failure(error))
                semaphore.signal()
                return
            }

            guard let sourceURL else {
                resultBox.set(.failure(BridgeError.nativeFailure("photos.ui.pick returned no file for selected item \(index)")))
                semaphore.signal()
                return
            }

            do {
                let outputURL = outputDirectory.appendingPathComponent(self.outputFileName(for: typeIdentifier))
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: outputURL)
                resultBox.set(.success(outputURL))
            } catch {
                resultBox.set(.failure(error))
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + .milliseconds(timeoutMs)) == .timedOut {
            throw BridgeError.timeout(milliseconds: timeoutMs)
        }

        guard let outputURL = try resultBox.get()?.get() else {
            throw BridgeError.nativeFailure("photos.ui.pick export produced no result")
        }

        let bytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.doubleValue ?? 0
        let mimeType = UTType(typeIdentifier)?.preferredMIMEType
        let artifact = try context.artifactStore.register(url: outputURL, mimeType: mimeType)

        var object: [String: JSONValue] = [
            "path": .string(outputURL.path),
            "artifactID": .string(artifact.id),
            "mediaType": .string(mediaTypeString(for: typeIdentifier)),
            "uniformTypeIdentifier": .string(typeIdentifier),
            "bytes": .number(bytes),
        ]
        if let assetIdentifier = result.assetIdentifier {
            object["assetIdentifier"] = .string(assetIdentifier)
        }
        return .object(object)
    }

    private func preferredTypeIdentifier(for itemProvider: NSItemProvider, mediaType: String) -> String? {
        let identifiers = itemProvider.registeredTypeIdentifiers
        let preferredTypes: [UTType]
        switch mediaType {
        case "image", "photo":
            preferredTypes = [.image]
        case "video":
            preferredTypes = [.movie, .video]
        default:
            preferredTypes = [.image, .movie, .video]
        }

        for preferredType in preferredTypes {
            if let identifier = identifiers.first(where: { UTType($0)?.conforms(to: preferredType) == true }) {
                return identifier
            }
        }

        return identifiers.first
    }

    private func outputFileName(for typeIdentifier: String) -> String {
        let ext = UTType(typeIdentifier)?.preferredFilenameExtension ?? "bin"
        return "picked-\(UUID().uuidString).\(ext)"
    }

    private func mediaTypeString(for typeIdentifier: String) -> String {
        guard let type = UTType(typeIdentifier) else {
            return "unknown"
        }
        if type.conforms(to: .image) {
            return "image"
        }
        if type.conforms(to: .movie) || type.conforms(to: .video) {
            return "video"
        }
        return "unknown"
    }

    private func mapContact(_ contact: CNContact) -> JSONValue {
        .object([
            "identifier": .string(contact.identifier),
            "givenName": .string(availableString(CNContactGivenNameKey, contact: contact) { $0.givenName }),
            "familyName": .string(availableString(CNContactFamilyNameKey, contact: contact) { $0.familyName }),
            "organization": .string(availableString(CNContactOrganizationNameKey, contact: contact) { $0.organizationName }),
            "phones": .array(availablePhoneNumbers(contact)),
            "emails": .array(availableEmailAddresses(contact)),
        ])
    }

    private func availableString(_ key: String, contact: CNContact, read: (CNContact) -> String) -> String {
        contact.isKeyAvailable(key) ? read(contact) : ""
    }

    private func availablePhoneNumbers(_ contact: CNContact) -> [JSONValue] {
        guard contact.isKeyAvailable(CNContactPhoneNumbersKey) else {
            return []
        }
        return contact.phoneNumbers.map { .string($0.value.stringValue) }
    }

    private func availableEmailAddresses(_ contact: CNContact) -> [JSONValue] {
        guard contact.isKeyAvailable(CNContactEmailAddressesKey) else {
            return []
        }
        return contact.emailAddresses.map { .string(String($0.value)) }
    }
}

private struct PhotoPickerSelection: @unchecked Sendable {
    var assetIdentifier: String?
    var itemProvider: NSItemProvider

    init(result: PHPickerResult) {
        self.assetIdentifier = result.assetIdentifier
        self.itemProvider = result.itemProvider
    }
}

@MainActor private final class CalendarEventEditCoordinator: NSObject, @preconcurrency EKEventEditViewDelegate {
    private let onComplete: (EKEventEditViewAction, EKEvent?) -> Void

    init(onComplete: @escaping (EKEventEditViewAction, EKEvent?) -> Void) {
        self.onComplete = onComplete
    }

    func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
        let event = controller.event
        controller.dismiss(animated: true)
        onComplete(action, event)
    }
}

@MainActor private final class PhotoPickerCoordinator: NSObject, PHPickerViewControllerDelegate {
    private let onComplete: ([PHPickerResult]) -> Void

    init(onComplete: @escaping ([PHPickerResult]) -> Void) {
        self.onComplete = onComplete
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        onComplete(results)
    }
}

@MainActor private final class ContactSinglePickerCoordinator: NSObject, @preconcurrency CNContactPickerDelegate {
    private let onComplete: ([CNContact]) -> Void

    init(onComplete: @escaping ([CNContact]) -> Void) {
        self.onComplete = onComplete
    }

    func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        picker.dismiss(animated: true)
        onComplete([])
    }

    func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        picker.dismiss(animated: true)
        onComplete([contact])
    }
}

@MainActor private final class ContactMultiplePickerCoordinator: NSObject, @preconcurrency CNContactPickerDelegate {
    private let onComplete: ([CNContact]) -> Void

    init(onComplete: @escaping ([CNContact]) -> Void) {
        self.onComplete = onComplete
    }

    func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        picker.dismiss(animated: true)
        onComplete([])
    }

    func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
        picker.dismiss(animated: true)
        onComplete(contacts)
    }
}
#endif
