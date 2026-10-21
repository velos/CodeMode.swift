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
        let timeoutMs = arguments.int("timeoutMs") ?? Self.defaultTimeoutMs
        let token = UUID()

        return try runUIOperation(timeoutMs: timeoutMs, onTimeout: { self.releaseCoordinator(token) }) { complete in
            do {
                let presenter = try self.requirePresenter()
                let store = EKEventStore()
                let event = EKEvent(eventStore: store)
                event.title = arguments.string("title") ?? ""
                event.notes = arguments.string("notes")
                event.location = arguments.string("location")

                let startDate = CodeModeDate.parse(arguments.string("start")) ?? Date()
                event.startDate = startDate
                event.endDate = CodeModeDate.parse(arguments.string("end"))
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

}
#endif
