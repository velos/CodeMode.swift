import Foundation

#if canImport(UIKit) && (os(iOS) || os(visionOS))
@preconcurrency import AuthenticationServices
@preconcurrency import Contacts
@preconcurrency import ContactsUI
@preconcurrency import EventKit
@preconcurrency import EventKitUI
@preconcurrency import Photos
@preconcurrency import PhotosUI
@preconcurrency import QuickLook
@preconcurrency import SafariServices
@preconcurrency import UIKit
@preconcurrency import UniformTypeIdentifiers
#if canImport(MessageUI)
@preconcurrency import MessageUI
#endif
#if canImport(VisionKit)
@preconcurrency import VisionKit
#endif

public final class UIKitSystemUIPresenter: SystemUIPresenter, @unchecked Sendable {
    private static let defaultTimeoutMs = 300_000

    private let presentingViewControllerProvider: @Sendable () -> UIViewController?
    private let coordinatorLock = NSLock()
    private var retainedCoordinators: [UUID: AnyObject] = [:]

    public init(presentingViewController: @escaping @Sendable () -> UIViewController?) {
        self.presentingViewControllerProvider = presentingViewController
    }

    public func pickCalendar(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let selectionStyle = arguments.string("selectionStyle")?.lowercased() == "multiple"
            ? EKCalendarChooserSelectionStyle.multiple
            : EKCalendarChooserSelectionStyle.single
        let displayStyle = arguments.string("displayStyle")?.lowercased() == "all"
            ? EKCalendarChooserDisplayStyle.allCalendars
            : EKCalendarChooserDisplayStyle.writableCalendarsOnly
        let token = UUID()

        return try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                let presenter = try self.requirePresenter()
                let store = EKEventStore()
                let controller = EKCalendarChooser(
                    selectionStyle: selectionStyle,
                    displayStyle: displayStyle,
                    entityType: .event,
                    eventStore: store
                )
                controller.showsDoneButton = true
                controller.showsCancelButton = true

                let coordinator = CalendarChooserCoordinator { [weak self] calendars in
                    self?.releaseCoordinator(token)
                    complete(.success(.array(calendars.map { self?.mapCalendar($0) ?? .null })))
                }
                self.retainCoordinator(coordinator, token: token)
                controller.delegate = coordinator

                presenter.present(UINavigationController(rootViewController: controller), animated: true)
            } catch let error as BridgeError {
                complete(.failure(error))
            } catch {
                complete(.failure(.nativeFailure(error.localizedDescription)))
            }
        }
    }

    public func presentCalendarEvent(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let identifier = arguments.string("identifier") ?? ""
        let token = UUID()

        return try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                let presenter = try self.requirePresenter()
                let store = EKEventStore()
                guard let event = store.event(withIdentifier: identifier) else {
                    complete(.failure(.invalidArguments("calendar.ui.presentEvent could not find event identifier \(identifier)")))
                    return
                }

                let controller = EKEventViewController()
                controller.event = event
                controller.allowsEditing = arguments.bool("allowsEditing") ?? false
                controller.allowsCalendarPreview = arguments.bool("allowsCalendarPreview") ?? true

                let coordinator = CalendarEventViewCoordinator { [weak self] in
                    self?.releaseCoordinator(token)
                    complete(.success(.object(["action": .string("dismissed")])))
                }
                self.retainCoordinator(coordinator, token: token)
                controller.delegate = coordinator

                presenter.present(UINavigationController(rootViewController: controller), animated: true)
            } catch let error as BridgeError {
                complete(.failure(error))
            } catch {
                complete(.failure(.nativeFailure(error.localizedDescription)))
            }
        }
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

    public func presentLimitedPhotoLibraryPicker(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .limited else {
            return .object([
                "action": .string("notLimited"),
                "status": .string(photoAuthorizationStatusString(status)),
            ])
        }

        return try runUIOperation(timeoutMs: timeoutMs) { complete in
            do {
                let presenter = try self.requirePresenter()
                PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter) { identifiers in
                    complete(.success(.object([
                        "action": .string("completed"),
                        "status": .string("limited"),
                        "selectedIdentifiers": .array(identifiers.map(JSONValue.string)),
                    ])))
                }
            } catch let error as BridgeError {
                complete(.failure(error))
            } catch {
                complete(.failure(.nativeFailure(error.localizedDescription)))
            }
        }
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

    public func presentContact(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let identifier = arguments.string("identifier") ?? ""
        let displayedPropertyKeys = arguments.array("displayedPropertyKeys")?.compactMap(\.stringValue)
        let token = UUID()

        return try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                let presenter = try self.requirePresenter()
                let contact = try self.fetchContact(identifier: identifier, displayedPropertyKeys: displayedPropertyKeys)
                let controller = CNContactViewController(for: contact)
                controller.allowsEditing = arguments.bool("allowsEditing") ?? false
                controller.allowsActions = arguments.bool("allowsActions") ?? true
                controller.displayedPropertyKeys = displayedPropertyKeys

                let coordinator = ContactViewCoordinator { [weak self] contact in
                    var object: [String: JSONValue] = ["action": .string("dismissed")]
                    if let contact {
                        object["contact"] = self?.mapContact(contact) ?? .null
                    }
                    self?.releaseCoordinator(token)
                    complete(.success(.object(object)))
                }
                self.retainCoordinator(coordinator, token: token)
                controller.delegate = coordinator

                presenter.present(UINavigationController(rootViewController: controller), animated: true)
            } catch let error as BridgeError {
                complete(.failure(error))
            } catch {
                complete(.failure(.nativeFailure(error.localizedDescription)))
            }
        }
    }

    public func presentNewContact(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let token = UUID()

        return try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                let presenter = try self.requirePresenter()
                let contact = CNMutableContact()
                contact.givenName = arguments.string("givenName") ?? ""
                contact.familyName = arguments.string("familyName") ?? ""
                contact.organizationName = arguments.string("organization") ?? ""
                contact.phoneNumbers = (arguments.array("phoneNumbers") ?? []).compactMap(\.stringValue).map {
                    CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: $0))
                }
                contact.emailAddresses = (arguments.array("emailAddresses") ?? []).compactMap(\.stringValue).map {
                    CNLabeledValue(label: CNLabelHome, value: NSString(string: $0))
                }

                let controller = CNContactViewController(forNewContact: contact)
                let coordinator = ContactViewCoordinator { [weak self] contact in
                    var object: [String: JSONValue] = [
                        "action": .string(contact == nil ? "cancelled" : "saved"),
                    ]
                    if let contact {
                        object["contact"] = self?.mapContact(contact) ?? .null
                    }
                    self?.releaseCoordinator(token)
                    complete(.success(.object(object)))
                }
                self.retainCoordinator(coordinator, token: token)
                controller.delegate = coordinator

                presenter.present(UINavigationController(rootViewController: controller), animated: true)
            } catch let error as BridgeError {
                complete(.failure(error))
            } catch {
                complete(.failure(.nativeFailure(error.localizedDescription)))
            }
        }
    }

    public func pickDocuments(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let outputDirectory = try outputDirectoryURL(from: arguments, context: context)
        let types = try documentContentTypes(from: arguments)
        let allowMultiple = arguments.bool("allowMultiple") ?? false
        let token = UUID()

        let urls: [URL] = try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                let presenter = try self.requirePresenter()
                let controller = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
                controller.allowsMultipleSelection = allowMultiple

                let coordinator = DocumentPickerCoordinator { [weak self] urls in
                    self?.releaseCoordinator(token)
                    complete(.success(urls))
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

        return .array(try urls.enumerated().map { index, url in
            try context.checkCancellation()
            return try copyExternalFile(
                from: url,
                suggestedName: url.lastPathComponent.isEmpty ? "document-\(index)" : url.lastPathComponent,
                outputDirectory: outputDirectory,
                context: context
            )
        })
    }

    public func exportDocuments(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let urls = try sandboxURLs(arguments: arguments, context: context)
        let asCopy = arguments.bool("asCopy") ?? true
        let token = UUID()

        let destinationURLs: [URL] = try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                let presenter = try self.requirePresenter()
                let controller = UIDocumentPickerViewController(forExporting: urls, asCopy: asCopy)
                let coordinator = DocumentPickerCoordinator { [weak self] urls in
                    self?.releaseCoordinator(token)
                    complete(.success(urls))
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

        return .object([
            "action": .string(destinationURLs.isEmpty ? "cancelled" : "exported"),
            "count": .number(Double(urls.count)),
            "destinationURLs": .array(destinationURLs.map { .string($0.absoluteString) }),
        ])
    }

    public func openDocument(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let url = try sandboxURL(path: arguments.string("path") ?? "", context: context)
        let token = UUID()

        return try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                let presenter = try self.requirePresenter()
                let controller = UIDocumentInteractionController(url: url)
                controller.name = arguments.string("name")
                controller.uti = arguments.string("uti")

                let coordinator = DocumentInteractionCoordinator(presenter: presenter) { [weak self] result in
                    self?.releaseCoordinator(token)
                    complete(.success(result))
                }
                coordinator.controller = controller
                self.retainCoordinator(coordinator, token: token)
                controller.delegate = coordinator

                let sourceRect = CGRect(
                    x: presenter.view.bounds.midX,
                    y: presenter.view.bounds.midY,
                    width: 1,
                    height: 1
                )
                guard controller.presentOpenInMenu(from: sourceRect, in: presenter.view, animated: true) else {
                    self.releaseCoordinator(token)
                    complete(.failure(.unsupportedPlatform("documents.ui.openIn")))
                    return
                }
            } catch let error as BridgeError {
                complete(.failure(error))
            } catch {
                complete(.failure(.nativeFailure(error.localizedDescription)))
            }
        }
    }

    public func scanDocuments(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        #if os(iOS) && canImport(VisionKit)
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let outputDirectory = try outputDirectoryURL(from: arguments, context: context)
        let token = UUID()

        let urls: [URL] = try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                guard VNDocumentCameraViewController.isSupported else {
                    complete(.failure(.unsupportedPlatform("documents.ui.scan")))
                    return
                }

                let presenter = try self.requirePresenter()
                let controller = VNDocumentCameraViewController()
                let coordinator = DocumentScanCoordinator(outputDirectory: outputDirectory) { [weak self] result in
                    self?.releaseCoordinator(token)
                    complete(result)
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

        return .array(try urls.enumerated().map { index, url in
            try context.checkCancellation()
            return try fileArtifactMetadata(
                url: url,
                artifactName: url.lastPathComponent,
                context: context,
                extra: ["pageIndex": .number(Double(index))]
            )
        })
        #else
        _ = arguments
        _ = context
        throw BridgeError.unsupportedPlatform("documents.ui.scan")
        #endif
    }

    public func presentShareSheet(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let token = UUID()

        return try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                let presenter = try self.requirePresenter()
                let items = try self.shareItems(from: arguments, context: context)
                let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
                controller.excludedActivityTypes = (arguments.array("excludedActivityTypes") ?? [])
                    .compactMap(\.stringValue)
                    .map(UIActivity.ActivityType.init(rawValue:))
                if let subject = arguments.string("subject") {
                    controller.setValue(subject, forKey: "subject")
                }
                controller.popoverPresentationController?.sourceView = presenter.view
                controller.popoverPresentationController?.sourceRect = CGRect(
                    x: presenter.view.bounds.midX,
                    y: presenter.view.bounds.midY,
                    width: 1,
                    height: 1
                )

                self.retainCoordinator(controller, token: token)
                controller.completionWithItemsHandler = { [weak self] activityType, completed, _, error in
                    self?.releaseCoordinator(token)
                    if let error {
                        complete(.failure(.nativeFailure(error.localizedDescription)))
                        return
                    }
                    var object: [String: JSONValue] = [
                        "action": .string(completed ? "completed" : "cancelled"),
                        "completed": .bool(completed),
                    ]
                    if let activityType {
                        object["activityType"] = .string(activityType.rawValue)
                    }
                    complete(.success(.object(object)))
                }

                presenter.present(controller, animated: true)
            } catch let error as BridgeError {
                complete(.failure(error))
            } catch {
                complete(.failure(.nativeFailure(error.localizedDescription)))
            }
        }
    }

    public func previewQuickLook(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let urls = try sandboxURLs(arguments: arguments, context: context)
        let token = UUID()

        return try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                let presenter = try self.requirePresenter()
                let controller = QLPreviewController()
                let coordinator = QuickLookCoordinator(urls: urls) { [weak self] in
                    self?.releaseCoordinator(token)
                    complete(.success(.object([
                        "action": .string("dismissed"),
                        "count": .number(Double(urls.count)),
                    ])))
                }
                self.retainCoordinator(coordinator, token: token)
                controller.dataSource = coordinator
                controller.delegate = coordinator
                presenter.present(controller, animated: true)
            } catch let error as BridgeError {
                complete(.failure(error))
            } catch {
                complete(.failure(.nativeFailure(error.localizedDescription)))
            }
        }
    }

    public func captureCamera(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        #if os(iOS)
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let mediaType = arguments.string("mediaType")?.lowercased() ?? "any"
        let outputDirectory = try outputDirectoryURL(from: arguments, context: context)
        let token = UUID()

        let capture: CameraCaptureResult? = try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                    complete(.failure(.unsupportedPlatform("camera.ui.capture")))
                    return
                }

                let presenter = try self.requirePresenter()
                let controller = UIImagePickerController()
                controller.sourceType = .camera
                let mediaTypes = self.cameraMediaTypes(for: mediaType)
                guard mediaTypes.isEmpty == false else {
                    complete(.failure(.unsupportedPlatform("camera.ui.capture \(mediaType)")))
                    return
                }
                controller.mediaTypes = mediaTypes
                controller.allowsEditing = false

                let coordinator = CameraCaptureCoordinator(outputDirectory: outputDirectory) { [weak self] result in
                    self?.releaseCoordinator(token)
                    complete(result)
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

        guard let capture else {
            return .object(["action": .string("cancelled")])
        }
        return try fileArtifactMetadata(
            url: capture.url,
            artifactName: capture.url.lastPathComponent,
            context: context,
            mediaType: capture.mediaType,
            typeIdentifier: capture.typeIdentifier,
            extra: ["action": .string("captured")]
        )
        #else
        _ = arguments
        _ = context
        throw BridgeError.unsupportedPlatform("camera.ui.capture")
        #endif
    }

    public func scanData(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        #if canImport(VisionKit)
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let token = UUID()

        return try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                guard DataScannerViewController.isSupported, DataScannerViewController.isAvailable else {
                    complete(.failure(.unsupportedPlatform("camera.ui.scanData")))
                    return
                }

                let presenter = try self.requirePresenter()
                let controller = DataScannerViewController(
                    recognizedDataTypes: self.scannerRecognizedDataTypes(from: arguments),
                    qualityLevel: self.scannerQualityLevel(from: arguments),
                    recognizesMultipleItems: arguments.bool("recognizesMultipleItems") ?? false,
                    isHighFrameRateTrackingEnabled: true,
                    isPinchToZoomEnabled: true,
                    isGuidanceEnabled: true,
                    isHighlightingEnabled: true
                )
                let navigation = UINavigationController(rootViewController: controller)
                let coordinator = DataScannerCoordinator(
                    controller: controller,
                    navigationController: navigation,
                    returnsOnFirstResult: arguments.bool("returnsOnFirstResult") ?? true
                ) { [weak self] result in
                    self?.releaseCoordinator(token)
                    complete(result)
                }
                self.retainCoordinator(coordinator, token: token)
                controller.delegate = coordinator
                controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
                    barButtonSystemItem: .cancel,
                    target: coordinator,
                    action: #selector(DataScannerCoordinator.cancel)
                )

                presenter.present(navigation, animated: true) {
                    do {
                        try controller.startScanning()
                    } catch let error as DataScannerViewController.ScanningUnavailable {
                        navigation.dismiss(animated: true)
                        self.releaseCoordinator(token)
                        complete(.failure(.unsupportedPlatform("camera.ui.scanData \(error)")))
                    } catch {
                        navigation.dismiss(animated: true)
                        self.releaseCoordinator(token)
                        complete(.failure(.nativeFailure(error.localizedDescription)))
                    }
                }
            } catch let error as BridgeError {
                complete(.failure(error))
            } catch {
                complete(.failure(.nativeFailure(error.localizedDescription)))
            }
        }
        #else
        _ = arguments
        _ = context
        throw BridgeError.unsupportedPlatform("camera.ui.scanData")
        #endif
    }

    public func composeMail(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        #if canImport(MessageUI) && os(iOS)
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let token = UUID()

        return try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                guard MFMailComposeViewController.canSendMail() else {
                    complete(.failure(.unsupportedPlatform("mail.ui.compose")))
                    return
                }

                let presenter = try self.requirePresenter()
                let controller = MFMailComposeViewController()
                controller.setToRecipients(self.stringArray(arguments, key: "to"))
                controller.setCcRecipients(self.stringArray(arguments, key: "cc"))
                controller.setBccRecipients(self.stringArray(arguments, key: "bcc"))
                controller.setSubject(arguments.string("subject") ?? "")
                controller.setMessageBody(arguments.string("body") ?? "", isHTML: arguments.bool("isHTML") ?? false)
                try self.addMailAttachments(from: arguments, to: controller, context: context)

                let coordinator = MailComposeCoordinator { [weak self] result in
                    self?.releaseCoordinator(token)
                    complete(.success(.object(["action": .string(self?.mailActionString(result) ?? "unknown")])))
                }
                self.retainCoordinator(coordinator, token: token)
                controller.mailComposeDelegate = coordinator
                presenter.present(controller, animated: true)
            } catch let error as BridgeError {
                complete(.failure(error))
            } catch {
                complete(.failure(.nativeFailure(error.localizedDescription)))
            }
        }
        #else
        _ = arguments
        _ = context
        throw BridgeError.unsupportedPlatform("mail.ui.compose")
        #endif
    }

    public func composeMessage(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        #if canImport(MessageUI) && os(iOS)
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let token = UUID()

        return try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                guard MFMessageComposeViewController.canSendText() else {
                    complete(.failure(.unsupportedPlatform("messages.ui.compose")))
                    return
                }

                let presenter = try self.requirePresenter()
                let controller = MFMessageComposeViewController()
                controller.recipients = self.stringArray(arguments, key: "recipients")
                controller.body = arguments.string("body")
                if MFMessageComposeViewController.canSendSubject() {
                    controller.subject = arguments.string("subject")
                }
                try self.addMessageAttachments(from: arguments, to: controller, context: context)

                let coordinator = MessageComposeCoordinator { [weak self] result in
                    self?.releaseCoordinator(token)
                    complete(.success(.object(["action": .string(self?.messageActionString(result) ?? "unknown")])))
                }
                self.retainCoordinator(coordinator, token: token)
                controller.messageComposeDelegate = coordinator
                presenter.present(controller, animated: true)
            } catch let error as BridgeError {
                complete(.failure(error))
            } catch {
                complete(.failure(.nativeFailure(error.localizedDescription)))
            }
        }
        #else
        _ = arguments
        _ = context
        throw BridgeError.unsupportedPlatform("messages.ui.compose")
        #endif
    }

    public func presentPrint(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let urls = try sandboxURLs(arguments: arguments, context: context)
        let token = UUID()

        return try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                let presenter = try self.requirePresenter()
                let controller = UIPrintInteractionController.shared
                let printInfo = UIPrintInfo(dictionary: nil)
                printInfo.jobName = arguments.string("jobName") ?? urls.first?.lastPathComponent ?? "CodeMode Print Job"
                printInfo.outputType = self.printOutputType(from: arguments)
                controller.printInfo = printInfo
                controller.showsNumberOfCopies = arguments.bool("showsNumberOfCopies") ?? true
                if urls.count == 1 {
                    controller.printingItem = urls[0]
                    controller.printingItems = nil
                } else {
                    controller.printingItem = nil
                    controller.printingItems = urls
                }

                let coordinator = PrintCoordinator(parent: presenter)
                self.retainCoordinator(coordinator, token: token)
                controller.delegate = coordinator

                guard controller.present(animated: true, completionHandler: { [weak self] controller, completed, error in
                    controller.delegate = nil
                    self?.releaseCoordinator(token)
                    if let error {
                        complete(.failure(.nativeFailure(error.localizedDescription)))
                        return
                    }
                    complete(.success(.object([
                        "action": .string(completed ? "completed" : "cancelled"),
                        "completed": .bool(completed),
                    ])))
                }) else {
                    controller.delegate = nil
                    self.releaseCoordinator(token)
                    complete(.failure(.unsupportedPlatform("print.ui.present")))
                    return
                }
            } catch let error as BridgeError {
                complete(.failure(error))
            } catch {
                complete(.failure(.nativeFailure(error.localizedDescription)))
            }
        }
    }

    public func presentWeb(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let url = URL(string: arguments.string("url") ?? "")!
        let token = UUID()

        #if os(iOS)
        return try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                let presenter = try self.requirePresenter()
                let configuration = SFSafariViewController.Configuration()
                configuration.entersReaderIfAvailable = arguments.bool("entersReaderIfAvailable") ?? false
                let controller = SFSafariViewController(url: url, configuration: configuration)
                let coordinator = SafariCoordinator { [weak self] in
                    self?.releaseCoordinator(token)
                    complete(.success(.object(["action": .string("dismissed")])))
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
        #else
        return try runUIOperation(timeoutMs: timeoutMs) { complete in
            UIApplication.shared.open(url, options: [:]) { success in
                complete(.success(.object([
                    "action": .string(success ? "opened" : "failed"),
                    "opened": .bool(success),
                ])))
            }
        }
        #endif
    }

    public func authenticateWeb(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let url = URL(string: arguments.string("url") ?? "")!
        let callbackURLScheme = arguments.string("callbackURLScheme")
        let token = UUID()

        return try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                let presenter = try self.requirePresenter()
                guard let anchor = presenter.view.window ?? UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap(\.windows)
                    .first(where: { $0.isKeyWindow })
                else {
                    complete(.failure(.uiPresenterUnavailable))
                    return
                }

                let coordinator = WebAuthenticationCoordinator(anchor: anchor)
                let session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: callbackURLScheme
                ) { [weak self] callbackURL, error in
                    self?.releaseCoordinator(token)
                    if let callbackURL {
                        complete(.success(.object([
                            "action": .string("callback"),
                            "callbackURL": .string(callbackURL.absoluteString),
                        ])))
                        return
                    }

                    if let error = error as? ASWebAuthenticationSessionError,
                       error.code == .canceledLogin
                    {
                        complete(.success(.object(["action": .string("cancelled")])))
                        return
                    }

                    if let error {
                        complete(.failure(.nativeFailure(error.localizedDescription)))
                    } else {
                        complete(.success(.object(["action": .string("cancelled")])))
                    }
                }
                session.presentationContextProvider = coordinator
                session.prefersEphemeralWebBrowserSession = arguments.bool("prefersEphemeralSession") ?? false
                coordinator.session = session
                self.retainCoordinator(coordinator, token: token)

                guard session.start() else {
                    self.releaseCoordinator(token)
                    complete(.failure(.nativeFailure("auth.ui.webAuthenticate could not start authentication session")))
                    return
                }
            } catch let error as BridgeError {
                complete(.failure(error))
            } catch {
                complete(.failure(.nativeFailure(error.localizedDescription)))
            }
        }
    }

    public func presentAlert(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let token = UUID()

        return try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                let presenter = try self.requirePresenter()
                let preferredStyle = arguments.string("preferredStyle")?.lowercased()
                let controller = UIAlertController(
                    title: arguments.string("title"),
                    message: arguments.string("message"),
                    preferredStyle: preferredStyle == "actionsheet" ? .actionSheet : .alert
                )

                for (index, button) in (arguments.array("buttons") ?? []).enumerated() {
                    guard let object = button.objectValue else {
                        complete(.failure(.invalidArguments("ui.alert.present buttons must contain objects")))
                        return
                    }
                    let title = object.string("title") ?? ""
                    let id = object.string("id") ?? title
                    let styleName = object.string("style")?.lowercased() ?? "default"
                    let actionStyle = self.alertActionStyle(styleName)
                    controller.addAction(
                        UIAlertAction(title: title, style: actionStyle) { [weak self] _ in
                            self?.releaseCoordinator(token)
                            complete(.success(.object([
                                "action": .string("selected"),
                                "buttonID": .string(id),
                                "buttonTitle": .string(title),
                                "buttonIndex": .number(Double(index)),
                                "style": .string(styleName),
                            ])))
                        }
                    )
                }

                controller.popoverPresentationController?.sourceView = presenter.view
                controller.popoverPresentationController?.sourceRect = CGRect(
                    x: presenter.view.bounds.midX,
                    y: presenter.view.bounds.midY,
                    width: 1,
                    height: 1
                )

                self.retainCoordinator(controller, token: token)
                presenter.present(controller, animated: true)
            } catch let error as BridgeError {
                complete(.failure(error))
            } catch {
                complete(.failure(.nativeFailure(error.localizedDescription)))
            }
        }
    }

    public func presentPrompt(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let token = UUID()

        return try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                let presenter = try self.requirePresenter()
                let controller = UIAlertController(
                    title: arguments.string("title"),
                    message: arguments.string("message"),
                    preferredStyle: .alert
                )
                let fields = arguments.array("fields") ?? []

                for field in fields {
                    let object = field.objectValue ?? [:]
                    controller.addTextField { textField in
                        textField.placeholder = object.string("placeholder")
                        textField.text = object.string("text") ?? object.string("defaultValue")
                        textField.isSecureTextEntry = object.bool("secure") ?? false
                        textField.keyboardType = self.keyboardType(object.string("keyboardType"))
                    }
                }

                for (index, button) in (arguments.array("buttons") ?? []).enumerated() {
                    guard let object = button.objectValue else {
                        complete(.failure(.invalidArguments("ui.prompt.present buttons must contain objects")))
                        return
                    }
                    let title = object.string("title") ?? ""
                    let id = object.string("id") ?? title
                    let styleName = object.string("style")?.lowercased() ?? "default"
                    let actionStyle = self.alertActionStyle(styleName)
                    controller.addAction(
                        UIAlertAction(title: title, style: actionStyle) { [weak self, weak controller] _ in
                            var values: [String: JSONValue] = [:]
                            for (fieldIndex, field) in fields.enumerated() {
                                let fieldID = field.objectValue?.string("id") ?? "\(fieldIndex)"
                                values[fieldID] = .string(controller?.textFields?[fieldIndex].text ?? "")
                            }
                            self?.releaseCoordinator(token)
                            complete(.success(.object([
                                "action": .string("selected"),
                                "buttonID": .string(id),
                                "buttonTitle": .string(title),
                                "buttonIndex": .number(Double(index)),
                                "style": .string(styleName),
                                "values": .object(values),
                            ])))
                        }
                    )
                }

                self.retainCoordinator(controller, token: token)
                presenter.present(controller, animated: true)
            } catch let error as BridgeError {
                complete(.failure(error))
            } catch {
                complete(.failure(.nativeFailure(error.localizedDescription)))
            }
        }
    }

    public func openSettings(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            throw BridgeError.unsupportedPlatform("settings.ui.open")
        }

        return try runUIOperation(timeoutMs: timeoutMs) { complete in
            UIApplication.shared.open(url, options: [:]) { success in
                complete(.success(.object([
                    "action": .string(success ? "opened" : "failed"),
                    "opened": .bool(success),
                ])))
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

    @MainActor private func alertActionStyle(_ styleName: String) -> UIAlertAction.Style {
        switch styleName {
        case "cancel":
            return .cancel
        case "destructive":
            return .destructive
        default:
            return .default
        }
    }

    @MainActor private func keyboardType(_ name: String?) -> UIKeyboardType {
        switch name?.lowercased() {
        case "email":
            return .emailAddress
        case "number":
            return .numberPad
        case "phone":
            return .phonePad
        case "url":
            return .URL
        default:
            return .default
        }
    }

    @MainActor private func printOutputType(from arguments: [String: JSONValue]) -> UIPrintInfo.OutputType {
        switch arguments.string("outputType")?.lowercased() {
        case "photo":
            return .photo
        case "grayscale":
            return .grayscale
        default:
            return .general
        }
    }

    private func photoAuthorizationStatusString(_ status: PHAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "authorized"
        case .limited:
            return "limited"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "notDetermined"
        @unknown default:
            return "unknown"
        }
    }

    #if canImport(VisionKit)
    @MainActor private func scannerRecognizedDataTypes(from arguments: [String: JSONValue]) -> Set<DataScannerViewController.RecognizedDataType> {
        let languages = (arguments.array("languages") ?? []).compactMap(\.stringValue)
        let requested = (arguments.array("recognizedDataTypes") ?? []).compactMap { $0.stringValue?.lowercased() }
        let types = requested.isEmpty ? [arguments.string("mode")?.lowercased() ?? "any"] : requested

        var recognized: Set<DataScannerViewController.RecognizedDataType> = []
        if types.contains("any") || types.contains("text") {
            recognized.insert(.text(languages: languages))
        }
        if types.contains("any") || types.contains("barcode") {
            recognized.insert(.barcode())
        }
        if recognized.isEmpty {
            recognized = [.text(languages: languages), .barcode()]
        }
        return recognized
    }

    @MainActor private func scannerQualityLevel(from arguments: [String: JSONValue]) -> DataScannerViewController.QualityLevel {
        switch arguments.string("qualityLevel")?.lowercased() {
        case "fast":
            return .fast
        case "accurate":
            return .accurate
        default:
            return .balanced
        }
    }
    #endif

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

    private func mapCalendar(_ calendar: EKCalendar) -> JSONValue {
        .object([
            "identifier": .string(calendar.calendarIdentifier),
            "title": .string(calendar.title),
            "type": .string(calendarTypeString(calendar.type)),
            "allowsContentModifications": .bool(calendar.allowsContentModifications),
        ])
    }

    private func calendarTypeString(_ type: EKCalendarType) -> String {
        switch type {
        case .local:
            return "local"
        case .calDAV:
            return "calDAV"
        case .exchange:
            return "exchange"
        case .subscription:
            return "subscription"
        case .birthday:
            return "birthday"
        @unknown default:
            return "unknown"
        }
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

    @MainActor private func fetchContact(identifier: String, displayedPropertyKeys: [String]?) throws -> CNContact {
        let store = CNContactStore()
        var keys: [CNKeyDescriptor] = [
            CNContactViewController.descriptorForRequiredKeys(),
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
        keys.append(contentsOf: (displayedPropertyKeys ?? []).map { $0 as CNKeyDescriptor })
        return try store.unifiedContact(withIdentifier: identifier, keysToFetch: keys)
    }

    private func outputDirectoryURL(from arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> URL {
        let outputDirectory = arguments.string("outputDirectory") ?? "tmp:"
        let outputURL = try context.pathPolicy.resolve(path: outputDirectory)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        return outputURL
    }

    private func documentContentTypes(from arguments: [String: JSONValue]) throws -> [UTType] {
        guard let identifiers = arguments.array("contentTypes")?.compactMap(\.stringValue), identifiers.isEmpty == false else {
            return [.item]
        }

        return try identifiers.map { identifier in
            guard let type = UTType(identifier) else {
                throw BridgeError.invalidArguments("documents.ui.pick contentTypes contains unknown UTType \(identifier)")
            }
            return type
        }
    }

    private func copyExternalFile(
        from sourceURL: URL,
        suggestedName: String,
        outputDirectory: URL,
        context: BridgeInvocationContext
    ) throws -> JSONValue {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let outputURL = uniqueOutputURL(in: outputDirectory, suggestedName: suggestedName)
        try FileManager.default.copyItem(at: sourceURL, to: outputURL)
        return try fileArtifactMetadata(
            url: outputURL,
            artifactName: outputURL.lastPathComponent,
            context: context,
            typeIdentifier: typeIdentifier(for: outputURL)
        )
    }

    private func fileArtifactMetadata(
        url: URL,
        artifactName: String,
        context: BridgeInvocationContext,
        mediaType: String? = nil,
        typeIdentifier uniformTypeIdentifier: String? = nil,
        extra: [String: JSONValue] = [:]
    ) throws -> JSONValue {
        let resolvedTypeIdentifier = uniformTypeIdentifier ?? typeIdentifier(for: url)
        let mimeType = resolvedTypeIdentifier.flatMap { UTType($0)?.preferredMIMEType }
        let artifact = try context.artifactStore.register(url: url, mimeType: mimeType)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.doubleValue ?? 0

        var object: [String: JSONValue] = [
            "path": .string(url.path),
            "artifactID": .string(artifact.id),
            "filename": .string(artifactName),
            "bytes": .number(bytes),
        ]
        if let resolvedTypeIdentifier {
            object["uniformTypeIdentifier"] = .string(resolvedTypeIdentifier)
        }
        if let mimeType {
            object["mimeType"] = .string(mimeType)
        }
        if let mediaType {
            object["mediaType"] = .string(mediaType)
        } else if let resolvedTypeIdentifier {
            object["mediaType"] = .string(mediaTypeString(for: resolvedTypeIdentifier))
        }
        for (key, value) in extra {
            object[key] = value
        }
        return .object(object)
    }

    private func typeIdentifier(for url: URL) -> String? {
        if let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return resourceType.identifier
        }
        return UTType(filenameExtension: url.pathExtension)?.identifier
    }

    private func uniqueOutputURL(in directory: URL, suggestedName: String) -> URL {
        let cleanName = suggestedName.isEmpty ? "artifact-\(UUID().uuidString)" : suggestedName
        let initial = directory.appendingPathComponent(cleanName)
        guard FileManager.default.fileExists(atPath: initial.path) else {
            return initial
        }

        let base = initial.deletingPathExtension().lastPathComponent
        let ext = initial.pathExtension
        let name = ext.isEmpty ? "\(base)-\(UUID().uuidString)" : "\(base)-\(UUID().uuidString).\(ext)"
        return directory.appendingPathComponent(name)
    }

    private func sandboxURLs(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> [URL] {
        var paths: [String] = []
        if let path = arguments.string("path") {
            paths.append(path)
        }
        paths.append(contentsOf: (arguments.array("paths") ?? []).compactMap(\.stringValue))
        return try paths.map { try context.pathPolicy.resolve(path: $0) }
    }

    private func sandboxURL(path: String, context: BridgeInvocationContext) throws -> URL {
        try context.pathPolicy.resolve(path: path)
    }

    @MainActor private func shareItems(from arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> [Any] {
        var items: [Any] = []
        if let text = arguments.string("text") {
            items.append(text)
        }
        if let urlString = arguments.string("url"), let url = URL(string: urlString) {
            items.append(url)
        }
        if let path = arguments.string("path") {
            items.append(try context.pathPolicy.resolve(path: path))
        }
        for value in arguments.array("paths") ?? [] {
            if let path = value.stringValue {
                items.append(try context.pathPolicy.resolve(path: path))
            }
        }
        return items
    }

    private func stringArray(_ arguments: [String: JSONValue], key: String) -> [String]? {
        guard let values = arguments.array(key) else {
            return nil
        }
        return values.compactMap(\.stringValue)
    }

    #if os(iOS)
    @MainActor private func cameraMediaTypes(for mediaType: String) -> [String] {
        let available = UIImagePickerController.availableMediaTypes(for: .camera) ?? [UTType.image.identifier]
        switch mediaType {
        case "image", "photo":
            return available.filter { UTType($0)?.conforms(to: .image) == true }
        case "video":
            return available.filter { UTType($0)?.conforms(to: .movie) == true || UTType($0)?.conforms(to: .video) == true }
        default:
            return available
        }
    }
    #endif

    #if canImport(MessageUI) && os(iOS)
    @MainActor private func addMailAttachments(
        from arguments: [String: JSONValue],
        to controller: MFMailComposeViewController,
        context: BridgeInvocationContext
    ) throws {
        for attachment in arguments.array("attachments") ?? [] {
            guard let object = attachment.objectValue, let path = object.string("path") else {
                continue
            }
            let url = try context.pathPolicy.resolve(path: path)
            let data = try Data(contentsOf: url)
            let mimeType = object.string("mimeType") ?? typeIdentifier(for: url).flatMap { UTType($0)?.preferredMIMEType } ?? "application/octet-stream"
            let filename = object.string("filename") ?? url.lastPathComponent
            controller.addAttachmentData(data, mimeType: mimeType, fileName: filename)
        }
    }

    @MainActor private func addMessageAttachments(
        from arguments: [String: JSONValue],
        to controller: MFMessageComposeViewController,
        context: BridgeInvocationContext
    ) throws {
        for attachment in arguments.array("attachments") ?? [] {
            guard let object = attachment.objectValue, let path = object.string("path") else {
                continue
            }
            let url = try context.pathPolicy.resolve(path: path)
            let filename = object.string("filename")
            if controller.addAttachmentURL(url, withAlternateFilename: filename) == false {
                throw BridgeError.nativeFailure("messages.ui.compose could not attach \(path)")
            }
        }
    }

    private func mailActionString(_ result: MFMailComposeResult) -> String {
        switch result {
        case .cancelled:
            return "cancelled"
        case .saved:
            return "saved"
        case .sent:
            return "sent"
        case .failed:
            return "failed"
        @unknown default:
            return "unknown"
        }
    }

    private func messageActionString(_ result: MessageComposeResult) -> String {
        switch result {
        case .cancelled:
            return "cancelled"
        case .sent:
            return "sent"
        case .failed:
            return "failed"
        @unknown default:
            return "unknown"
        }
    }
    #endif

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
#endif
