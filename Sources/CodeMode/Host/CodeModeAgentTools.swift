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

    /// Declared `async throws` for a body that is currently synchronous and
    /// non-throwing. That is deliberate: making the bridge ABI asynchronous is
    /// planned, and this signature is the one that will not have to change.
    public func executeJavaScript(_ request: JavaScriptExecutionRequest) async throws -> JavaScriptExecutionCall {
        runtime.makeExecutionCall(request)
    }

    /// TypeScript declarations for the whole platform-filtered API surface.
    ///
    /// Models write markedly better code against real types than against prose,
    /// so a host can drop this into its system prompt when the surface is small
    /// enough to afford, and rely on `searchJavaScriptAPI` (whose results carry a
    /// per-capability `dts`) when it is not.
    public func typeDeclarations() -> String {
        catalog.typeDeclarations()
    }

    /// Every capability available on this host, for consent UI and for hosts
    /// building their own `CapabilityGrant`.
    public func capabilities() -> [JavaScriptAPIReference] {
        catalog.allReferences()
    }

    /// Adds host providers after construction.
    ///
    /// Providers no longer have to be known at init: the catalog tracks the
    /// registry, so search starts advertising these immediately and the JS
    /// bindings are installed for the next execution. A host whose domain APIs
    /// depend on runtime state — a signed-in account, a loaded document — can
    /// register them when that state arrives.
    ///
    /// Registering a key that already exists replaces it.
    public func register(providers: [any CodeModeProvider]) {
        registry.register(providers.flatMap { $0.codeModeRegistrations() })
    }

    public func register(provider: any CodeModeProvider) {
        register(providers: [provider])
    }
}
