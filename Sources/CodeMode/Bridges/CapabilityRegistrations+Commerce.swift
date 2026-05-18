import Foundation

extension DefaultCapabilityRegistrationBuilder {
    func musicRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                .musicPermissionRequest,
                jsName: "apple.music.requestPermission",
                title: "Request Music permission",
                summary: "Request Apple Music/media-library permission before library or playback actions.",
                tags: ["music", "musickit", "permission"],
                example: "await apple.music.requestPermission()",
                resultSummary: "Object with status/granted."
            ) { _, context in
                try music.requestPermission(context: context)
            },
            CapabilityRegistration(
                .musicSubscriptionStatus,
                jsName: "apple.music.getSubscriptionStatus",
                title: "Read Music subscription status",
                summary: "Read MusicKit subscription/capability status exposed by the host.",
                tags: ["music", "musickit", "subscription", "catalog"],
                example: "await apple.music.getSubscriptionStatus()",
                resultSummary: "Object with canPlayCatalogContent/hasCloudLibraryEnabled/status."
            ) { args, _ in
                try music.subscriptionStatus(arguments: args)
            },
            CapabilityRegistration(
                .musicCatalogSearch,
                jsName: "apple.music.search",
                title: "Search Music catalog",
                summary: "Search the Apple Music catalog for songs, albums, artists, playlists, or stations.",
                tags: ["music", "musickit", "catalog", "search"],
                example: "await apple.music.search({ term: 'Miles Davis', types: ['artists', 'albums'], limit: 5 })",
                requiredArguments: ["term"],
                optionalArguments: ["types", "limit", "countryCode"],
                argumentHints: [
                    "term": "Catalog search term.",
                    "types": "Optional array such as songs, albums, artists, playlists, stations.",
                    "limit": "Maximum results.",
                    "countryCode": "Optional storefront country code.",
                ],
                resultSummary: "Object grouped by result type with catalog identifiers and metadata."
            ) { args, _ in
                try music.searchCatalog(arguments: args)
            },
            CapabilityRegistration(
                .musicCatalogDetails,
                jsName: "apple.music.getDetails",
                title: "Read Music catalog details",
                summary: "Read details for a catalog item identifier through MusicKit.",
                tags: ["music", "musickit", "catalog", "details"],
                example: "await apple.music.getDetails({ identifier: '123', type: 'albums' })",
                requiredArguments: ["identifier"],
                optionalArguments: ["type", "countryCode"],
                argumentHints: [
                    "identifier": "Music catalog item identifier.",
                    "type": "Catalog type such as songs, albums, artists, playlists, or stations.",
                ],
                resultSummary: "Catalog item details object."
            ) { args, _ in
                try music.catalogDetails(arguments: args)
            },
            CapabilityRegistration(
                .musicLibraryRead,
                jsName: "apple.music.readLibrary",
                title: "Read Music library",
                summary: "Read the user's Music library playlists or items after Music permission is granted.",
                tags: ["music", "musickit", "library"],
                example: "await apple.music.readLibrary({ type: 'playlists', limit: 20 })",
                requiredPermissions: [.music],
                optionalArguments: ["type", "limit"],
                argumentHints: [
                    "type": "Library type such as playlists, songs, albums, or artists.",
                    "limit": "Maximum library items.",
                ],
                resultSummary: "Array of library items with identifiers and metadata."
            ) { args, context in
                try music.readLibrary(arguments: args, context: context)
            },
            CapabilityRegistration(
                .musicPlaylistWrite,
                jsName: "apple.music.writePlaylist",
                title: "Write Music playlist",
                summary: "Create or update a user-library playlist through a host MusicKit adapter.",
                tags: ["music", "musickit", "library", "playlist", "write"],
                example: "await apple.music.writePlaylist({ name: 'Focus', catalogIDs: ['song-id'] })",
                requiredPermissions: [.music],
                requiredArguments: ["name"],
                optionalArguments: ["playlistID", "catalogIDs", "libraryIDs", "description"],
                argumentHints: [
                    "name": "Playlist name.",
                    "playlistID": "Optional existing playlist identifier to update.",
                    "catalogIDs": "Optional catalog song identifiers to add.",
                    "libraryIDs": "Optional library song identifiers to add.",
                ],
                resultSummary: "Object with playlistID/name/written."
            ) { args, context in
                try music.writePlaylist(arguments: args, context: context)
            },
            CapabilityRegistration(
                .musicPlaybackControl,
                jsName: "apple.music.play",
                title: "Control Music playback",
                summary: "Control Music playback queue through a user-authorized host adapter.",
                tags: ["music", "musickit", "playback", "queue"],
                example: "await apple.music.play({ action: 'playCatalog', catalogID: 'song-id' })",
                requiredPermissions: [.music],
                requiredArguments: ["action"],
                optionalArguments: ["catalogID", "libraryID", "queue", "startPlaying"],
                argumentHints: [
                    "action": "Host-supported action such as play, pause, stop, skipToNext, playCatalog, or playLibrary.",
                    "catalogID": "Optional catalog item identifier.",
                    "libraryID": "Optional library item identifier.",
                    "queue": "Optional queue definition approved by the host adapter.",
                ],
                resultSummary: "Object with action/status/currentItem when available."
            ) { args, context in
                try music.controlPlayback(arguments: args, context: context)
            },
        ]
    }


    func passKitRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                .passKitWalletStatus,
                jsName: "apple.wallet.getStatus",
                title: "Read Wallet status",
                summary: "Read PassKit Wallet availability and pass-library access status.",
                tags: ["passkit", "wallet", "passes"],
                example: "await apple.wallet.getStatus()",
                resultSummary: "Object with available/canAddPasses/canPresentPasses."
            ) { args, _ in
                try passKit.walletStatus(arguments: args)
            },
            CapabilityRegistration(
                .passKitPassesRead,
                jsName: "apple.wallet.listPasses",
                title: "List Wallet passes",
                summary: "List Wallet passes accessible to the host app through PassKit.",
                tags: ["passkit", "wallet", "passes", "read"],
                example: "await apple.wallet.listPasses({ limit: 20 })",
                optionalArguments: ["passTypeIdentifier", "serialNumber", "limit"],
                argumentHints: [
                    "passTypeIdentifier": "Optional pass type filter.",
                    "serialNumber": "Optional serial number filter.",
                    "limit": "Maximum accessible passes.",
                ],
                resultSummary: "Array of passes with passTypeIdentifier/serialNumber/organizationName/description."
            ) { args, _ in
                try passKit.listPasses(arguments: args)
            },
            CapabilityRegistration(
                .passKitPassAdd,
                jsName: "apple.wallet.addPass",
                title: "Add Wallet pass",
                summary: "Present user-mediated UI to add a sandbox .pkpass file to Wallet.",
                tags: ["passkit", "wallet", "passes", "add", "system-ui"],
                example: "await apple.wallet.addPass({ path: 'tmp:ticket.pkpass' })",
                requiredArguments: ["path"],
                optionalArguments: ["timeoutMs"],
                argumentHints: [
                    "path": "Sandbox path to a .pkpass file.",
                    "timeoutMs": "Optional timeout for user-mediated add-pass UI.",
                ],
                resultSummary: "Object with action/added/passTypeIdentifier/serialNumber."
            ) { args, context in
                try passKit.addPass(arguments: args, context: context)
            },
            CapabilityRegistration(
                .passKitPassPresent,
                jsName: "apple.wallet.presentPass",
                title: "Present Wallet pass",
                summary: "Present user-mediated details for an accessible Wallet pass.",
                tags: ["passkit", "wallet", "passes", "system-ui"],
                example: "await apple.wallet.presentPass({ identifier: 'pass-id' })",
                requiredArguments: ["identifier"],
                optionalArguments: ["timeoutMs"],
                resultSummary: "Object with action/presented/identifier."
            ) { args, _ in
                try passKit.presentPass(arguments: args)
            },
            CapabilityRegistration(
                .passKitApplePayStatus,
                jsName: "apple.wallet.canMakePayments",
                title: "Read Apple Pay status",
                summary: "Read Apple Pay capability using host merchant configuration; no merchant setup is accepted from JavaScript.",
                tags: ["passkit", "apple-pay", "payments", "safety"],
                example: "await apple.wallet.canMakePayments()",
                optionalArguments: ["networks"],
                argumentHints: [
                    "networks": "Optional supported payment networks to test against host merchant configuration.",
                ],
                resultSummary: "Object with canMakePayments/canMakePaymentsUsingNetworks."
            ) { args, _ in
                try passKit.applePayStatus(arguments: args)
            },
            CapabilityRegistration(
                .passKitApplePayPresent,
                jsName: "apple.wallet.presentPayment",
                title: "Present Apple Pay request",
                summary: "Present a host-defined Apple Pay payment request using host merchant configuration after explicit user-visible confirmation.",
                tags: ["passkit", "apple-pay", "payments", "system-ui", "safety"],
                example: "await apple.wallet.presentPayment({ paymentRequestID: 'checkout-123', confirmed: true })",
                requiredArguments: ["paymentRequestID", "confirmed"],
                optionalArguments: ["timeoutMs"],
                argumentHints: [
                    "paymentRequestID": "Host-defined payment request identifier using host merchant configuration; arbitrary merchant setup is not accepted from JavaScript.",
                    "confirmed": "Must be true after explicit user-visible confirmation before presenting Apple Pay.",
                ],
                resultSummary: "Object with action/authorized/paymentRequestID/status."
            ) { args, _ in
                try passKit.presentApplePay(arguments: args)
            },
        ]
    }


    func storeKitRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                .storeKitProductsRead,
                jsName: "apple.storekit.listProducts",
                title: "Read StoreKit products",
                summary: "Read StoreKit product metadata for host-configured product identifiers.",
                tags: ["storekit", "commerce", "products"],
                example: "await apple.storekit.listProducts({ productIDs: ['pro.monthly'] })",
                requiredArguments: ["productIDs"],
                argumentHints: [
                    "productIDs": "Array of host-configured StoreKit product identifiers.",
                ],
                resultSummary: "Array of products with id/displayName/description/price/type."
            ) { args, _ in
                try storeKit.products(arguments: args)
            },
            CapabilityRegistration(
                .storeKitEntitlementsRead,
                jsName: "apple.storekit.listEntitlements",
                title: "Read StoreKit entitlements",
                summary: "Read current StoreKit entitlements and verified transaction state.",
                tags: ["storekit", "commerce", "entitlements"],
                example: "await apple.storekit.listEntitlements()",
                resultSummary: "Array of current entitlements with productID/transactionID/expirationDate."
            ) { args, _ in
                try storeKit.currentEntitlements(arguments: args)
            },
            CapabilityRegistration(
                .storeKitPurchase,
                jsName: "apple.storekit.purchase",
                title: "Purchase StoreKit product",
                summary: "Present StoreKit purchase UI for a host-configured product after explicit user-visible confirmation.",
                tags: ["storekit", "commerce", "purchase", "safety"],
                example: "await apple.storekit.purchase({ productID: 'pro.monthly', confirmed: true })",
                requiredArguments: ["productID", "confirmed"],
                optionalArguments: ["appAccountToken"],
                argumentHints: [
                    "productID": "Host-configured StoreKit product identifier.",
                    "confirmed": "Must be true after explicit user-visible confirmation before purchase UI is presented.",
                    "appAccountToken": "Optional UUID string for StoreKit appAccountToken.",
                ],
                resultSummary: "Object with status/productID/transactionID when completed."
            ) { args, _ in
                try storeKit.purchase(arguments: args)
            },
            CapabilityRegistration(
                .storeKitRestore,
                jsName: "apple.storekit.restore",
                title: "Restore StoreKit purchases",
                summary: "Trigger StoreKit restore/sync after explicit user-visible confirmation.",
                tags: ["storekit", "commerce", "restore", "safety"],
                example: "await apple.storekit.restore({ confirmed: true })",
                requiredArguments: ["confirmed"],
                argumentHints: [
                    "confirmed": "Must be true after explicit user-visible confirmation before restore starts.",
                ],
                resultSummary: "Object with restored/status."
            ) { args, _ in
                try storeKit.restore(arguments: args)
            },
            CapabilityRegistration(
                .storeKitTransactionsRead,
                jsName: "apple.storekit.listTransactions",
                title: "Read StoreKit transaction inbox",
                summary: "Read bounded transaction updates captured by the host StoreKit adapter.",
                tags: ["storekit", "commerce", "transactions", "inbox", "events"],
                example: "await apple.storekit.listTransactions({ limit: 20 })",
                optionalArguments: ["limit", "productID", "afterCursor"],
                argumentHints: [
                    "limit": "Maximum transaction updates to return.",
                    "productID": "Optional product filter.",
                    "afterCursor": "Optional host-provided cursor for incremental reads.",
                ],
                resultSummary: "Array of transaction events with cursor/productID/transactionID/status/date."
            ) { args, _ in
                try storeKit.transactionUpdates(arguments: args)
            },
        ]
    }
}
