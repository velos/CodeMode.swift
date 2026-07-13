import Foundation

/// Constrained playback action; host MusicClient stays authoritative for
/// semantics, so only the advertised value set is enforced here.
enum MusicPlaybackAction: String, CodeModeStringEnum {
    case play
    case pause
    case stop
    case skipToNext
    case skipToPrevious
    case playCatalog
    case playLibrary
}

// MARK: - Music

@BuiltInCodeMode(.musicPermissionRequest, path: "apple.music.requestPermission")
struct MusicPermissionRequestTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Request Music permission"
    static let codeModeSummary = "Request Apple Music/media-library permission before library or playback actions."
    static let codeModeTags = ["music", "musickit", "permission"]
    static let codeModeExample = "await apple.music.requestPermission()"
    static let codeModeResultSummary = "Object with status/granted."

    struct Arguments: Sendable {}

    let music: MusicBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try music.requestPermission(context: context)
    }
}

@BuiltInCodeMode(.musicSubscriptionStatus, path: "apple.music.getSubscriptionStatus")
struct MusicSubscriptionStatusTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Read Music subscription status"
    static let codeModeSummary = "Read MusicKit subscription/capability status exposed by the host."
    static let codeModeTags = ["music", "musickit", "subscription", "catalog"]
    static let codeModeExample = "await apple.music.getSubscriptionStatus()"
    static let codeModeResultSummary = "Object with canPlayCatalogContent/hasCloudLibraryEnabled/status."

    struct Arguments: Sendable {
        var raw: [String: JSONValue]
    }

    let music: MusicBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try music.subscriptionStatus(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.musicCatalogSearch, path: "apple.music.search")
struct MusicCatalogSearchTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Search Music catalog"
    static let codeModeSummary = "Search the Apple Music catalog for songs, albums, artists, playlists, or stations."
    static let codeModeTags = ["music", "musickit", "catalog", "search"]
    static let codeModeExample = "await apple.music.search({ term: 'Miles Davis', types: ['artists', 'albums'], limit: 5 })"
    static let codeModeResultSummary = "Object grouped by result type with catalog identifiers and metadata."

    struct Arguments: Sendable {
        @ToolParam("Catalog search term.")
        var term: String
        @ToolParam("Optional array such as songs, albums, artists, playlists, stations.")
        var types: [String]?
        @ToolParam("Maximum results.")
        var limit: Int?
        @ToolParam("Optional storefront country code.")
        var countryCode: String?
        var raw: [String: JSONValue]
    }

    let music: MusicBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try music.searchCatalog(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.musicCatalogDetails, path: "apple.music.getDetails")
struct MusicCatalogDetailsTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Read Music catalog details"
    static let codeModeSummary = "Read details for a catalog item identifier through MusicKit."
    static let codeModeTags = ["music", "musickit", "catalog", "details"]
    static let codeModeExample = "await apple.music.getDetails({ identifier: '123', type: 'albums' })"
    static let codeModeResultSummary = "Catalog item details object."

    struct Arguments: Sendable {
        @ToolParam("Music catalog item identifier.")
        var identifier: String
        @ToolParam("Catalog type such as songs, albums, artists, playlists, or stations.")
        var type: String?
        @ToolParam("Optional storefront country code.")
        var countryCode: String?
        var raw: [String: JSONValue]
    }

    let music: MusicBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try music.catalogDetails(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.musicLibraryRead, path: "apple.music.readLibrary")
struct MusicLibraryReadTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Read Music library"
    static let codeModeSummary = "Read the user's Music library playlists or items after Music permission is granted."
    static let codeModeTags = ["music", "musickit", "library"]
    static let codeModeExample = "await apple.music.readLibrary({ type: 'playlists', limit: 20 })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.music]
    static let codeModeResultSummary = "Array of library items with identifiers and metadata."

    struct Arguments: Sendable {
        @ToolParam("Library type such as playlists, songs, albums, or artists.")
        var type: String?
        @ToolParam("Maximum library items.")
        var limit: Int?
        var raw: [String: JSONValue]
    }

    let music: MusicBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try music.readLibrary(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.musicPlaylistWrite, path: "apple.music.writePlaylist")
struct MusicPlaylistWriteTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Write Music playlist"
    static let codeModeSummary = "Create or update a user-library playlist through a host MusicKit adapter."
    static let codeModeTags = ["music", "musickit", "library", "playlist", "write"]
    static let codeModeExample = "await apple.music.writePlaylist({ name: 'Focus', catalogIDs: ['song-id'] })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.music]
    static let codeModeResultSummary = "Object with playlistID/name/written."

    struct Arguments: Sendable {
        // `name` is absent from the argument-type inference table, so its
        // historical advertised type is `any` — declared as JSONValue to match.
        @ToolParam("Playlist name.")
        var name: JSONValue
        @ToolParam("Optional existing playlist identifier to update.")
        var playlistID: String?
        @ToolParam("Optional catalog song identifiers to add.")
        var catalogIDs: [String]?
        @ToolParam("Optional library song identifiers to add.")
        var libraryIDs: [String]?
        @ToolParam("Optional playlist description.")
        var description: String?
        var raw: [String: JSONValue]
    }

    let music: MusicBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try music.writePlaylist(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.musicPlaybackControl, path: "apple.music.play")
