import Foundation

extension DefaultCapabilityRegistrationBuilder {
    func bigTicketAppleRegistrations() -> [CapabilityRegistration] {
        [
            cloudKitRegistrations(),
            remoteNotificationRegistrations(),
            speechRegistrations(),
            appIntentsRegistrations(),
            foundationModelsRegistrations(),
            activityRegistrations(),
            mapsRegistrations(),
            musicRegistrations(),
            passKitRegistrations(),
            storeKitRegistrations(),
        ].flatMap { $0 }
    }


    func cloudKitRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                jsNames: ["apple.cloudkit.getAccountStatus"],
                descriptor: .init(
                    id: .cloudKitAccountStatus,
                    title: "Read CloudKit account status",
                    summary: "Read iCloud account availability for CloudKit-backed agent state.",
                    tags: ["cloudkit", "icloud", "sync", "account"],
                    example: "await apple.cloudkit.getAccountStatus({ containerIdentifier: 'iCloud.com.example.app' })",
                    optionalArguments: ["containerIdentifier"],
                    argumentHints: [
                        "containerIdentifier": "Optional iCloud container identifier; defaults to the host client's configured container.",
                    ],
                    resultSummary: "Object with status/accountAvailable and containerIdentifier when available."
                ),
                handler: { args, _ in
                    try cloudKit.accountStatus(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.cloudkit.queryRecords"],
                descriptor: .init(
                    id: .cloudKitRecordsQuery,
                    title: "Query CloudKit records",
                    summary: "Query records from a private/shared/public CloudKit database for synced agent state.",
                    tags: ["cloudkit", "icloud", "database", "query"],
                    example: "await apple.cloudkit.queryRecords({ database: 'private', recordType: 'Task', limit: 20 })",
                    requiredArguments: ["recordType"],
                    optionalArguments: ["database", "containerIdentifier", "zoneID", "predicate", "sortDescriptors", "desiredKeys", "limit"],
                    argumentHints: [
                        "database": "private (default), shared, or public.",
                        "recordType": "CloudKit record type to query.",
                        "containerIdentifier": "Optional iCloud container identifier.",
                        "zoneID": "Optional custom zone identifier.",
                        "predicate": "Host-supported predicate object or string; keep predicates bounded and repairable.",
                        "sortDescriptors": "Optional array of sort descriptor objects.",
                        "desiredKeys": "Optional array of field keys to return.",
                        "limit": "Max records to return; default is host-defined.",
                    ],
                    resultSummary: "Array of records with recordName/recordType/fields/modifiedAt/database."
                ),
                handler: { args, _ in
                    try cloudKit.queryRecords(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.cloudkit.saveRecord"],
                descriptor: .init(
                    id: .cloudKitRecordSave,
                    title: "Save CloudKit record",
                    summary: "Create or update a CloudKit record in a private/shared/public database.",
                    tags: ["cloudkit", "icloud", "database", "write"],
                    example: "await apple.cloudkit.saveRecord({ database: 'private', recordType: 'Task', recordName: 'task-1', fields: { title: 'Review' } })",
                    requiredArguments: ["recordType", "fields"],
                    optionalArguments: ["recordName", "database", "containerIdentifier", "zoneID", "savePolicy"],
                    argumentHints: [
                        "recordType": "CloudKit record type to create or update.",
                        "fields": "JSON object mapped by the host client into supported CloudKit field values.",
                        "recordName": "Optional CloudKit recordName; omitted means create a new record.",
                        "database": "private (default), shared, or public.",
                        "containerIdentifier": "Optional iCloud container identifier.",
                        "zoneID": "Optional custom zone identifier.",
                        "savePolicy": "Host-supported save policy such as changedKeys or allKeys.",
                    ],
                    resultSummary: "Saved record object with recordName/recordType/fields/changeTag/database."
                ),
                handler: { args, _ in
                    try cloudKit.saveRecord(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.cloudkit.deleteRecord"],
                descriptor: .init(
                    id: .cloudKitRecordDelete,
                    title: "Delete CloudKit record",
                    summary: "Delete a CloudKit record by recordName from a configured database.",
                    tags: ["cloudkit", "icloud", "database", "delete"],
                    example: "await apple.cloudkit.deleteRecord({ database: 'private', recordName: 'task-1' })",
                    requiredArguments: ["recordName"],
                    optionalArguments: ["database", "containerIdentifier", "zoneID"],
                    argumentHints: [
                        "recordName": "CloudKit recordName to delete.",
                        "database": "private (default), shared, or public.",
                        "containerIdentifier": "Optional iCloud container identifier.",
                        "zoneID": "Optional custom zone identifier.",
                    ],
                    resultSummary: "Object with recordName/deleted/database."
                ),
                handler: { args, _ in
                    try cloudKit.deleteRecord(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.cloudkit.subscribe"],
                descriptor: .init(
                    id: .cloudKitSubscriptionSave,
                    title: "Save CloudKit subscription",
                    summary: "Register a bounded CloudKit query subscription so the host can enqueue subscription events later.",
                    tags: ["cloudkit", "icloud", "subscription", "inbox"],
                    example: "await apple.cloudkit.subscribe({ subscriptionID: 'tasks', database: 'private', recordType: 'Task' })",
                    requiredArguments: ["subscriptionID", "recordType"],
                    optionalArguments: ["database", "containerIdentifier", "zoneID", "predicate", "firesOnRecordCreation", "firesOnRecordUpdate", "firesOnRecordDeletion"],
                    argumentHints: [
                        "subscriptionID": "Stable host-visible subscription identifier.",
                        "recordType": "CloudKit record type to observe.",
                        "database": "private (default), shared, or public.",
                        "predicate": "Host-supported predicate object or string.",
                        "firesOnRecordCreation": "Whether creation events are enqueued; default true.",
                        "firesOnRecordUpdate": "Whether update events are enqueued; default true.",
                        "firesOnRecordDeletion": "Whether delete events are enqueued; default true.",
                    ],
                    resultSummary: "Object with subscriptionID/saved/database."
                ),
                handler: { args, _ in
                    try cloudKit.saveSubscription(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.cloudkit.listEvents"],
                descriptor: .init(
                    id: .cloudKitSubscriptionEventsRead,
                    title: "Read CloudKit subscription inbox",
                    summary: "Read bounded CloudKit subscription events previously received by the host.",
                    tags: ["cloudkit", "icloud", "subscription", "inbox", "events"],
                    example: "await apple.cloudkit.listEvents({ subscriptionID: 'tasks', limit: 20 })",
                    optionalArguments: ["subscriptionID", "limit", "afterCursor"],
                    argumentHints: [
                        "subscriptionID": "Optional subscription filter.",
                        "limit": "Maximum number of inbox events to read.",
                        "afterCursor": "Optional host-provided cursor for incremental reads.",
                    ],
                    resultSummary: "Array of subscription event objects with cursor/subscriptionID/recordName/reason/database."
                ),
                handler: { args, _ in
                    try cloudKit.readSubscriptionEvents(arguments: args)
                }
            ),
        ]
    }


    func remoteNotificationRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                jsNames: ["apple.notifications.registerRemote"],
                descriptor: .init(
                    id: .notificationsRemoteRegister,
                    title: "Register for remote notifications",
                    summary: "Ask the host app to register with APNs and record the client device-token lifecycle.",
                    tags: ["notifications", "apns", "remote", "registration"],
                    example: "await apple.notifications.registerRemote()",
                    optionalArguments: ["types"],
                    argumentHints: [
                        "types": "Optional host-supported notification types; APNs provider sending is intentionally out of scope.",
                    ],
                    resultSummary: "Object with registered/status and deviceToken when already available."
                ),
                handler: { args, _ in
                    try remoteNotifications.register(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.notifications.getRemoteToken"],
                descriptor: .init(
                    id: .notificationsRemoteTokenRead,
                    title: "Read APNs device token",
                    summary: "Read the latest APNs device token captured by the host app.",
                    tags: ["notifications", "apns", "remote", "token"],
                    example: "await apple.notifications.getRemoteToken()",
                    resultSummary: "Object with token/environment/updatedAt or null token when registration has not completed."
                ),
                handler: { args, _ in
                    try remoteNotifications.readToken(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.notifications.getSettings"],
                descriptor: .init(
                    id: .notificationsSettingsRead,
                    title: "Read notification settings",
                    summary: "Read UserNotifications/APNs client settings exposed by the host.",
                    tags: ["notifications", "apns", "settings", "permission"],
                    example: "await apple.notifications.getSettings()",
                    resultSummary: "Object with authorizationStatus/alert/badge/sound/criticalAlert/providesAppNotificationSettings."
                ),
                handler: { args, _ in
                    try remoteNotifications.readSettings(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.notifications.setCategories"],
                descriptor: .init(
                    id: .notificationsCategoriesSet,
                    title: "Set notification categories",
                    summary: "Register host-approved notification categories and actions for push/local response handling.",
                    tags: ["notifications", "apns", "categories", "actions"],
                    example: "await apple.notifications.setCategories({ categories: [{ identifier: 'task', actions: [{ identifier: 'done', title: 'Done' }] }] })",
                    requiredArguments: ["categories"],
                    argumentHints: [
                        "categories": "Array of category definitions with identifier/actions/options approved by the host.",
                    ],
                    resultSummary: "Object with registered category identifiers."
                ),
                handler: { args, _ in
                    try remoteNotifications.setCategories(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.notifications.listResponses"],
                descriptor: .init(
                    id: .notificationsResponsesRead,
                    title: "Read notification response inbox",
                    summary: "Read bounded notification action/open responses captured by the host for later agent handling.",
                    tags: ["notifications", "apns", "response", "inbox", "events"],
                    example: "await apple.notifications.listResponses({ limit: 20 })",
                    optionalArguments: ["limit", "categoryIdentifier", "actionIdentifier", "afterCursor"],
                    argumentHints: [
                        "limit": "Maximum number of response events to read.",
                        "categoryIdentifier": "Optional category filter.",
                        "actionIdentifier": "Optional action filter.",
                        "afterCursor": "Optional host-provided cursor for incremental reads.",
                    ],
                    resultSummary: "Array of response events with cursor/identifier/actionIdentifier/categoryIdentifier/userText/userInfo/date."
                ),
                handler: { args, _ in
                    try remoteNotifications.readResponses(arguments: args)
                }
            ),
        ]
    }


    func speechRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                jsNames: ["apple.speech.requestPermission"],
                descriptor: .init(
                    id: .speechPermissionRequest,
                    title: "Request speech recognition permission",
                    summary: "Trigger the Speech recognition permission prompt.",
                    tags: ["speech", "permission", "transcription"],
                    example: "await apple.speech.requestPermission()",
                    resultSummary: "Object with status/granted."
                ),
                handler: { _, context in
                    try speech.requestPermission(context: context)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.speech.getStatus"],
                descriptor: .init(
                    id: .speechStatus,
                    title: "Read speech recognition permission status",
                    summary: "Read Speech recognition permission status without starting capture.",
                    tags: ["speech", "permission", "transcription"],
                    example: "await apple.speech.getStatus()",
                    resultSummary: "Object with status/granted."
                ),
                handler: { _, context in
                    try speech.status(context: context)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.speech.transcribeFile"],
                descriptor: .init(
                    id: .speechFileTranscribe,
                    title: "Transcribe audio file",
                    summary: "Transcribe a sandbox audio file through the host Speech adapter.",
                    tags: ["speech", "transcription", "audio"],
                    example: "await apple.speech.transcribeFile({ path: 'tmp:meeting.m4a', locale: 'en-US', timeoutMs: 60000 })",
                    requiredPermissions: [.speechRecognition],
                    requiredArguments: ["path"],
                    optionalArguments: ["locale", "timeoutMs", "requiresOnDeviceRecognition", "taskHint"],
                    argumentHints: [
                        "path": "Sandbox audio file path.",
                        "locale": "BCP-47 locale identifier such as en-US.",
                        "timeoutMs": "Maximum transcription wait time in milliseconds.",
                        "requiresOnDeviceRecognition": "Whether to require on-device recognition when the host supports it.",
                        "taskHint": "Speech task hint such as dictation, search, or confirmation.",
                    ],
                    resultSummary: "Object with transcript/segments/locale/isFinal/durationSeconds."
                ),
                handler: { args, context in
                    try speech.transcribeFile(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.speech.transcribeMicrophone"],
                descriptor: .init(
                    id: .speechMicrophoneTranscribe,
                    title: "Transcribe microphone audio",
                    summary: "Run live microphone transcription through a host-mediated session with an explicit timeout.",
                    tags: ["speech", "transcription", "audio", "microphone"],
                    example: "await apple.speech.transcribeMicrophone({ locale: 'en-US', timeoutMs: 15000 })",
                    requiredPermissions: [.speechRecognition, .microphone],
                    optionalArguments: ["locale", "timeoutMs", "requiresOnDeviceRecognition", "taskHint", "partialResults"],
                    argumentHints: [
                        "locale": "BCP-47 locale identifier such as en-US.",
                        "timeoutMs": "Maximum microphone capture/transcription time in milliseconds.",
                        "requiresOnDeviceRecognition": "Whether to require on-device recognition when the host supports it.",
                        "taskHint": "Speech task hint such as dictation, search, or confirmation.",
                        "partialResults": "Whether partial transcripts may be returned.",
                    ],
                    resultSummary: "Object with transcript/segments/locale/isFinal/timedOut."
                ),
                handler: { args, context in
                    try speech.transcribeMicrophone(arguments: args, context: context)
                }
            ),
        ]
    }
}
