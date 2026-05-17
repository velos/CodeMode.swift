import Foundation

public final class CodeModeAgentTools: @unchecked Sendable {
    private let registry: CapabilityRegistry
    private let catalog: BridgeCatalog
    private let runtime: BridgeRuntime

    public init(config: CodeModeConfiguration = .init()) {
        let registrations = CapabilityPlatformSupport.filter(
            DefaultCapabilityLoader.loadAllRegistrations(
                fileSystem: config.fileSystem,
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
            ),
            for: config.hostPlatform
        )
        let registry = CapabilityRegistry(registrations: registrations)
        self.registry = registry
        self.catalog = BridgeCatalog(registry: registry)
        self.runtime = BridgeRuntime(registry: registry, catalog: self.catalog, config: config)
    }

    public func searchJavaScriptAPI(_ request: JavaScriptAPISearchRequest) async throws -> JavaScriptAPISearchResponse {
        try runtime.search(request)
    }

    public func executeJavaScript(_ request: JavaScriptExecutionRequest) async throws -> JavaScriptExecutionCall {
        runtime.makeExecutionCall(request)
    }
}
