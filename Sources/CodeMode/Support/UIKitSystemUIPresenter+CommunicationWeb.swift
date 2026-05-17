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

extension UIKitSystemUIPresenter {
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

}
#endif
