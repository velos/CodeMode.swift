import Foundation

// MARK: - Constrained argument values

enum ActivityDismissalPolicy: String, CodeModeStringEnum {
    case `default`
    case immediate
}

enum MapsTransportType: String, CodeModeStringEnum {
    case automobile
    case walking
    case transit
    case any
}

// MARK: - App Intents

@BuiltInCodeMode(.appIntentsList, path: "apple.appIntents.list")
struct AppIntentsListTool: BuiltInCodeModeTool {
    static let codeModeTitle = "List host App Intent adapters"
    static let codeModeSummary = "List host-registered App Intents or Shortcuts actions exposed to CodeMode."
    static let codeModeTags = ["appintents", "shortcuts", "actions", "host-adapter"]
    static let codeModeExample = "await apple.appIntents.list()"
    static let codeModeResultSummary = "Array of actions with identifier/title/summary/requiredParameters."

    struct Arguments: Sendable {
        @ToolParam("Optional host-defined action domain filter.")
        var domain: String?
        @ToolParam("Maximum actions to return.")
        var limit: Int?
        var raw: [String: JSONValue]
    }

    let appIntents: AppIntentsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try appIntents.listActions(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.appIntentsRun, path: "apple.appIntents.run")
struct AppIntentsRunTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Run host App Intent adapter"
    static let codeModeSummary = "Run a host-registered App Intent adapter with structured parameters."
    static let codeModeTags = ["appintents", "shortcuts", "actions", "host-adapter"]
    static let codeModeExample = "await apple.appIntents.run({ identifier: 'createNote', parameters: { title: 'Draft' } })"
    static let codeModeResultSummary = "Adapter-defined structured result."

    struct Arguments: Sendable {
        @ToolParam("Host-registered action identifier from apple.appIntents.list.")
        var identifier: String
        @ToolParam("Structured parameters validated by the host adapter.")
        var parameters: [String: JSONValue]?
        @ToolParam("Maximum wait time in milliseconds.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let appIntents: AppIntentsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try appIntents.runAction(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.appIntentsDonate, path: "apple.appIntents.donate")
struct AppIntentsDonateTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Donate host App Intent action"
    static let codeModeSummary = "Ask the host to donate a supported action to Shortcuts/Siri suggestions where feasible."
    static let codeModeTags = ["appintents", "shortcuts", "donation", "host-adapter"]
    static let codeModeExample = "await apple.appIntents.donate({ identifier: 'createNote', parameters: { title: 'Draft' } })"
    static let codeModeResultSummary = "Object with donated/status."

    struct Arguments: Sendable {
        @ToolParam("Host-registered action identifier.")
        var identifier: String
        @ToolParam("Structured action parameters used for the donation.")
        var parameters: [String: JSONValue]?
        var raw: [String: JSONValue]
    }

    let appIntents: AppIntentsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try appIntents.donateAction(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.appIntentsOpen, path: "apple.appIntents.open")
struct AppIntentsOpenTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Open host App Intent surface"
    static let codeModeSummary = "Open a host-provided App Intent, Shortcuts, or app surface for user-mediated continuation."
    static let codeModeTags = ["appintents", "shortcuts", "open", "host-adapter"]
    static let codeModeExample = "await apple.appIntents.open({ identifier: 'showTask', parameters: { id: 'task-1' } })"
    static let codeModeResultSummary = "Object with opened/status."

    struct Arguments: Sendable {
        @ToolParam("Host-registered open action identifier.")
        var identifier: String
        @ToolParam("Structured parameters for the host open action.")
        var parameters: [String: JSONValue]?
        var raw: [String: JSONValue]
    }

    let appIntents: AppIntentsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try appIntents.openAction(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.appIntentsHandoffsRead, path: "apple.appIntents.listHandoffs")
struct AppIntentsHandoffsReadTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Read App Intent handoff inbox"
    static let codeModeSummary = "Read bounded App Intent handoff events captured by the host app."
    static let codeModeTags = ["appintents", "shortcuts", "handoff", "inbox", "events"]
    static let codeModeExample = "await apple.appIntents.listHandoffs({ limit: 20 })"
    static let codeModeResultSummary = "Array of handoff events with cursor/identifier/parameters/date/source."

    struct Arguments: Sendable {
        @ToolParam("Optional action identifier filter.")
        var identifier: String?
        @ToolParam("Maximum handoff events to return.")
        var limit: Int?
        @ToolParam("Optional host-provided cursor for incremental reads.")
        var afterCursor: String?
        var raw: [String: JSONValue]
    }

    let appIntents: AppIntentsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try appIntents.readHandoffs(arguments: arguments.raw)
    }
}

// MARK: - Foundation Models

@BuiltInCodeMode(.foundationModelsStatus, path: "apple.foundationModels.getStatus")
struct FoundationModelsStatusTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Read Foundation Models availability"
    static let codeModeSummary = "Read host Foundation Models availability/status before attempting local generation."
    static let codeModeTags = ["foundationmodels", "apple-intelligence", "llm", "availability"]
    static let codeModeExample = "await apple.foundationModels.getStatus()"
    static let codeModeResultSummary = "Object with available/status/reason/modelIdentifier when available."

