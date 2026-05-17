import Foundation

public enum DefaultCapabilityLoader {
    public static func loadAllRegistrations(
        fileSystem: any CodeModeFileSystem = LocalCodeModeFileSystem()
    ) -> [CapabilityRegistration] {
        DefaultCapabilityRegistrationBuilder(fileSystem: fileSystem).loadAll()
    }
}

private struct DefaultCapabilityRegistrationBuilder {
    private let fs: FileSystemBridge
    private let network: NetworkBridge
    private let keychain: KeychainBridge
    private let location: LocationBridge
    private let weather: WeatherBridge
    private let eventKit: EventKitBridge
    private let contacts: ContactsBridge
    private let photos: PhotosBridge
    private let vision: VisionBridge
    private let notifications: NotificationsBridge
    private let alarm: AlarmBridge
    private let health: HealthBridge
    private let home: HomeBridge
    private let media: MediaBridge
    private let systemUI: SystemUIBridge

    init(fileSystem: any CodeModeFileSystem) {
        self.fs = FileSystemBridge(fileSystem: fileSystem)
        self.network = NetworkBridge()
        self.keychain = KeychainBridge()
        self.location = LocationBridge()
        self.weather = WeatherBridge()
        self.eventKit = EventKitBridge()
        self.contacts = ContactsBridge()
        self.photos = PhotosBridge()
        self.vision = VisionBridge()
        self.notifications = NotificationsBridge()
        self.alarm = AlarmBridge()
        self.health = HealthBridge()
        self.home = HomeBridge()
        self.media = MediaBridge()
        self.systemUI = SystemUIBridge()
    }

    func loadAll() -> [CapabilityRegistration] {
        [
            networkRegistrations(),
            keychainRegistrations(),
            locationAndWeatherRegistrations(),
            calendarAndReminderRegistrations(),
            contactRegistrations(),
            photoAndDocumentRegistrations(),
            interactionUIRegistrations(),
            visionRegistrations(),
            notificationRegistrations(),
            alarmRegistrations(),
            healthRegistrations(),
            homeRegistrations(),
            mediaRegistrations(),
            filesystemRegistrations(),
        ].flatMap { $0 }
    }

