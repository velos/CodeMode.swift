import Foundation

#if canImport(UIKit) && (os(iOS) || os(visionOS))
@preconcurrency import AuthenticationServices
@preconcurrency import Contacts
@preconcurrency import ContactsUI
@preconcurrency import EventKit
@preconcurrency import EventKitUI
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

struct PhotoPickerSelection: @unchecked Sendable {
    var assetIdentifier: String?
    var itemProvider: NSItemProvider

    init(result: PHPickerResult) {
        self.assetIdentifier = result.assetIdentifier
        self.itemProvider = result.itemProvider
    }
}

@MainActor final class CalendarEventEditCoordinator: NSObject, @preconcurrency EKEventEditViewDelegate {
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

@MainActor final class CalendarChooserCoordinator: NSObject, @preconcurrency EKCalendarChooserDelegate {
    private let onComplete: (Set<EKCalendar>) -> Void

    init(onComplete: @escaping (Set<EKCalendar>) -> Void) {
        self.onComplete = onComplete
    }

    func calendarChooserDidFinish(_ calendarChooser: EKCalendarChooser) {
        let calendars = calendarChooser.selectedCalendars
        calendarChooser.dismiss(animated: true)
        onComplete(calendars)
    }

    func calendarChooserDidCancel(_ calendarChooser: EKCalendarChooser) {
        calendarChooser.dismiss(animated: true)
        onComplete([])
    }
}

@MainActor final class CalendarEventViewCoordinator: NSObject, @preconcurrency EKEventViewDelegate {
    private let onComplete: () -> Void

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) {
        _ = action
        controller.dismiss(animated: true)
        onComplete()
    }
}

@MainActor final class PhotoPickerCoordinator: NSObject, PHPickerViewControllerDelegate {
    private let onComplete: ([PHPickerResult]) -> Void

    init(onComplete: @escaping ([PHPickerResult]) -> Void) {
        self.onComplete = onComplete
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        onComplete(results)
    }
}

@MainActor final class ContactSinglePickerCoordinator: NSObject, @preconcurrency CNContactPickerDelegate {
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

@MainActor final class ContactMultiplePickerCoordinator: NSObject, @preconcurrency CNContactPickerDelegate {
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

@MainActor final class ContactViewCoordinator: NSObject, @preconcurrency CNContactViewControllerDelegate {
    private let onComplete: (CNContact?) -> Void

    init(onComplete: @escaping (CNContact?) -> Void) {
        self.onComplete = onComplete
    }

    func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        viewController.dismiss(animated: true)
        onComplete(contact)
    }
}

@MainActor final class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
    private let onComplete: ([URL]) -> Void

    init(onComplete: @escaping ([URL]) -> Void) {
        self.onComplete = onComplete
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true)
        onComplete([])
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        controller.dismiss(animated: true)
        onComplete(urls)
    }
}

@MainActor final class DocumentInteractionCoordinator: NSObject, @preconcurrency UIDocumentInteractionControllerDelegate {
    weak var presenter: UIViewController?
    var controller: UIDocumentInteractionController?
    private var application: String?
    private var didSend = false
    private let onComplete: (JSONValue) -> Void

    init(presenter: UIViewController, onComplete: @escaping (JSONValue) -> Void) {
        self.presenter = presenter
        self.onComplete = onComplete
    }

    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        _ = controller
        return presenter ?? UIViewController()
    }

    func documentInteractionController(
        _ controller: UIDocumentInteractionController,
        willBeginSendingToApplication application: String?
    ) {
        _ = controller
        self.application = application
        didSend = true
    }

    func documentInteractionController(
        _ controller: UIDocumentInteractionController,
        didEndSendingToApplication application: String?
    ) {
        _ = controller
        self.application = application ?? self.application
        didSend = true
    }

    func documentInteractionControllerDidDismissOpenInMenu(_ controller: UIDocumentInteractionController) {
        _ = controller
        var object: [String: JSONValue] = [
            "action": .string(didSend ? "sent" : "dismissed"),
        ]
        if let application {
            object["application"] = .string(application)
        }
        onComplete(.object(object))
    }
}

@MainActor final class PrintCoordinator: NSObject, UIPrintInteractionControllerDelegate {
    weak var parent: UIViewController?

    init(parent: UIViewController) {
        self.parent = parent
    }

    func printInteractionControllerParentViewController(_ printInteractionController: UIPrintInteractionController) -> UIViewController? {
        _ = printInteractionController
        return parent
    }
}

