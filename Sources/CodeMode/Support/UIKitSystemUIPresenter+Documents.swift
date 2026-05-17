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

}
#endif