    struct Arguments: Sendable {
        var raw: [String: JSONValue]
    }

    let foundationModels: FoundationModelsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try foundationModels.status(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.foundationModelsGenerate, path: "apple.foundationModels.generate")
struct FoundationModelsGenerateTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Generate text with Foundation Models"
    static let codeModeSummary = "Generate text locally through the host Foundation Models adapter when available."
    static let codeModeTags = ["foundationmodels", "apple-intelligence", "llm", "generation"]
    static let codeModeExample = "await apple.foundationModels.generate({ prompt: 'Summarize this note', maxTokens: 200 })"
    static let codeModeResultSummary = "Object with text/finishReason/usage when available."

    struct Arguments: Sendable {
        // `prompt` is absent from the argument-type inference table, so its
        // historical advertised type is `any` — declared as JSONValue to match.
        @ToolParam("Prompt text sent to the host Foundation Models session.")
        var prompt: JSONValue
        @ToolParam("Optional host-approved system instructions.")
        var instructions: String?
        @ToolParam("Optional sampling temperature when supported.")
        var temperature: Double?
        @ToolParam("Optional maximum output tokens.")
        var maxTokens: Int?
        @ToolParam("Optional host-defined output schema identifier.")
        var schemaIdentifier: String?
        @ToolParam("Maximum generation wait time in milliseconds.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let foundationModels: FoundationModelsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try foundationModels.generateText(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.foundationModelsExtract, path: "apple.foundationModels.extract")
struct FoundationModelsExtractTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Extract structured data with Foundation Models"
    static let codeModeSummary = "Run host-defined structured extraction or classification with Foundation Models."
    static let codeModeTags = ["foundationmodels", "apple-intelligence", "llm", "structured-output"]
    static let codeModeExample = "await apple.foundationModels.extract({ input: text, schemaIdentifier: 'todo' })"
    static let codeModeResultSummary = "Object with values/classification/confidence/schemaIdentifier."

    struct Arguments: Sendable {
        @ToolParam("Input text to classify or extract from.")
        var input: String
        @ToolParam("Optional JSON schema object accepted by the host adapter.")
        var schema: [String: JSONValue]?
        @ToolParam("Preferred host-defined schema identifier.")
        var schemaIdentifier: String?
        @ToolParam("Optional task-specific instructions.")
        var instructions: String?
        @ToolParam("Maximum extraction wait time in milliseconds.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let foundationModels: FoundationModelsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try foundationModels.extract(arguments: arguments.raw)
    }
}

// MARK: - Live Activities

@BuiltInCodeMode(.activityList, path: "apple.activity.list")
struct ActivityListTool: BuiltInCodeModeTool {
    static let codeModeTitle = "List Live Activities"
    static let codeModeSummary = "List host-registered ActivityKit Live Activities visible to CodeMode."
    static let codeModeTags = ["activitykit", "live-activities", "host-adapter"]
    static let codeModeExample = "await apple.activity.list()"
    static let codeModeResultSummary = "Array of activities with identifier/activityType/state/contentState/attributes."

    struct Arguments: Sendable {
        @ToolParam("Optional host-registered activity adapter type filter.")
        var activityType: String?
        @ToolParam("Maximum activities to return.")
        var limit: Int?
        var raw: [String: JSONValue]
    }

    let activity: ActivityBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try activity.listActivities(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.activityStart, path: "apple.activity.start")
struct ActivityStartTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Start Live Activity"
    static let codeModeSummary = "Start a host-registered ActivityKit Live Activity adapter."
    static let codeModeTags = ["activitykit", "live-activities", "host-adapter"]
    static let codeModeExample = "await apple.activity.start({ activityType: 'delivery', attributes: {}, contentState: {} })"
    static let codeModeResultSummary = "Object with identifier/activityType/state/pushToken when available."

    struct Arguments: Sendable {
        @ToolParam("Host-registered activity adapter type.")
        var activityType: String
        @ToolParam("Adapter-defined immutable attributes.")
        var attributes: [String: JSONValue]
        @ToolParam("Adapter-defined mutable content state.")
        var contentState: [String: JSONValue]?
        @ToolParam("Optional push token request mode when the adapter supports remote updates.")
        var pushType: String?
        @ToolParam("Optional ISO8601 stale date.")
        var staleDate: String?
        var raw: [String: JSONValue]
    }

    let activity: ActivityBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try activity.startActivity(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.activityUpdate, path: "apple.activity.update")
struct ActivityUpdateTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Update Live Activity"
    static let codeModeSummary = "Update an existing host-registered Live Activity content state."
    static let codeModeTags = ["activitykit", "live-activities", "host-adapter"]
    static let codeModeExample = "await apple.activity.update({ identifier: 'activity-1', contentState: { progress: 0.7 } })"
    static let codeModeResultSummary = "Object with identifier/updated/state."

    struct Arguments: Sendable {
        @ToolParam("Live Activity identifier from apple.activity.list/start.")
        var identifier: String
        @ToolParam("Adapter-defined mutable content state.")
        var contentState: [String: JSONValue]
        @ToolParam("Optional alert configuration object for the update.")
        var alert: [String: JSONValue]?
        @ToolParam("Optional ISO8601 stale date.")
        var staleDate: String?
        var raw: [String: JSONValue]
    }

    let activity: ActivityBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try activity.updateActivity(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.activityEnd, path: "apple.activity.end")
struct ActivityEndTool: BuiltInCodeModeTool {
    static let codeModeTitle = "End Live Activity"
    static let codeModeSummary = "End a host-registered Live Activity, optionally with final content state."
    static let codeModeTags = ["activitykit", "live-activities", "host-adapter"]
    static let codeModeExample = "await apple.activity.end({ identifier: 'activity-1', dismissalPolicy: 'immediate' })"
    static let codeModeResultSummary = "Object with identifier/ended/state."

    struct Arguments: Sendable {
        @ToolParam("Live Activity identifier from apple.activity.list/start.")
        var identifier: String
        @ToolParam("Optional final adapter-defined content state.")
        var contentState: [String: JSONValue]?
        @ToolParam("default (default) or immediate.")
        var dismissalPolicy: ActivityDismissalPolicy?
        var raw: [String: JSONValue]
    }

    let activity: ActivityBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try activity.endActivity(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.activityPushTokenRead, path: "apple.activity.getPushToken")
struct ActivityPushTokenReadTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Read Live Activity push token"
    static let codeModeSummary = "Read a Live Activity push token when the host adapter supports push updates."
    static let codeModeTags = ["activitykit", "live-activities", "push-token"]
    static let codeModeExample = "await apple.activity.getPushToken({ identifier: 'activity-1' })"
    static let codeModeResultSummary = "Object with identifier/pushToken/environment."

    struct Arguments: Sendable {
        @ToolParam("Live Activity identifier from apple.activity.list/start.")
        var identifier: String
        var raw: [String: JSONValue]
    }

    let activity: ActivityBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try activity.readPushToken(arguments: arguments.raw)
    }
}

// MARK: - Maps

@BuiltInCodeMode(.mapsGeocode, path: "apple.maps.geocode")
struct MapsGeocodeTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Geocode address"
    static let codeModeSummary = "Resolve an address or place text to coordinate candidates through MapKit."
    static let codeModeTags = ["maps", "mapkit", "geocode", "location"]
    static let codeModeExample = "await apple.maps.geocode({ address: '1 Infinite Loop, Cupertino', limit: 3 })"
    static let codeModeResultSummary = "Array of placemarks with name/address/latitude/longitude."

    struct Arguments: Sendable {
        @ToolParam("Address or place text to geocode.")
        var address: String
        @ToolParam("Optional search bias region object.")
        var region: [String: JSONValue]?
        @ToolParam("Maximum coordinate candidates.")
        var limit: Int?
        var raw: [String: JSONValue]
    }

    let maps: MapsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try maps.geocode(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.mapsReverseGeocode, path: "apple.maps.reverseGeocode")
struct MapsReverseGeocodeTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Reverse geocode coordinates"
    static let codeModeSummary = "Resolve latitude/longitude into address candidates through MapKit."
    static let codeModeTags = ["maps", "mapkit", "reverse-geocode", "location"]
    static let codeModeExample = "await apple.maps.reverseGeocode({ latitude: 37.3318, longitude: -122.0312 })"
    static let codeModeResultSummary = "Array of placemarks with name/address/latitude/longitude."

    struct Arguments: Sendable {
        @ToolParam("Latitude in decimal degrees.")
        var latitude: Double
        @ToolParam("Longitude in decimal degrees.")
        var longitude: Double
        @ToolParam("Optional BCP-47 locale identifier for result localization.")
        var locale: String?
        var raw: [String: JSONValue]
    }

    let maps: MapsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try maps.reverseGeocode(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.mapsSearch, path: "apple.maps.search")
struct MapsSearchTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Search local map items"
    static let codeModeSummary = "Search for local businesses, addresses, or points of interest through MapKit."
    static let codeModeTags = ["maps", "mapkit", "local-search", "places"]
    static let codeModeExample = "await apple.maps.search({ query: 'coffee near me', limit: 5 })"
    static let codeModeResultSummary = "Array of map items with name/address/category/latitude/longitude/url."

    struct Arguments: Sendable {
        @ToolParam("Search query string.")
        var query: String
        @ToolParam("Optional coordinate region object for local bias.")
        var region: [String: JSONValue]?
        @ToolParam("Optional host-supported result type filters.")
        var resultTypes: [String]?
        @ToolParam("Maximum map items.")
        var limit: Int?
        var raw: [String: JSONValue]
    }

    let maps: MapsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try maps.search(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.mapsRouteEstimate, path: "apple.maps.routeEstimate")
struct MapsRouteEstimateTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Estimate route"
    static let codeModeSummary = "Estimate route distance and travel time between two coordinates or map items."
    static let codeModeTags = ["maps", "mapkit", "directions", "route"]
    static let codeModeExample = "await apple.maps.routeEstimate({ origin: { latitude: 37.33, longitude: -122.03 }, destination: { latitude: 37.77, longitude: -122.42 }, transportType: 'automobile' })"
    static let codeModeResultSummary = "Object with distanceMeters/expectedTravelTimeSeconds/transportType."

    struct Arguments: Sendable {
        @ToolParam("Coordinate or map item object.")
        var origin: [String: JSONValue]
        @ToolParam("Coordinate or map item object.")
        var destination: [String: JSONValue]
        @ToolParam("automobile (default), walking, or transit when supported.")
        var transportType: MapsTransportType?
        @ToolParam("Optional ISO8601 departure date.")
        var departureDate: String?
        @ToolParam("Optional ISO8601 arrival date.")
        var arrivalDate: String?
        var raw: [String: JSONValue]
    }

    let maps: MapsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try maps.routeEstimate(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.mapsOpen, path: "apple.maps.open")
struct MapsOpenTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Open Maps"
    static let codeModeSummary = "Open Apple Maps with coordinates, a query, URL, or directions in a user-mediated handoff."
    static let codeModeTags = ["maps", "mapkit", "open", "directions"]
    static let codeModeExample = "await apple.maps.open({ query: 'Apple Park' })"
    static let codeModeResultSummary = "Object with opened/target."

    struct Arguments: Sendable {
        @ToolParam("Place/search query to open.")
        var query: String?
        @ToolParam("Optional maps URL to open.")
        var url: String?
        @ToolParam("Latitude when opening coordinates.")
        var latitude: Double?
        @ToolParam("Longitude when opening coordinates.")
        var longitude: Double?
        @ToolParam("Optional destination object for directions.")
        var destination: [String: JSONValue]?
        @ToolParam("automobile (default), walking, transit, or any.")
        var transportType: MapsTransportType?
        var raw: [String: JSONValue]
    }

    let maps: MapsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try maps.open(arguments: arguments.raw)
    }
}