@MainActor final class QuickLookCoordinator: NSObject, QLPreviewControllerDataSource, @preconcurrency QLPreviewControllerDelegate {
    private let urls: [URL]
    private let onComplete: () -> Void

    init(urls: [URL], onComplete: @escaping () -> Void) {
        self.urls = urls
        self.onComplete = onComplete
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        _ = controller
        return urls.count
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        _ = controller
        return urls[index] as NSURL
    }

    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        _ = controller
        onComplete()
    }
}

#if canImport(VisionKit)
@MainActor final class DataScannerCoordinator: NSObject, DataScannerViewControllerDelegate {
    private weak var controller: DataScannerViewController?
    private weak var navigationController: UINavigationController?
    private let returnsOnFirstResult: Bool
    private let onComplete: (Result<JSONValue, BridgeError>) -> Void
    private var completed = false
    private var currentItems: [RecognizedItem] = []

    init(
        controller: DataScannerViewController,
        navigationController: UINavigationController,
        returnsOnFirstResult: Bool,
        onComplete: @escaping (Result<JSONValue, BridgeError>) -> Void
    ) {
        self.controller = controller
        self.navigationController = navigationController
        self.returnsOnFirstResult = returnsOnFirstResult
        self.onComplete = onComplete
    }

    @objc func cancel() {
        complete(action: "cancelled", items: currentItems)
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
        _ = dataScanner
        complete(action: "selected", items: [item])
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        _ = dataScanner
        currentItems = allItems
        if returnsOnFirstResult, (allItems.isEmpty == false || addedItems.isEmpty == false) {
            complete(action: "recognized", items: allItems.isEmpty ? addedItems : allItems)
        }
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        _ = dataScanner
        _ = updatedItems
        currentItems = allItems
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        _ = dataScanner
        _ = removedItems
        currentItems = allItems
    }

    func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
        _ = dataScanner
        complete(.failure(.unsupportedPlatform("camera.ui.scanData \(error)")))
    }

    private func complete(action: String, items: [RecognizedItem]) {
        complete(.success(.object([
            "action": .string(action),
            "items": .array(items.map(mapRecognizedItem)),
        ])))
    }

    private func complete(_ result: Result<JSONValue, BridgeError>) {
        guard completed == false else {
            return
        }
        completed = true
        controller?.stopScanning()
        navigationController?.dismiss(animated: true)
        onComplete(result)
    }
}

@MainActor private func mapRecognizedItem(_ item: RecognizedItem) -> JSONValue {
    var object: [String: JSONValue] = [
        "id": .string(item.id.uuidString),
        "bounds": mapRecognizedBounds(item.bounds),
    ]

    switch item {
    case .text(let text):
        object["type"] = .string("text")
        object["transcript"] = .string(text.transcript)
    case .barcode(let barcode):
        object["type"] = .string("barcode")
        object["payload"] = .string(barcode.payloadStringValue ?? "")
        object["symbology"] = .string(String(describing: barcode.observation.symbology))
    @unknown default:
        object["type"] = .string("unknown")
    }

    return .object(object)
}

@MainActor private func mapRecognizedBounds(_ bounds: RecognizedItem.Bounds) -> JSONValue {
    .object([
        "topLeft": mapPoint(bounds.topLeft),
        "topRight": mapPoint(bounds.topRight),
        "bottomRight": mapPoint(bounds.bottomRight),
        "bottomLeft": mapPoint(bounds.bottomLeft),
    ])
}

@MainActor private func mapPoint(_ point: CGPoint) -> JSONValue {
    .object([
        "x": .number(Double(point.x)),
        "y": .number(Double(point.y)),
    ])
}
#endif

#if os(iOS)
struct CameraCaptureResult: Sendable {
    var url: URL
    var mediaType: String
    var typeIdentifier: String
}

