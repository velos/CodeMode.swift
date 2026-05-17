import Foundation

extension DefaultCapabilityRegistrationBuilder {
    func contactRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                descriptor: .init(
                    id: .contactsRead,
                    title: "Read contacts",
                    summary: "Read contacts with bounded fields.",
                    tags: ["contacts", "address-book", "people"],
                    example: "await apple.contacts.list({ limit: 25 })",
                    requiredPermissions: [.contacts],
                    optionalArguments: ["limit", "identifiers"],
                    argumentHints: [
                        "limit": "Max number of contacts, default 50.",
                        "identifiers": "Optional array of contact identifiers for targeted read.",
                    ],
                    resultSummary: "Array of contacts with identifier/name/organization/phones/emails."
                ),
                handler: { args, context in
                    try contacts.read(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .contactsSearch,
                    title: "Search contacts",
                    summary: "Search contacts by name.",
                    tags: ["contacts", "search", "people"],
                    example: "await apple.contacts.search({ query: 'Alex', limit: 10 })",
                    requiredPermissions: [.contacts],
                    requiredArguments: ["query"],
                    optionalArguments: ["limit"],
                    argumentHints: [
                        "query": "Name text to match.",
                        "limit": "Max number of contacts, default 20.",
                    ],
                    resultSummary: "Array of contact objects."
                ),
                handler: { args, context in
                    try contacts.search(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .contactsUIPick,
                    title: "Pick contacts with system UI",
                    summary: "Present system contact picker UI and return selected contacts without requiring full Contacts permission.",
                    tags: ["contacts", "people", "system-ui", "picker"],
                    example: "await apple.contacts.pick({ mode: 'single', displayedPropertyKeys: ['phoneNumbers', 'emailAddresses'] })",
                    optionalArguments: ["mode", "displayedPropertyKeys", "timeoutMs"],
                    argumentTypes: [
                        "mode": .string,
                        "displayedPropertyKeys": .array,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "mode": "single (default) or multiple.",
                        "displayedPropertyKeys": "Optional array of CNContact property key strings to display.",
                        "timeoutMs": "Optional timeout for waiting on user selection.",
                    ],
                    resultSummary: "Array of selected contacts with identifier/name/organization/phones/emails."
                ),
                handler: { args, context in
                    try systemUI.pickContacts(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .contactsUIPresentContact,
                    title: "Present contact card",
                    summary: "Present system contact card UI for a contact identifier.",
                    tags: ["contacts", "people", "system-ui", "details"],
                    example: "await apple.contacts.presentContact({ identifier: 'CONTACT_ID', allowsEditing: false })",
                    requiredPermissions: [.contacts],
                    requiredArguments: ["identifier"],
                    optionalArguments: ["allowsEditing", "allowsActions", "displayedPropertyKeys", "timeoutMs"],
                    argumentTypes: [
                        "identifier": .string,
                        "allowsEditing": .bool,
                        "allowsActions": .bool,
                        "displayedPropertyKeys": .array,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "identifier": "Contact identifier from apple.contacts.list/search/pick.",
                        "allowsEditing": "Whether the user can edit the contact; default false.",
                        "allowsActions": "Whether built-in actions like call/message are shown; default true.",
                        "displayedPropertyKeys": "Optional array of CNContact property key strings to display.",
                        "timeoutMs": "Optional timeout for waiting on dismissal.",
                    ],
                    resultSummary: "Object with action and contact when available."
                ),
                handler: { args, context in
                    try systemUI.presentContact(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .contactsUIPresentNewContact,
                    title: "Present new contact editor",
                    summary: "Present system UI for creating a new contact draft.",
                    tags: ["contacts", "people", "system-ui", "create"],
                    example: "await apple.contacts.presentNewContact({ givenName: 'Alex', familyName: 'Lee', emailAddresses: ['alex@example.com'] })",
                    requiredPermissions: [.contacts],
                    optionalArguments: ["givenName", "familyName", "organization", "phoneNumbers", "emailAddresses", "timeoutMs"],
                    argumentTypes: [
                        "givenName": .string,
                        "familyName": .string,
                        "organization": .string,
                        "phoneNumbers": .array,
                        "emailAddresses": .array,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "givenName": "Optional given name to prefill.",
                        "familyName": "Optional family name to prefill.",
                        "organization": "Optional organization to prefill.",
                        "phoneNumbers": "Optional array of phone number strings.",
                        "emailAddresses": "Optional array of email address strings.",
                        "timeoutMs": "Optional timeout for waiting on user completion.",
                    ],
                    resultSummary: "Object with action and contact when the user saves."
                ),
                handler: { args, context in
                    try systemUI.presentNewContact(arguments: args, context: context)
                }
            ),
        ]
    }


    func photoAndDocumentRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                descriptor: .init(
                    id: .photosRead,
                    title: "List photo library assets",
                    summary: "List photos/videos from the user photo library.",
                    tags: ["photos", "photo-library", "media"],
                    example: "await apple.photos.list({ mediaType: 'image', limit: 20 })",
                    requiredPermissions: [.photoLibrary],
                    optionalArguments: ["mediaType", "limit"],
                    argumentHints: [
                        "mediaType": "any (default), image, or video.",
                        "limit": "Max number of results, default 50.",
                    ],
                    resultSummary: "Array of assets with localIdentifier/mediaType/dimensions/date metadata."
                ),
                handler: { args, context in
                    try photos.read(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .photosExport,
                    title: "Export photo library asset",
                    summary: "Export a photo/video asset to sandbox file path and register artifact handle.",
                    tags: ["photos", "photo-library", "artifact"],
                    example: "await apple.photos.export({ localIdentifier: 'ABC/L0/001', outputPath: 'tmp:exported.jpg' })",
                    requiredPermissions: [.photoLibrary],
                    requiredArguments: ["localIdentifier"],
                    optionalArguments: ["outputPath"],
                    argumentHints: [
                        "localIdentifier": "PHAsset localIdentifier from photos.read result.",
                        "outputPath": "Optional sandbox output path; defaults to tmp-generated file.",
                    ],
                    resultSummary: "Object with path/artifactID/localIdentifier/mediaType/bytes."
                ),
                handler: { args, context in
                    try photos.export(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .photosUIPick,
                    title: "Pick photos with system UI",
                    summary: "Present system photo picker UI and export selected assets into the sandbox artifact store.",
                    tags: ["photos", "photo-library", "system-ui", "picker", "artifact"],
                    example: "await apple.photos.pick({ mediaType: 'image', limit: 3, outputDirectory: 'tmp:picks' })",
                    optionalArguments: ["mediaType", "limit", "outputDirectory", "timeoutMs"],
                    argumentTypes: [
                        "mediaType": .string,
                        "limit": .number,
                        "outputDirectory": .string,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "mediaType": "any (default), image/photo, or video.",
                        "limit": "Maximum number of selectable items; default 1.",
                        "outputDirectory": "Optional sandbox directory for exported picker files; defaults to tmp:.",
                        "timeoutMs": "Optional timeout for waiting on user selection/export.",
                    ],
                    resultSummary: "Array of selected assets with path/artifactID/mediaType/uniformTypeIdentifier/bytes."
                ),
                handler: { args, context in
                    try systemUI.pickPhotos(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .photosUIPresentLimitedLibraryPicker,
                    title: "Present limited Photos picker",
                    summary: "Present the Photos limited-library management UI so the user can update the app's selected photo set.",
                    tags: ["photos", "photo-library", "system-ui", "permission", "picker"],
                    example: "await apple.photos.presentLimitedLibraryPicker()",
                    optionalArguments: ["timeoutMs"],
                    argumentTypes: [
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "timeoutMs": "Optional timeout for waiting on the limited-library picker completion.",
                    ],
                    resultSummary: "Object with action/status and selectedIdentifiers when the limited selection changes."
                ),
                handler: { args, context in
                    try systemUI.presentLimitedPhotoLibraryPicker(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .documentsUIPick,
                    title: "Pick documents with system UI",
                    summary: "Present Files document picker UI and copy selected documents into the sandbox artifact store.",
                    tags: ["documents", "files", "system-ui", "picker", "artifact"],
                    example: "await apple.documents.pick({ contentTypes: ['public.item'], allowMultiple: true, outputDirectory: 'tmp:imports' })",
                    optionalArguments: ["contentTypes", "allowMultiple", "outputDirectory", "timeoutMs"],
                    argumentTypes: [
                        "contentTypes": .array,
                        "allowMultiple": .bool,
                        "outputDirectory": .string,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "contentTypes": "Optional array of UTType identifiers; defaults to public.item.",
                        "allowMultiple": "Whether multiple files may be selected; default false.",
                        "outputDirectory": "Optional sandbox directory for copied files; defaults to tmp:.",
                        "timeoutMs": "Optional timeout for waiting on user selection/copy.",
                    ],
                    resultSummary: "Array of selected documents with path/artifactID/filename/uniformTypeIdentifier/bytes."
                ),
                handler: { args, context in
                    try systemUI.pickDocuments(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .documentsUIExport,
                    title: "Export documents with system UI",
                    summary: "Present Files export UI to save one or more sandbox files to a user-selected destination.",
                    tags: ["documents", "files", "system-ui", "export", "save"],
                    example: "await apple.documents.export({ path: 'tmp:report.pdf' })",
                    optionalArguments: ["path", "paths", "asCopy", "timeoutMs"],
                    argumentTypes: [
                        "path": .string,
                        "paths": .array,
                        "asCopy": .bool,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "path": "Single sandbox file path to export.",
                        "paths": "Optional array of sandbox file paths to export.",
                        "asCopy": "Whether to export as a copy; default true.",
                        "timeoutMs": "Optional timeout for waiting on export completion.",
                    ],
                    resultSummary: "Object with action/count and destination URLs when the provider returns them."
                ),
                handler: { args, context in
                    try systemUI.exportDocuments(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .documentsUIOpenIn,
                    title: "Open document in another app",
                    summary: "Present the system Open In menu for a sandbox file.",
                    tags: ["documents", "files", "system-ui", "open-in", "handoff"],
                    example: "await apple.documents.openIn({ path: 'tmp:report.pdf' })",
                    requiredArguments: ["path"],
                    optionalArguments: ["name", "uti", "timeoutMs"],
                    argumentTypes: [
                        "path": .string,
                        "name": .string,
                        "uti": .string,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "path": "Sandbox file path to hand off.",
                        "name": "Optional display name for the document interaction controller.",
                        "uti": "Optional uniform type identifier override.",
                        "timeoutMs": "Optional timeout for waiting on the Open In menu dismissal.",
                    ],
                    resultSummary: "Object with action and application bundle identifier when the user hands off the file."
                ),
                handler: { args, context in
                    try systemUI.openDocument(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .documentsUIScan,
                    title: "Scan documents with system UI",
                    summary: "Present VisionKit document scanner UI and export scanned pages into the sandbox artifact store.",
                    tags: ["documents", "scan", "camera", "system-ui", "artifact"],
                    example: "await apple.documents.scan({ outputDirectory: 'tmp:scans' })",
                    optionalArguments: ["outputDirectory", "timeoutMs"],
                    argumentTypes: [
                        "outputDirectory": .string,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "outputDirectory": "Optional sandbox directory for scanned page images; defaults to tmp:.",
                        "timeoutMs": "Optional timeout for waiting on user scanning/export.",
                    ],
                    resultSummary: "Array of scanned page artifacts with path/artifactID/pageIndex/mediaType/bytes."
                ),
                handler: { args, context in
                    try systemUI.scanDocuments(arguments: args, context: context)
                }
            ),
        ]
    }
}
