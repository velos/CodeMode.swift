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
    static let defaultTimeoutMs = 300_000

    private let presentingViewControllerProvider: @Sendable () -> UIViewController?
    private let coordinatorLock = NSLock()
    private var retainedCoordinators: [UUID: AnyObject] = [:]

    public init(presentingViewController: @escaping @Sendable () -> UIViewController?) {
        self.presentingViewControllerProvider = presentingViewController
    }

    func runUIOperation<T: Sendable>(
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

    @MainActor func requirePresenter() throws -> UIViewController {
        guard let presenter = presentingViewControllerProvider() else {
            throw BridgeError.uiPresenterUnavailable
        }
        return topMostPresenter(from: presenter)
    }

    @MainActor func topMostPresenter(from root: UIViewController) -> UIViewController {
        var current = root
        while let presented = current.presentedViewController {
            current = presented
        }
        return current
    }

    func retainCoordinator(_ coordinator: AnyObject, token: UUID) {
        coordinatorLock.lock()
        retainedCoordinators[token] = coordinator
        coordinatorLock.unlock()
    }

    func releaseCoordinator(_ token: UUID) {
        coordinatorLock.lock()
        retainedCoordinators[token] = nil
        coordinatorLock.unlock()
    }

    func actionString(_ action: EKEventEditViewAction) -> String {
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

    @MainActor func alertActionStyle(_ styleName: String) -> UIAlertAction.Style {
        switch styleName {
        case "cancel":
            return .cancel
        case "destructive":
            return .destructive
        default:
            return .default
        }
    }

    @MainActor func keyboardType(_ name: String?) -> UIKeyboardType {
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

    @MainActor func printOutputType(from arguments: [String: JSONValue]) -> UIPrintInfo.OutputType {
        switch arguments.string("outputType")?.lowercased() {
        case "photo":
            return .photo
        case "grayscale":
            return .grayscale
        default:
            return .general
        }
    }

    @MainActor func popoverSourceRect(from arguments: [String: JSONValue], presenter: UIViewController) -> CGRect {
        if let sourceRect = arguments.object("sourceRect"),
           let x = sourceRect.double("x"),
           let y = sourceRect.double("y"),
           let width = sourceRect.double("width"),
           let height = sourceRect.double("height")
        {
            return CGRect(x: x, y: y, width: width, height: height)
        }

        return CGRect(
            x: presenter.view.bounds.midX,
            y: presenter.view.bounds.midY,
            width: 1,
            height: 1
        )
    }

    func photoAuthorizationStatusString(_ status: PHAuthorizationStatus) -> String {
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
    @MainActor func scannerRecognizedDataTypes(from arguments: [String: JSONValue]) -> Set<DataScannerViewController.RecognizedDataType> {
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

    @MainActor func scannerQualityLevel(from arguments: [String: JSONValue]) -> DataScannerViewController.QualityLevel {
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

    func exportPickerResult(
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

    func preferredTypeIdentifier(for itemProvider: NSItemProvider, mediaType: String) -> String? {
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

    func outputFileName(for typeIdentifier: String) -> String {
        let ext = UTType(typeIdentifier)?.preferredFilenameExtension ?? "bin"
        return "picked-\(UUID().uuidString).\(ext)"
    }

    func mediaTypeString(for typeIdentifier: String) -> String {
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

    func mapCalendar(_ calendar: EKCalendar) -> JSONValue {
        .object([
            "identifier": .string(calendar.calendarIdentifier),
            "title": .string(calendar.title),
            "type": .string(calendarTypeString(calendar.type)),
            "allowsContentModifications": .bool(calendar.allowsContentModifications),
        ])
    }

    func calendarTypeString(_ type: EKCalendarType) -> String {
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

    func mapContact(_ contact: CNContact) -> JSONValue {
        .object([
            "identifier": .string(contact.identifier),
            "givenName": .string(availableString(CNContactGivenNameKey, contact: contact) { $0.givenName }),
            "familyName": .string(availableString(CNContactFamilyNameKey, contact: contact) { $0.familyName }),
            "organization": .string(availableString(CNContactOrganizationNameKey, contact: contact) { $0.organizationName }),
            "phones": .array(availablePhoneNumbers(contact)),
            "emails": .array(availableEmailAddresses(contact)),
        ])
    }

    @MainActor func fetchContact(identifier: String, displayedPropertyKeys: [String]?) throws -> CNContact {
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

    func outputDirectoryURL(from arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> URL {
        let outputDirectory = arguments.string("outputDirectory") ?? "tmp:"
        let outputURL = try context.pathPolicy.resolve(path: outputDirectory)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        return outputURL
    }

    func documentContentTypes(from arguments: [String: JSONValue]) throws -> [UTType] {
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

    func copyExternalFile(
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

    func fileArtifactMetadata(
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

    func typeIdentifier(for url: URL) -> String? {
        if let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return resourceType.identifier
        }
        return UTType(filenameExtension: url.pathExtension)?.identifier
    }

    func uniqueOutputURL(in directory: URL, suggestedName: String) -> URL {
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

    func sandboxURLs(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> [URL] {
        var paths: [String] = []
        if let path = arguments.string("path") {
            paths.append(path)
        }
        paths.append(contentsOf: (arguments.array("paths") ?? []).compactMap(\.stringValue))
        return try paths.map { try context.pathPolicy.resolve(path: $0) }
    }

    func sandboxURL(path: String, context: BridgeInvocationContext) throws -> URL {
        try context.pathPolicy.resolve(path: path)
    }

    @MainActor func shareItems(from arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> [Any] {
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

    func stringArray(_ arguments: [String: JSONValue], key: String) -> [String]? {
        guard let values = arguments.array(key) else {
            return nil
        }
        return values.compactMap(\.stringValue)
    }

    #if os(iOS)
    @MainActor func cameraMediaTypes(for mediaType: String) -> [String] {
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

    @MainActor func cameraDevice(from arguments: [String: JSONValue]) -> UIImagePickerController.CameraDevice {
        switch arguments.string("cameraDevice")?.lowercased() {
        case "front":
            return .front
        default:
            return .rear
        }
    }

    @MainActor func cameraFlashMode(from arguments: [String: JSONValue]) -> UIImagePickerController.CameraFlashMode {
        switch arguments.string("flashMode")?.lowercased() {
        case "on":
            return .on
        case "off":
            return .off
        default:
            return .auto
        }
    }

    @MainActor func cameraVideoQuality(from arguments: [String: JSONValue]) -> UIImagePickerController.QualityType {
        switch arguments.string("videoQuality")?.lowercased() {
        case "medium":
            return .typeMedium
        case "low":
            return .typeLow
        case "640x480":
            return .type640x480
        case "iframe1280x720":
            return .typeIFrame1280x720
        case "iframe960x540":
            return .typeIFrame960x540
        default:
            return .typeHigh
        }
    }
    #endif

    #if canImport(MessageUI) && os(iOS)
    @MainActor func addMailAttachments(
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

    @MainActor func addMessageAttachments(
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

    func mailActionString(_ result: MFMailComposeResult) -> String {
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

    func messageActionString(_ result: MessageComposeResult) -> String {
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

    func availableString(_ key: String, contact: CNContact, read: (CNContact) -> String) -> String {
        contact.isKeyAvailable(key) ? read(contact) : ""
    }

    func availablePhoneNumbers(_ contact: CNContact) -> [JSONValue] {
        guard contact.isKeyAvailable(CNContactPhoneNumbersKey) else {
            return []
        }
        return contact.phoneNumbers.map { .string($0.value.stringValue) }
    }

    func availableEmailAddresses(_ contact: CNContact) -> [JSONValue] {
        guard contact.isKeyAvailable(CNContactEmailAddressesKey) else {
            return []
        }
        return contact.emailAddresses.map { .string(String($0.value)) }
    }
}
#endif
