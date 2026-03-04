import Foundation

public enum DefaultCapabilityLoader {
    public static func loadAllRegistrations() -> [CapabilityRegistration] {
        let fs = FileSystemBridge()
        let network = NetworkBridge()
        let keychain = KeychainBridge()
        let location = LocationBridge()
        let weather = WeatherBridge()
        let eventKit = EventKitBridge()
        let contacts = ContactsBridge()
        let photos = PhotosBridge()
        let vision = VisionBridge()
        let notifications = NotificationsBridge()
        let alarm = AlarmBridge()
        let health = HealthBridge()
        let home = HomeBridge()
        let media = MediaBridge()

        return [
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
            CapabilityRegistration(
                descriptor: .init(
                    id: .keychainRead,
                    title: "Read Keychain value",
                    summary: "Read a string value from app-scoped Keychain storage.",
                    tags: ["security", "token", "keychain"],
                    example: "await ios.keychain.get('auth_token')",
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
                    example: "await ios.keychain.set('auth_token', token)",
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
                    example: "await ios.keychain.delete('auth_token')",
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
            CapabilityRegistration(
                descriptor: .init(
                    id: .locationRead,
                    title: "Read location state or coordinates",
                    summary: "Read location permission status or current coordinates.",
                    tags: ["location", "permission", "geospatial"],
                    example: "await ios.location.getCurrentPosition()",
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
                    example: "await ios.location.requestPermission()",
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
                    example: "await ios.weather.getCurrentWeather({ latitude: 37.77, longitude: -122.41 })",
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
            CapabilityRegistration(
                descriptor: .init(
                    id: .calendarRead,
                    title: "Read calendar events",
                    summary: "List events in a date range from EventKit.",
                    tags: ["calendar", "eventkit", "schedule"],
                    example: "await ios.calendar.listEvents({ start: '2026-02-21T00:00:00Z', end: '2026-03-01T00:00:00Z' })",
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
                    example: "await ios.calendar.createEvent({ title: 'Standup', start: '2026-02-22T16:00:00Z', end: '2026-02-22T16:15:00Z' })",
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
                    id: .remindersRead,
                    title: "Read reminders",
                    summary: "Read incomplete reminders from EventKit.",
                    tags: ["reminders", "eventkit", "task"],
                    example: "await ios.reminders.listReminders({ limit: 20 })",
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
                    example: "await ios.reminders.createReminder({ title: 'Buy batteries', dueDate: '2026-02-22T18:00:00Z' })",
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
            CapabilityRegistration(
                descriptor: .init(
                    id: .contactsRead,
                    title: "Read contacts",
                    summary: "Read contacts with bounded fields.",
                    tags: ["contacts", "address-book", "people"],
                    example: "await ios.contacts.list({ limit: 25 })",
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
                    example: "await ios.contacts.search({ query: 'Alex', limit: 10 })",
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
                    id: .photosRead,
                    title: "List photo library assets",
                    summary: "List photos/videos from the user photo library.",
                    tags: ["photos", "photo-library", "media"],
                    example: "await ios.photos.list({ mediaType: 'image', limit: 20 })",
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
                    example: "await ios.photos.export({ localIdentifier: 'ABC/L0/001', outputPath: 'tmp:exported.jpg' })",
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
                    id: .visionImageAnalyze,
                    title: "Analyze image with Vision",
                    summary: "Run on-device image analysis for labels/text/barcodes on sandbox image paths.",
                    tags: ["vision", "image-analysis", "ml"],
                    example: "await ios.vision.analyzeImage({ path: 'tmp:receipt.jpg', features: ['text'], maxResults: 10 })",
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
            CapabilityRegistration(
                descriptor: .init(
                    id: .notificationsPermissionRequest,
                    title: "Request notification permission",
                    summary: "Request local notification authorization from the user.",
                    tags: ["notifications", "permission"],
                    example: "await ios.notifications.requestPermission()",
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
                    example: "await ios.notifications.schedule({ title: 'Stand up', body: 'Stretch break', secondsFromNow: 900 })",
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
                    example: "await ios.notifications.listPending({ limit: 20 })",
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
                    example: "await ios.notifications.cancelPending({ identifiers: ['codemode.1', 'codemode.2'] })",
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
            CapabilityRegistration(
                descriptor: .init(
                    id: .healthPermissionRequest,
                    title: "Request HealthKit permission",
                    summary: "Request HealthKit authorization for requested read/write types.",
                    tags: ["healthkit", "health", "permission"],
                    example: "await ios.health.requestPermission({ readTypes: ['stepCount', 'heartRate'], writeTypes: ['stepCount'] })",
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
                    example: "await ios.health.read({ type: 'stepCount', start: '2026-03-03T00:00:00Z', end: '2026-03-04T00:00:00Z', limit: 25, unit: 'count' })",
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
                    example: "await ios.health.write({ type: 'stepCount', value: 1200, unit: 'count', start: '2026-03-04T08:00:00Z', end: '2026-03-04T08:30:00Z' })",
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
            CapabilityRegistration(
                descriptor: .init(
                    id: .homeRead,
                    title: "Read HomeKit graph",
                    summary: "Read homes/accessories/services (and optional characteristics) from HomeKit.",
                    tags: ["homekit", "iot", "devices"],
                    example: "await ios.home.list({ includeCharacteristics: true, limit: 5 })",
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
                    example: "await ios.home.writeCharacteristic({ accessoryIdentifier: 'UUID', characteristicType: 'HMCharacteristicTypePowerState', value: true })",
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
            CapabilityRegistration(
                descriptor: .init(
                    id: .mediaMetadataRead,
                    title: "Read media metadata",
                    summary: "Read duration and track metadata from media files.",
                    tags: ["media", "avfoundation", "metadata"],
                    example: "await ios.media.metadata({ path: 'tmp:video.mov' })",
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
                    example: "await ios.media.extractFrame({ path: 'tmp:video.mov', timeMs: 1500 })",
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
                    example: "await ios.media.transcode({ path: 'tmp:input.mov', preset: 'AVAssetExportPresetMediumQuality' })",
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
            CapabilityRegistration(
                descriptor: .init(
                    id: .fsList,
                    title: "List directory",
                    summary: "List files/directories within allowed sandbox roots.",
                    tags: ["filesystem", "io", "fs"],
                    example: "await ios.fs.list({ path: 'tmp:' })",
                    requiredArguments: ["path"],
                    argumentHints: [
                        "path": "Directory path using allowed root prefix (tmp:, caches:, documents:).",
                    ],
                    resultSummary: "Array of entries with name/path/isDirectory/size."
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
                    example: "await ios.fs.read({ path: 'tmp:data.json', encoding: 'utf8' })",
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
                    example: "await ios.fs.write({ path: 'tmp:data.json', data: '{\"ok\":true}' })",
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
                    example: "await ios.fs.move({ from: 'tmp:a.txt', to: 'tmp:b.txt' })",
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
                    example: "await ios.fs.copy({ from: 'tmp:a.txt', to: 'tmp:b.txt' })",
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
                    example: "await ios.fs.delete({ path: 'tmp:data.json' })",
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
                    example: "await ios.fs.stat({ path: 'tmp:data.json' })",
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
                    example: "await ios.fs.mkdir({ path: 'tmp:artifacts', recursive: true })",
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
                    example: "await ios.fs.exists({ path: 'tmp:data.json' })",
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
                    example: "await ios.fs.access({ path: 'tmp:data.json' })",
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
