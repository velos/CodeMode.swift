import Foundation

extension DefaultCapabilityRegistrationBuilder {
    func appIntentsRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                jsNames: ["apple.appIntents.list"],
                descriptor: .init(
                    id: .appIntentsList,
                    title: "List host App Intent adapters",
                    summary: "List host-registered App Intents or Shortcuts actions exposed to CodeMode.",
                    tags: ["appintents", "shortcuts", "actions", "host-adapter"],
                    example: "await apple.appIntents.list()",
                    optionalArguments: ["domain", "limit"],
                    argumentHints: [
                        "domain": "Optional host-defined action domain filter.",
                        "limit": "Maximum actions to return.",
                    ],
                    resultSummary: "Array of actions with identifier/title/summary/requiredParameters."
                ),
                handler: { args, _ in
                    try appIntents.listActions(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.appIntents.run"],
                descriptor: .init(
                    id: .appIntentsRun,
                    title: "Run host App Intent adapter",
                    summary: "Run a host-registered App Intent adapter with structured parameters.",
                    tags: ["appintents", "shortcuts", "actions", "host-adapter"],
                    example: "await apple.appIntents.run({ identifier: 'createNote', parameters: { title: 'Draft' } })",
                    requiredArguments: ["identifier"],
                    optionalArguments: ["parameters", "timeoutMs"],
                    argumentHints: [
                        "identifier": "Host-registered action identifier from apple.appIntents.list.",
                        "parameters": "Structured parameters validated by the host adapter.",
                        "timeoutMs": "Maximum wait time in milliseconds.",
                    ],
                    resultSummary: "Adapter-defined structured result."
                ),
                handler: { args, _ in
                    try appIntents.runAction(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.appIntents.donate"],
                descriptor: .init(
                    id: .appIntentsDonate,
                    title: "Donate host App Intent action",
                    summary: "Ask the host to donate a supported action to Shortcuts/Siri suggestions where feasible.",
                    tags: ["appintents", "shortcuts", "donation", "host-adapter"],
                    example: "await apple.appIntents.donate({ identifier: 'createNote', parameters: { title: 'Draft' } })",
                    requiredArguments: ["identifier"],
                    optionalArguments: ["parameters"],
                    argumentHints: [
                        "identifier": "Host-registered action identifier.",
                        "parameters": "Structured action parameters used for the donation.",
                    ],
                    resultSummary: "Object with donated/status."
                ),
                handler: { args, _ in
                    try appIntents.donateAction(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.appIntents.open"],
                descriptor: .init(
                    id: .appIntentsOpen,
                    title: "Open host App Intent surface",
                    summary: "Open a host-provided App Intent, Shortcuts, or app surface for user-mediated continuation.",
                    tags: ["appintents", "shortcuts", "open", "host-adapter"],
                    example: "await apple.appIntents.open({ identifier: 'showTask', parameters: { id: 'task-1' } })",
                    requiredArguments: ["identifier"],
                    optionalArguments: ["parameters"],
                    argumentHints: [
                        "identifier": "Host-registered open action identifier.",
                        "parameters": "Structured parameters for the host open action.",
                    ],
                    resultSummary: "Object with opened/status."
                ),
                handler: { args, _ in
                    try appIntents.openAction(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.appIntents.listHandoffs"],
                descriptor: .init(
                    id: .appIntentsHandoffsRead,
                    title: "Read App Intent handoff inbox",
                    summary: "Read bounded App Intent handoff events captured by the host app.",
                    tags: ["appintents", "shortcuts", "handoff", "inbox", "events"],
                    example: "await apple.appIntents.listHandoffs({ limit: 20 })",
                    optionalArguments: ["identifier", "limit", "afterCursor"],
                    argumentHints: [
                        "identifier": "Optional action identifier filter.",
                        "limit": "Maximum handoff events to return.",
                        "afterCursor": "Optional host-provided cursor for incremental reads.",
                    ],
                    resultSummary: "Array of handoff events with cursor/identifier/parameters/date/source."
                ),
                handler: { args, _ in
                    try appIntents.readHandoffs(arguments: args)
                }
            ),
        ]
    }


    func foundationModelsRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                jsNames: ["apple.foundationModels.getStatus"],
                descriptor: .init(
                    id: .foundationModelsStatus,
                    title: "Read Foundation Models availability",
                    summary: "Read host Foundation Models availability/status before attempting local generation.",
                    tags: ["foundationmodels", "apple-intelligence", "llm", "availability"],
                    example: "await apple.foundationModels.getStatus()",
                    resultSummary: "Object with available/status/reason/modelIdentifier when available."
                ),
                handler: { args, _ in
                    try foundationModels.status(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.foundationModels.generate"],
                descriptor: .init(
                    id: .foundationModelsGenerate,
                    title: "Generate text with Foundation Models",
                    summary: "Generate text locally through the host Foundation Models adapter when available.",
                    tags: ["foundationmodels", "apple-intelligence", "llm", "generation"],
                    example: "await apple.foundationModels.generate({ prompt: 'Summarize this note', maxTokens: 200 })",
                    requiredArguments: ["prompt"],
                    optionalArguments: ["instructions", "temperature", "maxTokens", "schemaIdentifier", "timeoutMs"],
                    argumentHints: [
                        "prompt": "Prompt text sent to the host Foundation Models session.",
                        "instructions": "Optional host-approved system instructions.",
                        "temperature": "Optional sampling temperature when supported.",
                        "maxTokens": "Optional maximum output tokens.",
                        "schemaIdentifier": "Optional host-defined output schema identifier.",
                        "timeoutMs": "Maximum generation wait time in milliseconds.",
                    ],
                    resultSummary: "Object with text/finishReason/usage when available."
                ),
                handler: { args, _ in
                    try foundationModels.generateText(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.foundationModels.extract"],
                descriptor: .init(
                    id: .foundationModelsExtract,
                    title: "Extract structured data with Foundation Models",
                    summary: "Run host-defined structured extraction or classification with Foundation Models.",
                    tags: ["foundationmodels", "apple-intelligence", "llm", "structured-output"],
                    example: "await apple.foundationModels.extract({ input: text, schemaIdentifier: 'todo' })",
                    requiredArguments: ["input"],
                    optionalArguments: ["schema", "schemaIdentifier", "instructions", "timeoutMs"],
                    argumentHints: [
                        "input": "Input text to classify or extract from.",
                        "schema": "Optional JSON schema object accepted by the host adapter.",
                        "schemaIdentifier": "Preferred host-defined schema identifier.",
                        "instructions": "Optional task-specific instructions.",
                        "timeoutMs": "Maximum extraction wait time in milliseconds.",
                    ],
                    resultSummary: "Object with values/classification/confidence/schemaIdentifier."
                ),
                handler: { args, _ in
                    try foundationModels.extract(arguments: args)
                }
            ),
        ]
    }


    func activityRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                jsNames: ["apple.activity.list"],
                descriptor: .init(
                    id: .activityList,
                    title: "List Live Activities",
                    summary: "List host-registered ActivityKit Live Activities visible to CodeMode.",
                    tags: ["activitykit", "live-activities", "host-adapter"],
                    example: "await apple.activity.list()",
                    optionalArguments: ["activityType", "limit"],
                    resultSummary: "Array of activities with identifier/activityType/state/contentState/attributes."
                ),
                handler: { args, _ in
                    try activity.listActivities(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.activity.start"],
                descriptor: .init(
                    id: .activityStart,
                    title: "Start Live Activity",
                    summary: "Start a host-registered ActivityKit Live Activity adapter.",
                    tags: ["activitykit", "live-activities", "host-adapter"],
                    example: "await apple.activity.start({ activityType: 'delivery', attributes: {}, contentState: {} })",
                    requiredArguments: ["activityType", "attributes"],
                    optionalArguments: ["contentState", "pushType", "staleDate"],
                    argumentHints: [
                        "activityType": "Host-registered activity adapter type.",
                        "attributes": "Adapter-defined immutable attributes.",
                        "contentState": "Adapter-defined mutable content state.",
                        "pushType": "Optional push token request mode when the adapter supports remote updates.",
                        "staleDate": "Optional ISO8601 stale date.",
                    ],
                    resultSummary: "Object with identifier/activityType/state/pushToken when available."
                ),
                handler: { args, _ in
                    try activity.startActivity(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.activity.update"],
                descriptor: .init(
                    id: .activityUpdate,
                    title: "Update Live Activity",
                    summary: "Update an existing host-registered Live Activity content state.",
                    tags: ["activitykit", "live-activities", "host-adapter"],
                    example: "await apple.activity.update({ identifier: 'activity-1', contentState: { progress: 0.7 } })",
                    requiredArguments: ["identifier", "contentState"],
                    optionalArguments: ["alert", "staleDate"],
                    resultSummary: "Object with identifier/updated/state."
                ),
                handler: { args, _ in
                    try activity.updateActivity(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.activity.end"],
                descriptor: .init(
                    id: .activityEnd,
                    title: "End Live Activity",
                    summary: "End a host-registered Live Activity, optionally with final content state.",
                    tags: ["activitykit", "live-activities", "host-adapter"],
                    example: "await apple.activity.end({ identifier: 'activity-1', dismissalPolicy: 'immediate' })",
                    requiredArguments: ["identifier"],
                    optionalArguments: ["contentState", "dismissalPolicy"],
                    resultSummary: "Object with identifier/ended/state."
                ),
                handler: { args, _ in
                    try activity.endActivity(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.activity.getPushToken"],
                descriptor: .init(
                    id: .activityPushTokenRead,
                    title: "Read Live Activity push token",
                    summary: "Read a Live Activity push token when the host adapter supports push updates.",
                    tags: ["activitykit", "live-activities", "push-token"],
                    example: "await apple.activity.getPushToken({ identifier: 'activity-1' })",
                    requiredArguments: ["identifier"],
                    resultSummary: "Object with identifier/pushToken/environment."
                ),
                handler: { args, _ in
                    try activity.readPushToken(arguments: args)
                }
            ),
        ]
    }


    func mapsRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                jsNames: ["apple.maps.geocode"],
                descriptor: .init(
                    id: .mapsGeocode,
                    title: "Geocode address",
                    summary: "Resolve an address or place text to coordinate candidates through MapKit.",
                    tags: ["maps", "mapkit", "geocode", "location"],
                    example: "await apple.maps.geocode({ address: '1 Infinite Loop, Cupertino', limit: 3 })",
                    requiredArguments: ["address"],
                    optionalArguments: ["region", "limit"],
                    argumentHints: [
                        "address": "Address or place text to geocode.",
                        "region": "Optional search bias region object.",
                        "limit": "Maximum coordinate candidates.",
                    ],
                    resultSummary: "Array of placemarks with name/address/latitude/longitude."
                ),
                handler: { args, _ in
                    try maps.geocode(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.maps.reverseGeocode"],
                descriptor: .init(
                    id: .mapsReverseGeocode,
                    title: "Reverse geocode coordinates",
                    summary: "Resolve latitude/longitude into address candidates through MapKit.",
                    tags: ["maps", "mapkit", "reverse-geocode", "location"],
                    example: "await apple.maps.reverseGeocode({ latitude: 37.3318, longitude: -122.0312 })",
                    requiredArguments: ["latitude", "longitude"],
                    optionalArguments: ["locale"],
                    resultSummary: "Array of placemarks with name/address/latitude/longitude."
                ),
                handler: { args, _ in
                    try maps.reverseGeocode(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.maps.search"],
                descriptor: .init(
                    id: .mapsSearch,
                    title: "Search local map items",
                    summary: "Search for local businesses, addresses, or points of interest through MapKit.",
                    tags: ["maps", "mapkit", "local-search", "places"],
                    example: "await apple.maps.search({ query: 'coffee near me', limit: 5 })",
                    requiredArguments: ["query"],
                    optionalArguments: ["region", "resultTypes", "limit"],
                    argumentHints: [
                        "query": "Search query string.",
                        "region": "Optional coordinate region object for local bias.",
                        "resultTypes": "Optional host-supported result type filters.",
                        "limit": "Maximum map items.",
                    ],
                    resultSummary: "Array of map items with name/address/category/latitude/longitude/url."
                ),
                handler: { args, _ in
                    try maps.search(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.maps.routeEstimate"],
                descriptor: .init(
                    id: .mapsRouteEstimate,
                    title: "Estimate route",
                    summary: "Estimate route distance and travel time between two coordinates or map items.",
                    tags: ["maps", "mapkit", "directions", "route"],
                    example: "await apple.maps.routeEstimate({ origin: { latitude: 37.33, longitude: -122.03 }, destination: { latitude: 37.77, longitude: -122.42 }, transportType: 'automobile' })",
                    requiredArguments: ["origin", "destination"],
                    optionalArguments: ["transportType", "departureDate", "arrivalDate"],
                    argumentHints: [
                        "origin": "Coordinate or map item object.",
                        "destination": "Coordinate or map item object.",
                        "transportType": "automobile (default), walking, or transit when supported.",
                    ],
                    resultSummary: "Object with distanceMeters/expectedTravelTimeSeconds/transportType."
                ),
                handler: { args, _ in
                    try maps.routeEstimate(arguments: args)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.maps.open"],
                descriptor: .init(
                    id: .mapsOpen,
                    title: "Open Maps",
                    summary: "Open Apple Maps with coordinates, a query, URL, or directions in a user-mediated handoff.",
                    tags: ["maps", "mapkit", "open", "directions"],
                    example: "await apple.maps.open({ query: 'Apple Park' })",
                    optionalArguments: ["query", "url", "latitude", "longitude", "destination", "transportType"],
                    argumentHints: [
                        "query": "Place/search query to open.",
                        "url": "Optional maps URL to open.",
                        "latitude": "Latitude when opening coordinates.",
                        "longitude": "Longitude when opening coordinates.",
                        "destination": "Optional destination object for directions.",
                    ],
                    resultSummary: "Object with opened/target."
                ),
                handler: { args, _ in
                    try maps.open(arguments: args)
                }
            ),
        ]
    }
}