    private func networkRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                descriptor: .init(
                    id: .networkFetch,
                    title: "Fetch HTTP resource",
                    summary: "Perform HTTP(S) requests through URLSession via a fetch-compatible API.",
                    tags: ["network", "http", "fetch"],
                    example: "await fetch('https://api.example.com/data').then(r => r.json())",
                    requiredArguments: ["url"],
                    optionalArguments: ["options.method", "options.headers", "options.body"],
                    argumentHints: [
                        "url": "Absolute HTTP(S) URL string.",
                        "options.method": "HTTP method; defaults to GET.",
                        "options.headers": "Object of header key/value string pairs.",
                        "options.body": "UTF-8 request body string.",
                    ],
                    resultSummary: "Object with ok/status/statusText/headers/bodyText."
                ),
                handler: { args, context in
                    try network.fetch(arguments: args, context: context)
                }
            ),
        ]
    }

    private func keychainRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                descriptor: .init(
                    id: .keychainRead,
                    title: "Read Keychain value",
                    summary: "Read a string value from app-scoped Keychain storage.",
                    tags: ["security", "token", "keychain"],
                    example: "await apple.keychain.get('auth_token')",
                    requiredArguments: ["key"],
                    argumentHints: [
                        "key": "Logical key for this secret value.",
                    ],
                    resultSummary: "Object { key, value } or null when the key does not exist."
                ),
                handler: { args, _ in
                    try keychain.read(arguments: args)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .keychainWrite,
                    title: "Write Keychain value",
                    summary: "Store or update a string value in app-scoped Keychain storage.",
                    tags: ["security", "token", "keychain"],
                    example: "await apple.keychain.set('auth_token', token)",
                    requiredArguments: ["key"],
                    optionalArguments: ["value"],
                    argumentHints: [
                        "key": "Logical key for this secret value.",
                        "value": "Secret string value. Defaults to empty string when omitted.",
                    ],
                    resultSummary: "Object { key, written: true }."
                ),
                handler: { args, _ in
                    try keychain.write(arguments: args)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .keychainDelete,
                    title: "Delete Keychain value",
                    summary: "Delete an app-scoped Keychain value.",
                    tags: ["security", "token", "keychain"],
                    example: "await apple.keychain.delete('auth_token')",
                    requiredArguments: ["key"],
                    argumentHints: [
                        "key": "Logical key for value removal.",
                    ],
                    resultSummary: "Object { key, deleted: true }."
                ),
                handler: { args, _ in
                    try keychain.delete(arguments: args)
                }
            ),
        ]
    }

    private func locationAndWeatherRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                descriptor: .init(
                    id: .locationRead,
                    title: "Read location state or coordinates",
                    summary: "Read location permission status or current coordinates.",
                    tags: ["location", "permission", "geospatial"],
                    example: "await apple.location.getCurrentPosition()",
                    requiredPermissions: [],
                    optionalArguments: ["mode"],
                    argumentHints: [
                        "mode": "permissionStatus or current (default current).",
                    ],
                    resultSummary: "Permission status string or coordinates object."
                ),
                handler: { args, context in
                    try location.read(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .locationPermissionRequest,
                    title: "Request location permission",
                    summary: "Trigger location when-in-use permission request flow.",
                    tags: ["location", "permission"],
                    example: "await apple.location.requestPermission()",
                    resultSummary: "Permission status string."
                ),
                handler: { _, context in
                    location.requestPermission(context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .weatherRead,
                    title: "Read WeatherKit weather",
                    summary: "Fetch current weather for a latitude/longitude pair.",
                    tags: ["weather", "forecast", "weatherkit"],
                    example: "await apple.weather.getCurrentWeather({ latitude: 37.77, longitude: -122.41 })",
                    requiredArguments: ["latitude", "longitude"],
                    argumentHints: [
                        "latitude": "Latitude in decimal degrees.",
                        "longitude": "Longitude in decimal degrees.",
                    ],
                    resultSummary: "Object with temperatureCelsius/condition/symbolName/date."
                ),
                handler: { args, _ in
                    try weather.read(arguments: args)
                }
            ),
        ]
    }

    private func calendarAndReminderRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                descriptor: .init(
                    id: .calendarRead,
                    title: "Read calendar events",
                    summary: "List events in a date range from EventKit.",
                    tags: ["calendar", "eventkit", "schedule"],
                    example: "await apple.calendar.listEvents({ start: '2026-02-21T00:00:00Z', end: '2026-03-01T00:00:00Z' })",
                    requiredPermissions: [.calendar],
                    optionalArguments: ["start", "end", "limit"],
                    argumentHints: [
                        "start": "ISO8601 timestamp; defaults to now.",
                        "end": "ISO8601 timestamp; defaults to start + 14 days.",
                        "limit": "Max number of items, default 50.",
                    ],
                    resultSummary: "Array of events with identifier/title/startDate/endDate/notes/calendarTitle."
                ),
                handler: { args, context in
                    try eventKit.readEvents(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .calendarWrite,
                    title: "Create calendar event",
                    summary: "Create a calendar event in the default calendar.",
                    tags: ["calendar", "eventkit", "schedule"],
                    example: "await apple.calendar.createEvent({ title: 'Standup', start: '2026-02-22T16:00:00Z', end: '2026-02-22T16:15:00Z' })",
                    requiredPermissions: [.calendarWriteOnly],
                    requiredArguments: ["title", "start", "end"],
                    optionalArguments: ["notes"],
                    argumentHints: [
                        "title": "Event title string.",
                        "start": "ISO8601 start timestamp.",
                        "end": "ISO8601 end timestamp.",
                        "notes": "Optional notes/body string.",
                    ],
                    resultSummary: "Object with identifier/title."
                ),
                handler: { args, context in
                    try eventKit.writeEvent(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .calendarUIPickCalendar,
                    title: "Pick calendar with system UI",
                    summary: "Present EventKit calendar chooser UI and return the user-selected writable calendars.",
                    tags: ["calendar", "eventkit", "system-ui", "picker"],
                    example: "await apple.calendar.pickCalendar({ selectionStyle: 'single' })",
                    requiredPermissions: [.calendarWriteOnly],
                    optionalArguments: ["selectionStyle", "displayStyle", "timeoutMs"],
                    argumentTypes: [
                        "selectionStyle": .string,
                        "displayStyle": .string,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "selectionStyle": "single (default) or multiple.",
                        "displayStyle": "writable (default) or all.",
                        "timeoutMs": "Optional timeout for waiting on user selection.",
                    ],
                    resultSummary: "Array of selected calendars with identifier/title/type/allowsContentModifications."
                ),
                handler: { args, context in
                    try systemUI.pickCalendar(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .calendarUIPresentEvent,
                    title: "Present calendar event details",
                    summary: "Present system UI for an existing calendar event identifier.",
                    tags: ["calendar", "eventkit", "system-ui", "details"],
                    example: "await apple.calendar.presentEvent({ identifier: 'EVENT_ID', allowsEditing: false })",
                    requiredPermissions: [.calendar],
                    requiredArguments: ["identifier"],
                    optionalArguments: ["allowsEditing", "allowsCalendarPreview", "timeoutMs"],
                    argumentTypes: [
                        "identifier": .string,
                        "allowsEditing": .bool,
                        "allowsCalendarPreview": .bool,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "identifier": "EventKit eventIdentifier from apple.calendar.listEvents.",
                        "allowsEditing": "Whether the user can edit from the detail UI; default false.",
                        "allowsCalendarPreview": "Whether the UI may show calendar day previews; default true.",
                        "timeoutMs": "Optional timeout for waiting on dismissal.",
                    ],
                    resultSummary: "Object with action dismissed."
                ),
                handler: { args, context in
                    try systemUI.presentCalendarEvent(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .calendarUIPresentNewEvent,
                    title: "Present calendar event editor",
                    summary: "Present system UI to let the user create or edit a new calendar event draft.",
                    tags: ["calendar", "eventkit", "system-ui", "picker"],
                    example: "await apple.calendar.presentNewEvent({ title: 'Standup', start: '2026-02-22T16:00:00Z', end: '2026-02-22T16:15:00Z' })",
                    requiredPermissions: [.calendarWriteOnly],
                    optionalArguments: ["title", "start", "end", "notes", "location"],
                    argumentTypes: [
                        "title": .string,
                        "start": .string,
                        "end": .string,
                        "notes": .string,
                        "location": .string,
                    ],
                    argumentHints: [
                        "title": "Optional event title shown in the editor.",
                        "start": "Optional ISO8601 start timestamp.",
                        "end": "Optional ISO8601 end timestamp.",
                        "notes": "Optional event notes/body text.",
                        "location": "Optional location string.",
                    ],
                    resultSummary: "Object with action plus identifier/title when the user saves."
                ),
                handler: { args, context in
                    try systemUI.presentNewCalendarEvent(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .remindersRead,
                    title: "Read reminders",
                    summary: "Read incomplete reminders from EventKit.",
                    tags: ["reminders", "eventkit", "task"],
                    example: "await apple.reminders.listReminders({ limit: 20 })",
                    requiredPermissions: [.reminders],
                    optionalArguments: ["limit"],
                    argumentHints: [
                        "limit": "Max number of reminder items, default 50.",
                    ],
                    resultSummary: "Array of reminders with identifier/title/isCompleted/dueDate."
                ),
                handler: { args, context in
                    try eventKit.readReminders(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .remindersWrite,
                    title: "Create reminder",
                    summary: "Create a reminder in default reminders list.",
                    tags: ["reminders", "eventkit", "task"],
                    example: "await apple.reminders.createReminder({ title: 'Buy batteries', dueDate: '2026-02-22T18:00:00Z' })",
                    requiredPermissions: [.reminders],
                    requiredArguments: ["title"],
                    optionalArguments: ["dueDate"],
                    argumentHints: [
                        "title": "Reminder title string.",
                        "dueDate": "Optional ISO8601 due date timestamp.",
                    ],
                    resultSummary: "Object with identifier/title."
                ),
                handler: { args, context in
                    try eventKit.writeReminder(arguments: args, context: context)
                }
            ),
        ]
    }

    private func contactRegistrations() -> [CapabilityRegistration] {
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

    private func photoAndDocumentRegistrations() -> [CapabilityRegistration] {
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

    private func interactionUIRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                descriptor: .init(
                    id: .shareUIPresent,
                    title: "Present share sheet",
                    summary: "Present system share sheet for text, URLs, and sandbox file artifacts.",
                    tags: ["share", "export", "system-ui"],
                    example: "await apple.share.present({ text: 'Report ready', paths: ['tmp:report.pdf'] })",
                    optionalArguments: ["text", "url", "path", "paths", "subject", "excludedActivityTypes", "timeoutMs"],
                    argumentTypes: [
                        "text": .string,
                        "url": .string,
                        "path": .string,
                        "paths": .array,
                        "subject": .string,
                        "excludedActivityTypes": .array,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "text": "Optional text item to share.",
                        "url": "Optional absolute HTTP(S) URL to share.",
                        "path": "Optional single sandbox file path to share.",
                        "paths": "Optional array of sandbox file paths to share.",
                        "subject": "Optional subject for services that support it.",
                        "excludedActivityTypes": "Optional array of UIActivity.ActivityType raw value strings to hide.",
                        "timeoutMs": "Optional timeout for waiting on share completion.",
                    ],
                    resultSummary: "Object with completed/activityType/action."
                ),
                handler: { args, context in
                    try systemUI.presentShareSheet(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .quickLookUIPreview,
                    title: "Preview files with Quick Look",
                    summary: "Present Quick Look preview UI for one or more sandbox file artifacts.",
                    tags: ["quicklook", "preview", "documents", "system-ui"],
                    example: "await apple.quicklook.preview({ path: 'tmp:report.pdf' })",
                    optionalArguments: ["path", "paths", "timeoutMs"],
                    argumentTypes: [
                        "path": .string,
                        "paths": .array,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "path": "Single sandbox file path to preview.",
                        "paths": "Optional array of sandbox file paths to preview.",
                        "timeoutMs": "Optional timeout for waiting on dismissal.",
                    ],
                    resultSummary: "Object with action dismissed and count."
                ),
                handler: { args, context in
                    try systemUI.previewQuickLook(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .cameraUICapture,
                    title: "Capture photo or video with camera UI",
                    summary: "Present system camera UI and export captured media into the sandbox artifact store.",
                    tags: ["camera", "capture", "photos", "system-ui", "artifact"],
                    example: "await apple.camera.capture({ mediaType: 'image', outputDirectory: 'tmp:camera' })",
                    optionalArguments: ["mediaType", "outputDirectory", "timeoutMs"],
                    argumentTypes: [
                        "mediaType": .string,
                        "outputDirectory": .string,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "mediaType": "any (default), image/photo, or video.",
                        "outputDirectory": "Optional sandbox directory for captured media; defaults to tmp:.",
                        "timeoutMs": "Optional timeout for waiting on capture/export.",
                    ],
                    resultSummary: "Object with path/artifactID/mediaType/uniformTypeIdentifier/bytes."
                ),
                handler: { args, context in
                    try systemUI.captureCamera(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .cameraUIScanData,
                    title: "Scan text or barcodes with camera UI",
                    summary: "Present VisionKit live data scanner UI and return recognized text or barcode payloads.",
                    tags: ["camera", "scan", "barcode", "text", "visionkit", "system-ui"],
                    example: "await apple.camera.scanData({ mode: 'barcode', returnsOnFirstResult: true })",
                    optionalArguments: ["mode", "recognizedDataTypes", "languages", "qualityLevel", "recognizesMultipleItems", "returnsOnFirstResult", "timeoutMs"],
                    argumentTypes: [
                        "mode": .string,
                        "recognizedDataTypes": .array,
                        "languages": .array,
                        "qualityLevel": .string,
                        "recognizesMultipleItems": .bool,
                        "returnsOnFirstResult": .bool,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "mode": "any (default), text, or barcode.",
                        "recognizedDataTypes": "Optional array containing text and/or barcode; overrides mode.",
                        "languages": "Optional text recognition language identifiers.",
                        "qualityLevel": "balanced (default), fast, or accurate.",
                        "recognizesMultipleItems": "Whether the scanner tracks multiple items at once; default false.",
                        "returnsOnFirstResult": "Whether to dismiss as soon as data is recognized; default true.",
                        "timeoutMs": "Optional timeout for waiting on a scan result or cancellation.",
                    ],
                    resultSummary: "Object with action and items containing text transcripts or barcode payloads."
                ),
                handler: { args, context in
                    try systemUI.scanData(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .mailUICompose,
                    title: "Compose mail with system UI",
                    summary: "Present system mail compose UI with optional recipients, body, and sandbox file attachments.",
                    tags: ["mail", "compose", "system-ui", "share"],
                    example: "await apple.mail.compose({ to: ['alex@example.com'], subject: 'Report', body: 'Attached.', attachments: [{ path: 'tmp:report.pdf' }] })",
                    optionalArguments: ["to", "cc", "bcc", "subject", "body", "isHTML", "attachments", "timeoutMs"],
                    argumentTypes: [
                        "to": .array,
                        "cc": .array,
                        "bcc": .array,
                        "subject": .string,
                        "body": .string,
                        "isHTML": .bool,
                        "attachments": .array,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "to": "Optional array of recipient email strings.",
                        "cc": "Optional array of CC email strings.",
                        "bcc": "Optional array of BCC email strings.",
                        "subject": "Optional subject.",
                        "body": "Optional message body.",
                        "isHTML": "Whether body should be treated as HTML; default false.",
                        "attachments": "Optional array of { path, mimeType?, filename? } sandbox file attachments.",
                        "timeoutMs": "Optional timeout for waiting on user completion.",
                    ],
                    resultSummary: "Object with action sent/saved/cancelled/failed."
                ),
                handler: { args, context in
                    try systemUI.composeMail(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .messagesUICompose,
                    title: "Compose message with system UI",
                    summary: "Present system Messages compose UI with optional recipients, body, and sandbox file attachments.",
                    tags: ["messages", "sms", "compose", "system-ui", "share"],
                    example: "await apple.messages.compose({ recipients: ['4085551212'], body: 'Report ready' })",
                    optionalArguments: ["recipients", "subject", "body", "attachments", "timeoutMs"],
                    argumentTypes: [
                        "recipients": .array,
                        "subject": .string,
                        "body": .string,
                        "attachments": .array,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "recipients": "Optional array of phone number or address strings.",
                        "subject": "Optional subject on devices/accounts that support it.",
                        "body": "Optional message body.",
                        "attachments": "Optional array of { path, filename? } sandbox file attachments.",
                        "timeoutMs": "Optional timeout for waiting on user completion.",
                    ],
                    resultSummary: "Object with action sent/cancelled/failed."
                ),
                handler: { args, context in
                    try systemUI.composeMessage(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .printUIPresent,
                    title: "Present print UI",
                    summary: "Present the system print sheet for one or more sandbox files.",
                    tags: ["print", "documents", "system-ui", "export"],
                    example: "await apple.print.present({ path: 'tmp:report.pdf', jobName: 'Report' })",
                    optionalArguments: ["path", "paths", "jobName", "outputType", "showsNumberOfCopies", "timeoutMs"],
                    argumentTypes: [
                        "path": .string,
                        "paths": .array,
                        "jobName": .string,
                        "outputType": .string,
                        "showsNumberOfCopies": .bool,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "path": "Single sandbox file path to print.",
                        "paths": "Optional array of sandbox file paths to print.",
                        "jobName": "Optional print job name.",
                        "outputType": "general (default), photo, or grayscale.",
                        "showsNumberOfCopies": "Whether copy count controls are shown; default true.",
                        "timeoutMs": "Optional timeout for waiting on print completion/cancellation.",
                    ],
                    resultSummary: "Object with action/completed for the print interaction."
                ),
                handler: { args, context in
                    try systemUI.presentPrint(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .webUIPresent,
                    title: "Present web page with system UI",
                    summary: "Present an HTTP(S) URL with the system Safari view controller.",
                    tags: ["web", "safari", "browser", "system-ui"],
                    example: "await apple.web.present({ url: 'https://example.com' })",
                    requiredArguments: ["url"],
                    optionalArguments: ["entersReaderIfAvailable", "timeoutMs"],
                    argumentTypes: [
                        "url": .string,
                        "entersReaderIfAvailable": .bool,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "url": "Absolute HTTP(S) URL to present.",
                        "entersReaderIfAvailable": "Whether Safari may enter Reader automatically; default false.",
                        "timeoutMs": "Optional timeout for waiting on dismissal.",
                    ],
                    resultSummary: "Object with action dismissed."
                ),
                handler: { args, context in
                    try systemUI.presentWeb(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .authUIWebAuthenticate,
                    title: "Authenticate with system web UI",
                    summary: "Start an ASWebAuthenticationSession for OAuth-style browser authentication.",
                    tags: ["auth", "oauth", "web", "browser", "system-ui"],
                    example: "await apple.auth.webAuthenticate({ url: 'https://example.com/oauth', callbackURLScheme: 'myapp' })",
                    requiredArguments: ["url"],
                    optionalArguments: ["callbackURLScheme", "prefersEphemeralSession", "timeoutMs"],
                    argumentTypes: [
                        "url": .string,
                        "callbackURLScheme": .string,
                        "prefersEphemeralSession": .bool,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "url": "Absolute HTTP(S) authentication URL.",
                        "callbackURLScheme": "Optional custom URL scheme that completes the session.",
                        "prefersEphemeralSession": "Whether to prefer a private browser session; default false.",
                        "timeoutMs": "Optional timeout for waiting on callback/cancellation.",
                    ],
                    resultSummary: "Object with action callback/cancelled and callbackURL when available."
                ),
                handler: { args, context in
                    try systemUI.authenticateWeb(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .uiAlertPresent,
                    title: "Present alert with custom buttons",
                    summary: "Present a system alert or action sheet and return the button the user selects.",
                    tags: ["ui", "alert", "dialog", "system-ui"],
                    example: "await apple.ui.presentAlert({ title: 'Delete draft?', message: 'This cannot be undone.', buttons: [{ id: 'cancel', title: 'Cancel', style: 'cancel' }, { id: 'delete', title: 'Delete', style: 'destructive' }] })",
                    requiredArguments: ["buttons"],
                    optionalArguments: ["title", "message", "preferredStyle", "timeoutMs"],
                    argumentTypes: [
                        "title": .string,
                        "message": .string,
                        "preferredStyle": .string,
                        "buttons": .array,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "title": "Optional alert title.",
                        "message": "Optional alert message.",
                        "preferredStyle": "alert (default) or actionSheet.",
                        "buttons": "Array of { id?, title, style? }; style is default, cancel, or destructive. At most one cancel button.",
                        "timeoutMs": "Optional timeout for waiting on user selection.",
                    ],
                    resultSummary: "Object with action/buttonID/buttonTitle/buttonIndex/style for the selected button."
                ),
                handler: { args, context in
                    try systemUI.presentAlert(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .uiPromptPresent,
                    title: "Present prompt with text fields",
                    summary: "Present a system alert with one or more text fields and custom buttons.",
                    tags: ["ui", "alert", "prompt", "input", "system-ui"],
                    example: "await apple.ui.presentPrompt({ title: 'Name', fields: [{ id: 'name', placeholder: 'Name' }], buttons: [{ id: 'cancel', title: 'Cancel', style: 'cancel' }, { id: 'ok', title: 'OK' }] })",
                    requiredArguments: ["fields", "buttons"],
                    optionalArguments: ["title", "message", "timeoutMs"],
                    argumentTypes: [
                        "title": .string,
                        "message": .string,
                        "fields": .array,
                        "buttons": .array,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "fields": "Array of { id?, placeholder?, text?/defaultValue?, secure?, keyboardType? }. keyboardType is default, email, number, phone, or url.",
                        "buttons": "Array of { id?, title, style? }; style is default, cancel, or destructive. At most one cancel button.",
                        "timeoutMs": "Optional timeout for waiting on user selection.",
                    ],
                    resultSummary: "Object with selected button metadata and values keyed by field id."
                ),
                handler: { args, context in
                    try systemUI.presentPrompt(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .settingsUIOpen,
                    title: "Open app settings",
                    summary: "Open the host app's Settings page so the user can recover denied permissions.",
                    tags: ["settings", "permissions", "system-ui"],
                    example: "await apple.settings.open()",
                    optionalArguments: ["timeoutMs"],
                    argumentTypes: [
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "timeoutMs": "Optional timeout for waiting on UIApplication.open completion.",
                    ],
                    resultSummary: "Object with action opened/failed and opened boolean."
                ),
                handler: { args, context in
                    try systemUI.openSettings(arguments: args, context: context)
                }
            ),
        ]
    }

    private func visionRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                descriptor: .init(
                    id: .visionImageAnalyze,
                    title: "Analyze image with Vision",
                    summary: "Run on-device image analysis for labels/text/barcodes on sandbox image paths.",
                    tags: ["vision", "image-analysis", "ml"],
                    example: "await apple.vision.analyzeImage({ path: 'tmp:receipt.jpg', features: ['text'], maxResults: 10 })",
                    requiredArguments: ["path"],
                    optionalArguments: ["features", "maxResults"],
                    argumentHints: [
                        "path": "Sandbox image path to analyze.",
                        "features": "Optional array including labels/text/barcodes.",
                        "maxResults": "Max observations returned per feature, default 5.",
                    ],
                    resultSummary: "Object containing requested analysis sections such as labels/text/barcodes."
                ),
                handler: { args, context in
                    try vision.analyzeImage(arguments: args, context: context)
                }
            ),
        ]
    }

    private func notificationRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                descriptor: .init(
                    id: .notificationsPermissionRequest,
                    title: "Request notification permission",
                    summary: "Request local notification authorization from the user.",
                    tags: ["notifications", "permission"],
                    example: "await apple.notifications.requestPermission()",
                    resultSummary: "Object with status/granted fields."
                ),
                handler: { _, context in
                    try notifications.requestPermission(context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .notificationsSchedule,
                    title: "Schedule local notification",
                    summary: "Schedule a local notification using time interval or fireDate trigger.",
                    tags: ["notifications", "local", "schedule"],
                    example: "await apple.notifications.schedule({ title: 'Stand up', body: 'Stretch break', secondsFromNow: 900 })",
                    requiredPermissions: [.notifications],
                    requiredArguments: ["title"],
                    optionalArguments: ["identifier", "subtitle", "body", "secondsFromNow", "fireDate", "repeats"],
                    argumentHints: [
                        "title": "Notification title text.",
                        "identifier": "Optional request identifier; defaults to codemode UUID.",
                        "secondsFromNow": "Delay in seconds for time interval trigger (default 5).",
                        "fireDate": "Optional ISO8601 timestamp for calendar trigger.",
                        "repeats": "Boolean repeat flag (time interval requires >= 60 seconds).",
                    ],
                    resultSummary: "Object with identifier/scheduled/repeats."
                ),
                handler: { args, context in
                    try notifications.schedule(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .notificationsPendingRead,
                    title: "List pending local notifications",
                    summary: "List pending local notification requests.",
                    tags: ["notifications", "local", "schedule"],
                    example: "await apple.notifications.listPending({ limit: 20 })",
                    requiredPermissions: [.notifications],
                    optionalArguments: ["limit"],
                    argumentHints: [
                        "limit": "Max number of pending requests to return, default 50.",
                    ],
                    resultSummary: "Array of pending requests with identifiers/content/trigger metadata."
                ),
                handler: { args, context in
                    try notifications.readPending(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .notificationsPendingDelete,
                    title: "Delete pending local notifications",
                    summary: "Delete pending local notifications by identifier list or clear all.",
                    tags: ["notifications", "local", "schedule"],
                    example: "await apple.notifications.cancelPending({ identifiers: ['codemode.1', 'codemode.2'] })",
                    requiredPermissions: [.notifications],
                    optionalArguments: ["identifier", "identifiers"],
                    argumentHints: [
                        "identifier": "Single pending request identifier to remove.",
                        "identifiers": "Array of pending request identifiers to remove. Omit both to clear all pending requests.",
                    ],
                    resultSummary: "Object with deleted/count fields."
                ),
                handler: { args, context in
                    try notifications.deletePending(arguments: args, context: context)
                }
            ),
        ]
    }

    private func alarmRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                descriptor: .init(
                    id: .alarmPermissionRequest,
                    title: "Request AlarmKit permission",
                    summary: "Request AlarmKit authorization from the user.",
                    tags: ["alarmkit", "permission", "alarms"],
                    example: "await ios.alarm.requestPermission()",
                    resultSummary: "Object with status/granted fields."
                ),
                handler: { _, context in
                    try alarm.requestPermission(context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .alarmRead,
                    title: "List scheduled alarms",
                    summary: "List scheduled alarms known to the bridge runtime.",
                    tags: ["alarmkit", "alarms", "schedule"],
                    example: "await ios.alarm.list({ limit: 20 })",
                    requiredPermissions: [.alarmKit],
                    optionalArguments: ["limit"],
                    argumentHints: [
                        "limit": "Max number of scheduled alarms returned, default 50.",
                    ],
                    resultSummary: "Array of scheduled alarms with identifier/title/timing fields."
                ),
                handler: { args, context in
                    try alarm.read(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .alarmSchedule,
                    title: "Schedule AlarmKit alarm",
                    summary: "Schedule an AlarmKit alarm using secondsFromNow or fireDate.",
                    tags: ["alarmkit", "alarms", "schedule"],
                    example: "await ios.alarm.schedule({ title: 'Wake up', secondsFromNow: 1800 })",
                    requiredPermissions: [.alarmKit],
                    requiredArguments: ["title"],
                    optionalArguments: ["identifier", "secondsFromNow", "fireDate"],
                    argumentHints: [
                        "title": "Alarm title shown in presentation.",
                        "identifier": "Optional UUID string; generated when omitted.",
                        "secondsFromNow": "Fallback relative delay in seconds, default 60.",
                        "fireDate": "Optional absolute ISO8601 date; used when provided.",
                    ],
                    resultSummary: "Object with identifier/scheduled/title."
                ),
                handler: { args, context in
                    try alarm.schedule(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .alarmCancel,
                    title: "Cancel scheduled alarms",
                    summary: "Cancel one or more scheduled alarms by identifier, or clear all known alarms.",
                    tags: ["alarmkit", "alarms", "schedule"],
                    example: "await ios.alarm.cancel({ identifiers: ['8F11679B-92E8-4D2F-84B4-4D0A7C95E3C3'] })",
                    requiredPermissions: [.alarmKit],
                    optionalArguments: ["identifier", "identifiers"],
                    argumentHints: [
                        "identifier": "Single alarm identifier UUID string.",
                        "identifiers": "Array of alarm identifier UUID strings. Omit both to cancel all known alarms.",
                    ],
                    resultSummary: "Object with deleted/count fields."
                ),
                handler: { args, context in
                    try alarm.cancel(arguments: args, context: context)
                }
            ),
        ]
    }

    private func healthRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                descriptor: .init(
                    id: .healthPermissionRequest,
                    title: "Request HealthKit permission",
                    summary: "Request HealthKit authorization for requested read/write types.",
                    tags: ["healthkit", "health", "permission"],
                    example: "await apple.health.requestPermission({ readTypes: ['stepCount', 'heartRate'], writeTypes: ['stepCount'] })",
                    optionalArguments: ["readTypes", "writeTypes"],
                    argumentTypes: [
                        "readTypes": .array,
                        "writeTypes": .array,
                    ],
                    argumentHints: [
                        "readTypes": "Optional array of type names to read, e.g. stepCount, heartRate, activeEnergyBurned.",
                        "writeTypes": "Optional array of type names to write (quantity types only).",
                    ],
                    resultSummary: "Object with status/granted fields and requested type arrays."
                ),
                handler: { args, context in
                    try health.requestPermission(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .healthRead,
                    title: "Read HealthKit samples",
                    summary: "Read HealthKit samples for a supported type and date range.",
                    tags: ["healthkit", "health", "query"],
                    example: "await apple.health.read({ type: 'stepCount', start: '2026-03-03T00:00:00Z', end: '2026-03-04T00:00:00Z', limit: 25, unit: 'count' })",
                    requiredArguments: ["type"],
                    optionalArguments: ["start", "end", "limit", "unit"],
                    argumentTypes: [
                        "type": .string,
                        "start": .string,
                        "end": .string,
                        "limit": .number,
                        "unit": .string,
                    ],
                    argumentHints: [
                        "type": "Supported: stepCount, heartRate, activeEnergyBurned, bodyMass, distanceWalkingRunning, sleepAnalysis, workout.",
                        "start": "Optional ISO8601 start timestamp; defaults to last 24h.",
                        "end": "Optional ISO8601 end timestamp; defaults to now.",
                        "limit": "Max number of samples, default 50.",
                        "unit": "Optional unit override for quantity types (count, bpm, kcal, kg, m).",
                    ],
                    resultSummary: "Array of samples with identifier/type/value and timing metadata."
                ),
                handler: { args, context in
                    try health.read(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .healthWrite,
                    title: "Write HealthKit quantity sample",
                    summary: "Write a HealthKit quantity sample for supported writable quantity types.",
                    tags: ["healthkit", "health", "write"],
                    example: "await apple.health.write({ type: 'stepCount', value: 1200, unit: 'count', start: '2026-03-04T08:00:00Z', end: '2026-03-04T08:30:00Z' })",
                    requiredArguments: ["type", "value"],
                    optionalArguments: ["unit", "start", "end"],
                    argumentTypes: [
                        "type": .string,
                        "value": .number,
                        "unit": .string,
                        "start": .string,
                        "end": .string,
                    ],
                    argumentHints: [
                        "type": "Writable types: stepCount, heartRate, activeEnergyBurned, bodyMass, distanceWalkingRunning.",
                        "value": "Numeric sample value.",
                        "unit": "Optional unit (count, bpm, kcal, kg, m).",
                        "start": "Optional ISO8601 start timestamp; defaults to now.",
                        "end": "Optional ISO8601 end timestamp; defaults to start.",
                    ],
                    resultSummary: "Object with identifier/type/value/unit and written=true."
                ),
                handler: { args, context in
                    try health.write(arguments: args, context: context)
                }
            ),
        ]
    }

    private func homeRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                descriptor: .init(
                    id: .homeRead,
                    title: "Read HomeKit graph",
                    summary: "Read homes/accessories/services (and optional characteristics) from HomeKit.",
                    tags: ["homekit", "iot", "devices"],
                    example: "await apple.home.list({ includeCharacteristics: true, limit: 5 })",
                    requiredPermissions: [.homeKit],
                    optionalArguments: ["includeCharacteristics", "limit"],
                    argumentHints: [
                        "includeCharacteristics": "Boolean; include characteristic details when true.",
                        "limit": "Max number of homes to return, default 10.",
                    ],
                    resultSummary: "Array of homes with accessories/services snapshot."
                ),
                handler: { args, context in
                    try home.read(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .homeWrite,
                    title: "Write HomeKit characteristic",
                    summary: "Write a value to a writable HomeKit characteristic for a target accessory.",
                    tags: ["homekit", "iot", "devices", "control"],
                    example: "await apple.home.writeCharacteristic({ accessoryIdentifier: 'UUID', characteristicType: 'HMCharacteristicTypePowerState', value: true })",
                    requiredPermissions: [.homeKit],
                    requiredArguments: ["accessoryIdentifier", "characteristicType", "value"],
                    optionalArguments: ["serviceType"],
                    argumentTypes: [
                        "accessoryIdentifier": .string,
                        "characteristicType": .string,
                        "value": .any,
                        "serviceType": .string,
                    ],
                    argumentHints: [
                        "accessoryIdentifier": "Accessory UUID string from home.read output.",
                        "characteristicType": "Characteristic type identifier (e.g. HMCharacteristicTypePowerState).",
                        "value": "Target value; string/number/bool/null.",
                        "serviceType": "Optional service type filter for characteristic lookup.",
                    ],
                    resultSummary: "Object with accessoryIdentifier/characteristicType/written."
                ),
                handler: { args, context in
                    try home.write(arguments: args, context: context)
                }
            ),
        ]
    }

    private func mediaRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                descriptor: .init(
                    id: .mediaMetadataRead,
                    title: "Read media metadata",
                    summary: "Read duration and track metadata from media files.",
                    tags: ["media", "avfoundation", "metadata"],
                    example: "await apple.media.metadata({ path: 'tmp:video.mov' })",
                    requiredArguments: ["path"],
                    argumentHints: [
                        "path": "Sandbox path like tmp:clip.mov.",
                    ],
                    resultSummary: "Object with path/durationSeconds/tracks."
                ),
                handler: { args, context in
                    try media.metadata(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .mediaFrameExtract,
                    title: "Extract video frame",
                    summary: "Extract frame at time offset and persist JPEG output.",
                    tags: ["media", "avfoundation", "thumbnail"],
                    example: "await apple.media.extractFrame({ path: 'tmp:video.mov', timeMs: 1500 })",
                    requiredArguments: ["path"],
                    optionalArguments: ["timeMs", "outputPath"],
                    argumentHints: [
                        "path": "Input video sandbox path.",
                        "timeMs": "Frame timestamp in milliseconds; default 0.",
                        "outputPath": "Optional output sandbox path; defaults to tmp-generated JPEG.",
                    ],
                    resultSummary: "Object with output path and artifactID."
                ),
                handler: { args, context in
                    try media.extractFrame(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .mediaTranscode,
                    title: "Transcode media",
                    summary: "Transcode media into MP4 with preset quality.",
                    tags: ["media", "avfoundation", "transcode"],
                    example: "await apple.media.transcode({ path: 'tmp:input.mov', preset: 'AVAssetExportPresetMediumQuality' })",
                    requiredArguments: ["path"],
                    optionalArguments: ["outputPath", "preset"],
                    argumentHints: [
                        "path": "Input media sandbox path.",
                        "outputPath": "Optional output sandbox path; defaults to tmp-generated mp4.",
                        "preset": "AVAssetExportSession preset string; default AVAssetExportPresetMediumQuality.",
                    ],
                    resultSummary: "Object with output path/artifactID/preset."
                ),
                handler: { args, context in
                    try media.transcode(arguments: args, context: context)
                }
            ),
        ]
    }

    private func filesystemRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                descriptor: .init(
                    id: .fsList,
                    title: "List directory",
                    summary: "List files/directories within allowed sandbox roots as entry objects.",
                    tags: ["filesystem", "io", "fs"],
                    example: "await apple.fs.list({ path: 'tmp:' })",
                    requiredArguments: ["path"],
                    argumentHints: [
                        "path": "Directory path using allowed root prefix (tmp:, caches:, documents:).",
                    ],
                    resultSummary: "Array of entry objects with name/path/isDirectory/size. Use entry.name for filenames; fs.promises.readdir returns the same entry objects, not strings."
                ),
                handler: { args, context in
                    try fs.list(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .fsRead,
                    title: "Read file",
                    summary: "Read text/base64 file data within allowed sandbox roots.",
                    tags: ["filesystem", "io", "fs"],
                    example: "await apple.fs.read({ path: 'tmp:data.json', encoding: 'utf8' })",
                    requiredArguments: ["path"],
                    optionalArguments: ["encoding"],
                    argumentHints: [
                        "path": "File path using allowed root prefix.",
                        "encoding": "utf8 (default) or base64.",
                    ],
                    resultSummary: "Object with path plus text or base64 field."
                ),
                handler: { args, context in
                    try fs.read(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .fsWrite,
                    title: "Write file",
                    summary: "Write text/base64 file data within allowed sandbox roots.",
                    tags: ["filesystem", "io", "fs"],
                    example: "await apple.fs.write({ path: 'tmp:data.json', data: '{\"ok\":true}' })",
                    requiredArguments: ["path"],
                    optionalArguments: ["data", "encoding"],
                    argumentHints: [
                        "path": "File path using allowed root prefix.",
                        "data": "UTF-8 text or base64 string depending on encoding.",
                        "encoding": "utf8 (default) or base64.",
                    ],
                    resultSummary: "Object with path and bytesWritten."
                ),
                handler: { args, context in
                    try fs.write(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .fsMove,
                    title: "Move file",
                    summary: "Move file/directory within allowed sandbox roots.",
                    tags: ["filesystem", "io", "fs"],
                    example: "await apple.fs.move({ from: 'tmp:a.txt', to: 'tmp:b.txt' })",
                    requiredArguments: ["from", "to"],
                    argumentHints: [
                        "from": "Source sandbox path.",
                        "to": "Destination sandbox path.",
                    ],
                    resultSummary: "Object with from/to resolved paths."
                ),
                handler: { args, context in
                    try fs.move(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .fsCopy,
                    title: "Copy file",
                    summary: "Copy file/directory within allowed sandbox roots.",
                    tags: ["filesystem", "io", "fs"],
                    example: "await apple.fs.copy({ from: 'tmp:a.txt', to: 'tmp:b.txt' })",
                    requiredArguments: ["from", "to"],
                    argumentHints: [
                        "from": "Source sandbox path.",
                        "to": "Destination sandbox path.",
                    ],
                    resultSummary: "Object with from/to resolved paths."
                ),
                handler: { args, context in
                    try fs.copy(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .fsDelete,
                    title: "Delete file",
                    summary: "Delete file/directory within allowed sandbox roots.",
                    tags: ["filesystem", "io", "fs"],
                    example: "await apple.fs.delete({ path: 'tmp:data.json' })",
                    requiredArguments: ["path"],
                    optionalArguments: ["recursive"],
                    argumentHints: [
                        "path": "Path to file or directory.",
                        "recursive": "Required as true when deleting a directory.",
                    ],
                    resultSummary: "Object with deleted flag and path."
                ),
                handler: { args, context in
                    try fs.delete(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .fsStat,
                    title: "Stat path",
                    summary: "Read file metadata within allowed sandbox roots.",
                    tags: ["filesystem", "io", "fs"],
                    example: "await apple.fs.stat({ path: 'tmp:data.json' })",
                    requiredArguments: ["path"],
                    argumentHints: [
                        "path": "File or directory path.",
                    ],
                    resultSummary: "Object with path/isDirectory/size/createdAt/modifiedAt."
                ),
                handler: { args, context in
                    try fs.stat(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .fsMkdir,
                    title: "Create directory",
                    summary: "Create directories within allowed sandbox roots.",
                    tags: ["filesystem", "io", "fs"],
                    example: "await apple.fs.mkdir({ path: 'tmp:artifacts', recursive: true })",
                    requiredArguments: ["path"],
                    optionalArguments: ["recursive"],
                    argumentHints: [
                        "path": "Directory path to create.",
                        "recursive": "Boolean; default true.",
                    ],
                    resultSummary: "Object with created flag and path."
                ),
                handler: { args, context in
                    try fs.mkdir(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .fsExists,
                    title: "Check path exists",
                    summary: "Check if file/directory exists within allowed sandbox roots.",
                    tags: ["filesystem", "io", "fs"],
                    example: "await apple.fs.exists({ path: 'tmp:data.json' })",
                    requiredArguments: ["path"],
                    argumentHints: [
                        "path": "File or directory path to check.",
                    ],
                    resultSummary: "Boolean."
                ),
                handler: { args, context in
                    try fs.exists(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .fsAccess,
                    title: "Check path access",
                    summary: "Check read/write access for path within allowed sandbox roots.",
                    tags: ["filesystem", "io", "fs"],
                    example: "await apple.fs.access({ path: 'tmp:data.json' })",
                    requiredArguments: ["path"],
                    argumentHints: [
                        "path": "File or directory path to inspect.",
                    ],
                    resultSummary: "Object with readable/writable/path."
                ),
                handler: { args, context in
                    try fs.access(arguments: args, context: context)
                }
            ),
        ]
    }
}