@MainActor final class CameraCaptureCoordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let outputDirectory: URL
    private let onComplete: (Result<CameraCaptureResult?, BridgeError>) -> Void

    init(outputDirectory: URL, onComplete: @escaping (Result<CameraCaptureResult?, BridgeError>) -> Void) {
        self.outputDirectory = outputDirectory
        self.onComplete = onComplete
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        onComplete(.success(nil))
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        do {
            let result = try exportCapture(info: info)
            picker.dismiss(animated: true)
            onComplete(.success(result))
        } catch let error as BridgeError {
            picker.dismiss(animated: true)
            onComplete(.failure(error))
        } catch {
            picker.dismiss(animated: true)
            onComplete(.failure(.nativeFailure(error.localizedDescription)))
        }
    }

    private func exportCapture(info: [UIImagePickerController.InfoKey: Any]) throws -> CameraCaptureResult {
        let mediaType = (info[.mediaType] as? String) ?? UTType.image.identifier
        if UTType(mediaType)?.conforms(to: .movie) == true || UTType(mediaType)?.conforms(to: .video) == true {
            guard let sourceURL = info[.mediaURL] as? URL else {
                throw BridgeError.nativeFailure("camera.ui.capture returned no video URL")
            }
            let outputURL = outputDirectory.appendingPathComponent("capture-\(UUID().uuidString).\(sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension)")
            try FileManager.default.copyItem(at: sourceURL, to: outputURL)
            return CameraCaptureResult(url: outputURL, mediaType: "video", typeIdentifier: mediaType)
        }

        if let imageURL = info[.imageURL] as? URL {
            let outputURL = outputDirectory.appendingPathComponent("capture-\(UUID().uuidString).\(imageURL.pathExtension.isEmpty ? "jpg" : imageURL.pathExtension)")
            try FileManager.default.copyItem(at: imageURL, to: outputURL)
            return CameraCaptureResult(url: outputURL, mediaType: "image", typeIdentifier: UTType.jpeg.identifier)
        }

        guard let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage),
              let data = image.jpegData(compressionQuality: 0.92)
        else {
            throw BridgeError.nativeFailure("camera.ui.capture returned no image")
        }

        let outputURL = outputDirectory.appendingPathComponent("capture-\(UUID().uuidString).jpg")
        try data.write(to: outputURL, options: .atomic)
        return CameraCaptureResult(url: outputURL, mediaType: "image", typeIdentifier: UTType.jpeg.identifier)
    }
}
#endif

#if os(iOS) && canImport(VisionKit)
@MainActor final class DocumentScanCoordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
    private let outputDirectory: URL
    private let onComplete: (Result<[URL], BridgeError>) -> Void

    init(outputDirectory: URL, onComplete: @escaping (Result<[URL], BridgeError>) -> Void) {
        self.outputDirectory = outputDirectory
        self.onComplete = onComplete
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
        onComplete(.success([]))
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
        controller.dismiss(animated: true)
        onComplete(.failure(.nativeFailure(error.localizedDescription)))
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        do {
            var urls: [URL] = []
            for index in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: index)
                guard let data = image.jpegData(compressionQuality: 0.92) else {
                    throw BridgeError.nativeFailure("documents.ui.scan could not encode page \(index)")
                }
                let url = outputDirectory.appendingPathComponent("scan-\(UUID().uuidString)-page-\(index + 1).jpg")
                try data.write(to: url, options: .atomic)
                urls.append(url)
            }
            controller.dismiss(animated: true)
            onComplete(.success(urls))
        } catch let error as BridgeError {
            controller.dismiss(animated: true)
            onComplete(.failure(error))
        } catch {
            controller.dismiss(animated: true)
            onComplete(.failure(.nativeFailure(error.localizedDescription)))
        }
    }
}
#endif

#if canImport(MessageUI) && os(iOS)
@MainActor final class MailComposeCoordinator: NSObject, @preconcurrency MFMailComposeViewControllerDelegate {
    private let onComplete: (MFMailComposeResult) -> Void

    init(onComplete: @escaping (MFMailComposeResult) -> Void) {
        self.onComplete = onComplete
    }

    func mailComposeController(
        _ controller: MFMailComposeViewController,
        didFinishWith result: MFMailComposeResult,
        error: (any Error)?
    ) {
        _ = error
        controller.dismiss(animated: true)
        onComplete(result)
    }
}

@MainActor final class MessageComposeCoordinator: NSObject, @preconcurrency MFMessageComposeViewControllerDelegate {
    private let onComplete: (MessageComposeResult) -> Void

    init(onComplete: @escaping (MessageComposeResult) -> Void) {
        self.onComplete = onComplete
    }

    func messageComposeViewController(
        _ controller: MFMessageComposeViewController,
        didFinishWith result: MessageComposeResult
    ) {
        controller.dismiss(animated: true)
        onComplete(result)
    }
}
#endif

#if os(iOS)
@MainActor final class SafariCoordinator: NSObject, @preconcurrency SFSafariViewControllerDelegate {
    private let onComplete: () -> Void

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        _ = controller
        onComplete()
    }
}
#endif

@MainActor final class WebAuthenticationCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor
    var session: ASWebAuthenticationSession?

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        _ = session
        return anchor
    }
}
#endif
