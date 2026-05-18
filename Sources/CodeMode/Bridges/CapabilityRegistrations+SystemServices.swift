import Foundation

extension DefaultCapabilityRegistrationBuilder {
    func visionRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                jsNames: ["apple.vision.analyzeImage"],
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


    func notificationRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                jsNames: ["apple.notifications.requestPermission"],
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
                jsNames: ["apple.notifications.schedule"],
                descriptor: .init(
                    id: .notificationsSchedule,
                    title: "Schedule local notification",
                    summary: "Schedule a local notification using time interval or fireDate trigger.",
                    tags: ["notifications", "local", "schedule"],
                    example: "await apple.notifications.schedule({ title: 'Stand up', body: 'Stretch break', secondsFromNow: 900 })",
                    requiredPermissions: [.notifications],
                    requiredArguments: ["title"],
                    optionalArguments: [
                        "identifier",
                        "subtitle",
                        "body",
                        "secondsFromNow",
                        "fireDate",
                        "repeats",
                        "sound",
                        "badge",
                        "userInfo",
                        "threadIdentifier",
                        "categoryIdentifier",
                    ],
                    argumentHints: [
                        "title": "Notification title text.",
                        "identifier": "Optional request identifier; defaults to codemode UUID.",
                        "subtitle": "Optional subtitle text.",
                        "body": "Optional body text.",
                        "secondsFromNow": "Delay in seconds for time interval trigger (default 5).",
                        "fireDate": "Optional ISO8601 timestamp for calendar trigger.",
                        "repeats": "Boolean repeat flag (time interval requires >= 60 seconds).",
                        "sound": "default (default), none, or a bundled custom sound name.",
                        "badge": "Optional app icon badge number.",
                        "userInfo": "Optional property-list-safe userInfo object.",
                        "threadIdentifier": "Optional thread identifier for notification grouping.",
                        "categoryIdentifier": "Optional category identifier for notification actions.",
                    ],
                    resultSummary: "Object with identifier/scheduled/repeats."
                ),
                handler: { args, context in
                    try notifications.schedule(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.notifications.listPending"],
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
                jsNames: ["apple.notifications.cancelPending"],
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
            CapabilityRegistration(
                jsNames: ["apple.notifications.listDelivered"],
                descriptor: .init(
                    id: .notificationsDeliveredRead,
                    title: "List delivered local notifications",
                    summary: "List notifications currently delivered in Notification Center.",
                    tags: ["notifications", "local", "delivered"],
                    example: "await apple.notifications.listDelivered({ limit: 20 })",
                    requiredPermissions: [.notifications],
                    optionalArguments: ["limit"],
                    argumentHints: [
                        "limit": "Max number of delivered notifications to return, default 50.",
                    ],
                    resultSummary: "Array of delivered notifications with identifiers/content/date metadata."
                ),
                handler: { args, context in
                    try notifications.readDelivered(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.notifications.removeDelivered"],
                descriptor: .init(
                    id: .notificationsDeliveredDelete,
                    title: "Delete delivered local notifications",
                    summary: "Delete delivered notifications by identifier list or clear all.",
                    tags: ["notifications", "local", "delivered", "delete"],
                    example: "await apple.notifications.removeDelivered({ identifiers: ['codemode.1', 'codemode.2'] })",
                    requiredPermissions: [.notifications],
                    optionalArguments: ["identifier", "identifiers"],
                    argumentHints: [
                        "identifier": "Single delivered notification identifier to remove.",
                        "identifiers": "Array of delivered notification identifiers to remove. Omit both to clear all delivered notifications.",
                    ],
                    resultSummary: "Object with deleted/count fields."
                ),
                handler: { args, context in
                    try notifications.deleteDelivered(arguments: args, context: context)
                }
            ),
        ]
    }


    func alarmRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                jsNames: ["ios.alarm.requestPermission"],
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
                jsNames: ["ios.alarm.list"],
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
                jsNames: ["ios.alarm.schedule"],
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
                jsNames: ["ios.alarm.cancel"],
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


    func healthRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                jsNames: ["apple.health.requestPermission"],
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
                jsNames: ["apple.health.read"],
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
                jsNames: ["apple.health.write"],
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


    func homeRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                jsNames: ["apple.home.list"],
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
                jsNames: ["apple.home.writeCharacteristic"],
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


    func mediaRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                jsNames: ["apple.media.metadata"],
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
                jsNames: ["apple.media.extractFrame"],
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
                jsNames: ["apple.media.transcode"],
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
}
