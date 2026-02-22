import Foundation

public struct CodeModeBridgeHostConfig: Sendable {
    public var runtimeConfig: BridgeRuntimeConfig
    public var registrations: [CapabilityRegistration]

    public init(
        runtimeConfig: BridgeRuntimeConfig = .init(),
        registrations: [CapabilityRegistration] = DefaultCapabilityLoader.loadAllRegistrations()
    ) {
        self.runtimeConfig = runtimeConfig
        self.registrations = registrations
    }
}

public final class CodeModeBridgeHost: @unchecked Sendable {
    private let registry: CapabilityRegistry
    private let catalog: BridgeCatalog
    private let runtime: BridgeRuntime

    public init(config: CodeModeBridgeHostConfig = .init()) {
        let registry = CapabilityRegistry(registrations: config.registrations)
        self.registry = registry
        self.catalog = BridgeCatalog(registry: registry)
        self.runtime = BridgeRuntime(registry: registry, catalog: self.catalog, config: config.runtimeConfig)
    }

    public func search(_ request: SearchRequest) async throws -> SearchResponse {
        runtime.search(request)
    }

    public func execute(_ request: ExecuteRequest) async throws -> ExecuteResponse {
        runtime.execute(request)
    }

    public func docs() -> [BridgeAPIDoc] {
        catalog.entries
    }
}
