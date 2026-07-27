import Foundation

/// The host-owned ceiling on what an execution may reach.
///
/// `JavaScriptExecutionRequest.allowedCapabilities` / `allowedCapabilityKeys` are
/// *model-authored* — they travel in the advertised tool schema, so a script
/// declares them for itself. They are a least-privilege declaration of intent and
/// a useful audit signal, but they are not a sandbox: on their own, a script that
/// asks for `keychain.read` gets it.
///
/// `CapabilityGrant` is the half the host owns. It is configured on
/// `CodeModeConfiguration` and intersected with the request before the invocation
/// context is built, so the effective set is always
/// `requested ∩ granted`. Anything the model asks for that the grant withholds
/// fails with `CAPABILITY_DENIED` and is reported to the model as *not*
/// repairable by retrying with a wider `allowedCapabilities`.
public struct CapabilityGrant: Sendable, Equatable {
    /// Built-in capabilities the host permits, or `nil` for "no host ceiling".
    public var capabilities: Set<CapabilityID>?
    /// Custom provider capability keys the host permits, or `nil` for "no host ceiling".
    public var capabilityKeys: Set<CodeModeCapabilityKey>?

    public init(capabilities: Set<CapabilityID>?, capabilityKeys: Set<CodeModeCapabilityKey>?) {
        self.capabilities = capabilities
        self.capabilityKeys = capabilityKeys
    }

    /// No host ceiling: whatever the request declares is what the script gets.
    ///
    /// This is the default for source compatibility, and it is the right choice
    /// only when the host has already vetted the request itself. Hosts that pipe
    /// model-authored tool JSON straight into `executeJavaScript` should set an
    /// explicit grant.
    public static let unrestricted = CapabilityGrant(capabilities: nil, capabilityKeys: nil)

    /// Grants nothing; every capability request is withheld.
    public static let none = CapabilityGrant(capabilities: [], capabilityKeys: [])

    /// Grants exactly the listed built-in capabilities and provider keys.
    public static func only(
        _ capabilities: Set<CapabilityID>,
        capabilityKeys: Set<CodeModeCapabilityKey> = []
    ) -> CapabilityGrant {
        CapabilityGrant(capabilities: capabilities, capabilityKeys: capabilityKeys)
    }

    /// Applies the ceiling to a model-authored request.
    ///
    /// Returns the effective sets alongside everything that was asked for and
    /// withheld, so the caller can tell the model why a retry will not help.
    public func resolve(
        requestedCapabilities: Set<CapabilityID>,
        requestedCapabilityKeys: Set<CodeModeCapabilityKey>
    ) -> Resolution {
        let effectiveCapabilities = capabilities.map { requestedCapabilities.intersection($0) } ?? requestedCapabilities
        let effectiveKeys = capabilityKeys.map { requestedCapabilityKeys.intersection($0) } ?? requestedCapabilityKeys

        return Resolution(
            capabilities: effectiveCapabilities,
            capabilityKeys: effectiveKeys,
            withheld: (
                requestedCapabilities.subtracting(effectiveCapabilities).map(\.rawValue)
                    + requestedCapabilityKeys.subtracting(effectiveKeys).map(\.rawValue)
            ).sorted()
        )
    }

    public struct Resolution: Sendable, Equatable {
        public var capabilities: Set<CapabilityID>
        public var capabilityKeys: Set<CodeModeCapabilityKey>
        /// Identifiers the request declared and the grant refused, sorted. Both
        /// namespaces together, because every consumer reports them as one list.
        public var withheld: [String]
    }
}
