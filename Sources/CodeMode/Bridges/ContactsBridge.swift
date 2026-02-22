import Foundation

#if canImport(Contacts)
import Contacts
#endif

public final class ContactsBridge: @unchecked Sendable {
    public init() {}

    public func read(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let status = resolvePermission(context: context)
        guard status == .granted else {
            throw BridgeError.permissionDenied(.contacts)
        }

        #if canImport(Contacts)
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]

        let limit = arguments.int("limit") ?? 50

        if let identifiers = arguments.array("identifiers")?.compactMap(\.stringValue), identifiers.isEmpty == false {
            let predicate = CNContact.predicateForContacts(withIdentifiers: identifiers)
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
            return .array(Array(contacts.prefix(max(1, limit))).map(mapContact))
        }

        var contacts: [JSONValue] = []
        let request = CNContactFetchRequest(keysToFetch: keys)
        try store.enumerateContacts(with: request) { contact, stop in
            contacts.append(self.mapContact(contact))
            if contacts.count >= max(1, limit) {
                stop.pointee = true
            }
        }

        return .array(contacts)
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("Contacts")
        #endif
    }

    public func search(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let status = resolvePermission(context: context)
        guard status == .granted else {
            throw BridgeError.permissionDenied(.contacts)
        }

        #if canImport(Contacts)
        guard let query = arguments.string("query"), query.isEmpty == false else {
            throw BridgeError.invalidArguments("contacts.search requires query")
        }

        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]

        let predicate = CNContact.predicateForContacts(matchingName: query)
        let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)

        let limit = arguments.int("limit") ?? 20
        return .array(Array(contacts.prefix(max(1, limit))).map(mapContact))
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("Contacts")
        #endif
    }

    private func resolvePermission(context: BridgeInvocationContext) -> PermissionStatus {
        let status = context.permissionBroker.status(for: .contacts)
        context.recordPermission(.contacts, status: status)
        if status == .notDetermined {
            let requested = context.permissionBroker.request(for: .contacts)
            context.recordPermission(.contacts, status: requested)
            return requested
        }

        return status
    }

    #if canImport(Contacts)
    private func mapContact(_ contact: CNContact) -> JSONValue {
        .object([
            "identifier": .string(contact.identifier),
            "givenName": .string(contact.givenName),
            "familyName": .string(contact.familyName),
            "organization": .string(contact.organizationName),
            "phones": .array(contact.phoneNumbers.map { .string($0.value.stringValue) }),
            "emails": .array(contact.emailAddresses.map { .string(String($0.value)) }),
        ])
    }
    #endif
}
