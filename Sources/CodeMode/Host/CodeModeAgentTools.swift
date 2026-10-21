import Foundation

public final class CodeModeAgentTools: @unchecked Sendable {
    private let registry: CapabilityRegistry
    private let catalog: BridgeCatalog
    private let runtime: BridgeRuntime
    private let capabilityGrant: CapabilityGrant

    public convenience init(config: CodeModeConfiguration = .init()) {
        self.init(config: config, clock: RealClock())
    }

    /// Test seam: a virtual clock makes timer-driven executions instant and
    /// exact. Not public — production time is not a host decision.
    init(config: CodeModeConfiguration, clock: any RuntimeClock) {
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
        self.capabilityGrant = config.capabilityGrant
        self.catalog = BridgeCatalog(registry: registry)
        self.runtime = BridgeRuntime(
            registry: registry,
            catalog: self.catalog,
            config: config,
            unsupportedBuiltInJavaScriptNames: unsupportedBuiltInJavaScriptNames,
            clock: clock
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

    /// TypeScript declarations for what this host actually permits: the
    /// platform-filtered surface, narrowed to the configured `CapabilityGrant`.
    ///
    /// Models write markedly better code against real types than against prose,
    /// but the unrestricted iOS surface is roughly 21,000 tokens. A host with a
    /// grant pays only for what it grants — and never advertises a helper the
    /// model would be denied. Searches return a per-capability `dts` for the
    /// cases in between.
    public func typeDeclarations() -> String {
        catalog.typeDeclarations { reference in
            if let builtIn = reference.builtInCapability {
                return capabilityGrant.permits(builtIn)
            }
            return capabilityGrant.permits(key: reference.capabilityKey)
        }
    }

    /// Declarations for an explicit subset — for example, the capabilities a
    /// particular agent task needs, when even the grant is too broad to inline.
    /// Identifiers not available on this host are skipped.
    public func typeDeclarations(
        for capabilities: Set<CapabilityID>,
        capabilityKeys: Set<CodeModeCapabilityKey> = []
    ) -> String {
        catalog.typeDeclarations { reference in
            if let builtIn = reference.builtInCapability {
                return capabilities.contains(builtIn)
            }
            return capabilityKeys.contains(reference.capabilityKey)
        }
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
