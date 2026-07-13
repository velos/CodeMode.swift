import Foundation

extension DefaultCapabilityRegistrationBuilder {
    func musicRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: MusicPermissionRequestTool(music: music)),
            CapabilityRegistration(tool: MusicSubscriptionStatusTool(music: music)),
            CapabilityRegistration(tool: MusicCatalogSearchTool(music: music)),
            CapabilityRegistration(tool: MusicCatalogDetailsTool(music: music)),
            CapabilityRegistration(tool: MusicLibraryReadTool(music: music)),
            CapabilityRegistration(tool: MusicPlaylistWriteTool(music: music)),
            CapabilityRegistration(tool: MusicPlaybackControlTool(music: music)),
        ]
    }


    func passKitRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: PassKitWalletStatusTool(passKit: passKit)),
            CapabilityRegistration(tool: PassKitPassesReadTool(passKit: passKit)),
            CapabilityRegistration(tool: PassKitPassAddTool(passKit: passKit)),
            CapabilityRegistration(tool: PassKitPassPresentTool(passKit: passKit)),
            CapabilityRegistration(tool: PassKitApplePayStatusTool(passKit: passKit)),
            CapabilityRegistration(tool: PassKitApplePayPresentTool(passKit: passKit)),
        ]
    }


    func storeKitRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: StoreKitProductsReadTool(storeKit: storeKit)),
            CapabilityRegistration(tool: StoreKitEntitlementsReadTool(storeKit: storeKit)),
            CapabilityRegistration(tool: StoreKitPurchaseTool(storeKit: storeKit)),
            CapabilityRegistration(tool: StoreKitRestoreTool(storeKit: storeKit)),
            CapabilityRegistration(tool: StoreKitTransactionsReadTool(storeKit: storeKit)),
        ]
    }
}
