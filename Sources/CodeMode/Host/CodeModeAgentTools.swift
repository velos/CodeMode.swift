import Foundation

public final class CodeModeAgentTools: @unchecked Sendable {
    private let registry: CapabilityRegistry
    private let catalog: BridgeCatalog
    private let runtime: BridgeRuntime

    public init(config: CodeModeConfiguration = .init()) {
        let registry = CapabilityRegistry(registrations: DefaultCapabilityLoader.loadAllRegistrations())
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
