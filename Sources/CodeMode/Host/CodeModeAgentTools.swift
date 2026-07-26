import Foundation

public final class CodeModeAgentTools: @unchecked Sendable {
    private let registry: CapabilityRegistry
    private let catalog: BridgeCatalog
    private let runtime: BridgeRuntime

    public init(config: CodeModeConfiguration = .init()) {
        let allDefaultRegistrations = DefaultCapabilityLoader.loadAllRegistrations(
            fileSystem: config.fileSystem,
            fileSystemLimits: config.fileSystemLimits,
            networkAccessPolicy: config.networkAccessPolicy,
            eventInbox: config.eventInbox,
            cloudKitClient: config.cloudKitClient,
            remoteNotificationsClient: config.remoteNotificationsClient,
            speechClient: config.speechClient,
            appIntentsClient: config.appIntentsClient,
            foundationModelsClient: config.foundationModelsClient,
            activityClient: config.activityClient,
            mapsClient: config.mapsClient,
            musicClient: config.musicClient,
            passKitClient: config.passKitClient,
            storeKitClient: config.storeKitClient
        )
        let registrations = CapabilityPlatformSupport.filter(
            allDefaultRegistrations,
            for: config.hostPlatform
        )
        let unsupportedBuiltInJavaScriptNames = CapabilityPlatformSupport.unsupportedJavaScriptNames(
            from: allDefaultRegistrations,
            for: config.hostPlatform
        )
        let providerRegistrations = config.codeModeProviders.flatMap { $0.codeModeRegistrations() }
        let registry = CapabilityRegistry(registrations: registrations, codeModeRegistrations: providerRegistrations)
        self.registry = registry
        self.catalog = BridgeCatalog(registry: registry)
        self.runtime = BridgeRuntime(
            registry: registry,
            catalog: self.catalog,
            config: config,
            unsupportedBuiltInJavaScriptNames: unsupportedBuiltInJavaScriptNames
        )
    }

    public func searchJavaScriptAPI(_ request: JavaScriptAPISearchRequest) async throws -> JavaScriptAPISearchResponse {
        try await runtime.searchAsync(request)
    }

    public func executeJavaScript(_ request: JavaScriptExecutionRequest) async throws -> JavaScriptExecutionCall {
        runtime.makeExecutionCall(request)
    }
}