struct MusicPlaybackControlTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Control Music playback"
    static let codeModeSummary = "Control Music playback queue through a user-authorized host adapter."
    static let codeModeTags = ["music", "musickit", "playback", "queue"]
    static let codeModeExample = "await apple.music.play({ action: 'playCatalog', catalogID: 'song-id' })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.music]
    static let codeModeResultSummary = "Object with action/status/currentItem when available."

    struct Arguments: Sendable {
        @ToolParam("Host-supported action such as play, pause, stop, skipToNext, playCatalog, or playLibrary.")
        var action: MusicPlaybackAction
        @ToolParam("Optional catalog item identifier.")
        var catalogID: String?
        @ToolParam("Optional library item identifier.")
        var libraryID: String?
        @ToolParam("Optional queue definition approved by the host adapter.")
        var queue: [String: JSONValue]?
        @ToolParam("Whether playback should begin immediately; host-adapter defined.")
        var startPlaying: Bool?
        var raw: [String: JSONValue]
    }

    let music: MusicBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try music.controlPlayback(arguments: arguments.raw, context: context)
    }
}

// MARK: - PassKit / Wallet

@BuiltInCodeMode(.passKitWalletStatus, path: "apple.wallet.getStatus")
struct PassKitWalletStatusTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Read Wallet status"
    static let codeModeSummary = "Read PassKit Wallet availability and pass-library access status."
    static let codeModeTags = ["passkit", "wallet", "passes"]
    static let codeModeExample = "await apple.wallet.getStatus()"
    static let codeModeResultSummary = "Object with available/canAddPasses/canPresentPasses."

    struct Arguments: Sendable {
        var raw: [String: JSONValue]
    }

    let passKit: PassKitBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try passKit.walletStatus(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.passKitPassesRead, path: "apple.wallet.listPasses")
struct PassKitPassesReadTool: BuiltInCodeModeTool {
    static let codeModeTitle = "List Wallet passes"
    static let codeModeSummary = "List Wallet passes accessible to the host app through PassKit."
    static let codeModeTags = ["passkit", "wallet", "passes", "read"]
    static let codeModeExample = "await apple.wallet.listPasses({ limit: 20 })"
    static let codeModeResultSummary = "Array of passes with passTypeIdentifier/serialNumber/organizationName/description."

    struct Arguments: Sendable {
        @ToolParam("Optional pass type filter.")
        var passTypeIdentifier: String?
        @ToolParam("Optional serial number filter.")
        var serialNumber: String?
        @ToolParam("Maximum accessible passes.")
        var limit: Int?
        var raw: [String: JSONValue]
    }

    let passKit: PassKitBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try passKit.listPasses(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.passKitPassAdd, path: "apple.wallet.addPass")
struct PassKitPassAddTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Add Wallet pass"
    static let codeModeSummary = "Present user-mediated UI to add a sandbox .pkpass file to Wallet."
    static let codeModeTags = ["passkit", "wallet", "passes", "add", "system-ui"]
    static let codeModeExample = "await apple.wallet.addPass({ path: 'tmp:ticket.pkpass' })"
    static let codeModeResultSummary = "Object with action/added/passTypeIdentifier/serialNumber."

