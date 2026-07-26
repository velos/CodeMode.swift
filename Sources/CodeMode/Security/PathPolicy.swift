import Foundation

public struct PathPolicyConfig: Sendable {
    public var tmpRoot: URL
    public var cachesRoot: URL
    public var documentsRoot: URL
    public var appGroupRoot: URL?

    public init(fileManager: FileManager = .default, appGroupRoot: URL? = nil) {
        self.tmpRoot = fileManager.temporaryDirectory
        self.cachesRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        self.documentsRoot = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        self.appGroupRoot = appGroupRoot
    }

    public init(tmpRoot: URL, cachesRoot: URL, documentsRoot: URL, appGroupRoot: URL? = nil) {
        self.tmpRoot = tmpRoot
        self.cachesRoot = cachesRoot
        self.documentsRoot = documentsRoot
        self.appGroupRoot = appGroupRoot
    }
}

public protocol PathPolicy: Sendable {
    func resolve(path: String) throws -> URL

    /// The roots this policy admits.
    ///
    /// `resolve` accepts a root itself — `documents:` resolves to the documents
    /// root — so destructive operations need to be able to recognize one and
    /// refuse. Custom policies that do not implement this get an empty list and
    /// simply lose that specific check.
    var allowedRoots: [URL] { get }
}

public extension PathPolicy {
    var allowedRoots: [URL] { [] }

    /// True when `url` *is* one of the allowed roots rather than something inside one.
    func isAllowedRoot(_ url: URL) -> Bool {
        let candidate = url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path
        return allowedRoots.contains { root in
            root.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path == candidate
        }
    }
}

public struct DefaultPathPolicy: PathPolicy {
    private var config: PathPolicyConfig

    public init(config: PathPolicyConfig = .init()) {
        self.config = config
    }

    public var allowedRoots: [URL] {
        [config.tmpRoot, config.cachesRoot, config.documentsRoot, config.appGroupRoot].compactMap { $0 }
    }

    public func resolve(path: String) throws -> URL {
        let cleaned = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else {
            throw BridgeError.pathViolation("Path must not be empty")
        }

        let url: URL
        if let scoped = parseScoped(path: cleaned) {
            url = scoped.base.appendingPathComponent(scoped.suffix)
        } else if cleaned.hasPrefix("/") {
            url = URL(fileURLWithPath: cleaned)
        } else {
            // Relative paths default to tmp scope.
            url = config.tmpRoot.appendingPathComponent(cleaned)
        }

        let normalized = url.standardizedFileURL
        let containmentURL = resolveSymlinksForContainment(normalized)
        guard isAllowed(containmentURL) else {
            throw BridgeError.pathViolation("Path is outside allowed roots: \(cleaned)")
        }

        return containmentURL
    }

    private func parseScoped(path: String) -> (base: URL, suffix: String)? {
        let parts = path.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let scope = String(parts[0])
        let suffix = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        switch scope {
        case "tmp":
            return (config.tmpRoot, suffix)
        case "caches":
            return (config.cachesRoot, suffix)
        case "documents":
            return (config.documentsRoot, suffix)
        case "appGroup":
            guard let appGroupRoot = config.appGroupRoot else {
                return nil
            }
            return (appGroupRoot, suffix)
        default:
            return nil
        }
    }

    private func isAllowed(_ url: URL) -> Bool {
        let allowedRoots = [config.tmpRoot, config.cachesRoot, config.documentsRoot, config.appGroupRoot]
            .compactMap { root in
                root.map { resolveSymlinksForContainment($0.standardizedFileURL).path }
            }
        let path = resolveSymlinksForContainment(url.standardizedFileURL).path

        return allowedRoots.contains { allowed in
            path == allowed || path.hasPrefix(allowed + "/")
        }
    }

    private func resolveSymlinksForContainment(_ url: URL) -> URL {
        var existingAncestor = url.standardizedFileURL
        var missingComponents: [String] = []
        let fileManager = FileManager.default

        while fileManager.fileExists(atPath: existingAncestor.path) == false,
              existingAncestor.path != existingAncestor.deletingLastPathComponent().path {
            missingComponents.insert(existingAncestor.lastPathComponent, at: 0)
            existingAncestor.deleteLastPathComponent()
        }

        let resolvedAncestor = existingAncestor.resolvingSymlinksInPath().standardizedFileURL
        return missingComponents.reduce(resolvedAncestor) { partial, component in
            partial.appendingPathComponent(component)
        }.standardizedFileURL
    }
}
