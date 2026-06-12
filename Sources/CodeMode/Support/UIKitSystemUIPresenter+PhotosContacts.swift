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

}
#endif