    struct Arguments: Sendable {
        @ToolParam("Sandbox path to a .pkpass file.")
        var path: String
        @ToolParam("Optional timeout for user-mediated add-pass UI.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let passKit: PassKitBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try passKit.addPass(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.passKitPassPresent, path: "apple.wallet.presentPass")
struct PassKitPassPresentTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Present Wallet pass"
    static let codeModeSummary = "Present user-mediated details for an accessible Wallet pass."
    static let codeModeTags = ["passkit", "wallet", "passes", "system-ui"]
    static let codeModeExample = "await apple.wallet.presentPass({ identifier: 'pass-id' })"
    static let codeModeResultSummary = "Object with action/presented/identifier."

    struct Arguments: Sendable {
        @ToolParam("Accessible Wallet pass identifier from apple.wallet.listPasses.")
        var identifier: String
        @ToolParam("Optional timeout for user-mediated pass presentation.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let passKit: PassKitBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try passKit.presentPass(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.passKitApplePayStatus, path: "apple.wallet.canMakePayments")
struct PassKitApplePayStatusTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Read Apple Pay status"
    static let codeModeSummary = "Read Apple Pay capability using host merchant configuration; no merchant setup is accepted from JavaScript."
    static let codeModeTags = ["passkit", "apple-pay", "payments", "safety"]
    static let codeModeExample = "await apple.wallet.canMakePayments()"
    static let codeModeResultSummary = "Object with canMakePayments/canMakePaymentsUsingNetworks."

    struct Arguments: Sendable {
        @ToolParam("Optional supported payment networks to test against host merchant configuration.")
        var networks: [String]?
        var raw: [String: JSONValue]
    }

    let passKit: PassKitBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try passKit.applePayStatus(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.passKitApplePayPresent, path: "apple.wallet.presentPayment")
struct PassKitApplePayPresentTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Present Apple Pay request"
    static let codeModeSummary = "Present a host-defined Apple Pay payment request using host merchant configuration after explicit user-visible confirmation."
    static let codeModeTags = ["passkit", "apple-pay", "payments", "system-ui", "safety"]
    static let codeModeExample = "await apple.wallet.presentPayment({ paymentRequestID: 'checkout-123', confirmed: true })"
    static let codeModeResultSummary = "Object with action/authorized/paymentRequestID/status."

    struct Arguments: Sendable {
        @ToolParam("Host-defined payment request identifier using host merchant configuration; arbitrary merchant setup is not accepted from JavaScript.")
        var paymentRequestID: String
        @ToolParam("Must be true after explicit user-visible confirmation before presenting Apple Pay.")
        var confirmed: Bool
        @ToolParam("Optional timeout for user-mediated Apple Pay UI.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let passKit: PassKitBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try passKit.presentApplePay(arguments: arguments.raw)
    }
}

// MARK: - StoreKit

@BuiltInCodeMode(.storeKitProductsRead, path: "apple.storekit.listProducts")
struct StoreKitProductsReadTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Read StoreKit products"
    static let codeModeSummary = "Read StoreKit product metadata for host-configured product identifiers."
    static let codeModeTags = ["storekit", "commerce", "products"]
    static let codeModeExample = "await apple.storekit.listProducts({ productIDs: ['pro.monthly'] })"
    static let codeModeResultSummary = "Array of products with id/displayName/description/price/type."

    struct Arguments: Sendable {
        @ToolParam("Array of host-configured StoreKit product identifiers.")
        var productIDs: [String]
        var raw: [String: JSONValue]
    }

    let storeKit: StoreKitBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try storeKit.products(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.storeKitEntitlementsRead, path: "apple.storekit.listEntitlements")
struct StoreKitEntitlementsReadTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Read StoreKit entitlements"
    static let codeModeSummary = "Read current StoreKit entitlements and verified transaction state."
    static let codeModeTags = ["storekit", "commerce", "entitlements"]
    static let codeModeExample = "await apple.storekit.listEntitlements()"
    static let codeModeResultSummary = "Array of current entitlements with productID/transactionID/expirationDate."

    struct Arguments: Sendable {
        var raw: [String: JSONValue]
    }

    let storeKit: StoreKitBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try storeKit.currentEntitlements(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.storeKitPurchase, path: "apple.storekit.purchase")
struct StoreKitPurchaseTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Purchase StoreKit product"
    static let codeModeSummary = "Present StoreKit purchase UI for a host-configured product after explicit user-visible confirmation."
    static let codeModeTags = ["storekit", "commerce", "purchase", "safety"]
    static let codeModeExample = "await apple.storekit.purchase({ productID: 'pro.monthly', confirmed: true })"
    static let codeModeResultSummary = "Object with status/productID/transactionID when completed."

    struct Arguments: Sendable {
        @ToolParam("Host-configured StoreKit product identifier.")
        var productID: String
        @ToolParam("Must be true after explicit user-visible confirmation before purchase UI is presented.")
        var confirmed: Bool
        @ToolParam("Optional UUID string for StoreKit appAccountToken.")
        var appAccountToken: String?
        var raw: [String: JSONValue]
    }

    let storeKit: StoreKitBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try storeKit.purchase(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.storeKitRestore, path: "apple.storekit.restore")
struct StoreKitRestoreTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Restore StoreKit purchases"
    static let codeModeSummary = "Trigger StoreKit restore/sync after explicit user-visible confirmation."
    static let codeModeTags = ["storekit", "commerce", "restore", "safety"]
    static let codeModeExample = "await apple.storekit.restore({ confirmed: true })"
    static let codeModeResultSummary = "Object with restored/status."

    struct Arguments: Sendable {
        @ToolParam("Must be true after explicit user-visible confirmation before restore starts.")
        var confirmed: Bool
        var raw: [String: JSONValue]
    }

    let storeKit: StoreKitBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try storeKit.restore(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.storeKitTransactionsRead, path: "apple.storekit.listTransactions")
struct StoreKitTransactionsReadTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Read StoreKit transaction inbox"
    static let codeModeSummary = "Read bounded transaction updates captured by the host StoreKit adapter."
    static let codeModeTags = ["storekit", "commerce", "transactions", "inbox", "events"]
    static let codeModeExample = "await apple.storekit.listTransactions({ limit: 20 })"
    static let codeModeResultSummary = "Array of transaction events with cursor/productID/transactionID/status/date."

    struct Arguments: Sendable {
        @ToolParam("Maximum transaction updates to return.")
        var limit: Int?
        @ToolParam("Optional product filter.")
        var productID: String?
        @ToolParam("Optional host-provided cursor for incremental reads.")
        var afterCursor: String?
        var raw: [String: JSONValue]
    }

    let storeKit: StoreKitBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try storeKit.transactionUpdates(arguments: arguments.raw)
    }
}
