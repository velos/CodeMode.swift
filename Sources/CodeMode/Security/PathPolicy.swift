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

        // `fileExists` follows symlinks, so a symlink pointing at a *nonexistent*
        // out-of-root target reported "missing" and was treated as a component to
        // re-append rather than a link to resolve — admitting it. Checking for the
        // link itself keeps a dangling symlink in the resolution path, where
        // `resolvingSymlinksInPath` sends containment to the real target.
        while Self.isMissingComponent(existingAncestor, fileManager: fileManager),
              existingAncestor.path != existingAncestor.deletingLastPathComponent().path {
            missingComponents.insert(existingAncestor.lastPathComponent, at: 0)
            existingAncestor.deleteLastPathComponent()
        }

        let resolvedAncestor = Self.followingDanglingSymlink(
            existingAncestor.resolvingSymlinksInPath().standardizedFileURL,
            fileManager: fileManager
        )
        return missingComponents.reduce(resolvedAncestor) { partial, component in
            partial.appendingPathComponent(component)
        }.standardizedFileURL
    }

    /// True when nothing exists at this path — not even a broken symlink.
    /// `FileManager.fileExists` follows links and so answers false for one.
    private static func isMissingComponent(_ url: URL, fileManager: FileManager) -> Bool {
        if fileManager.fileExists(atPath: url.path) {
            return false
        }
        // `attributesOfItem` does not traverse the final symlink, so a dangling
        // link still has attributes here.
        return (try? fileManager.attributesOfItem(atPath: url.path)) == nil
    }

    /// Resolves a symlink whose target does not exist.
    ///
    /// `URL.resolvingSymlinksInPath()` only rewrites links it can follow, so a
    /// link to a nonexistent out-of-root target came back unchanged and passed
    /// containment. Containment must be judged on where the link *points*.
    private static func followingDanglingSymlink(_ url: URL, fileManager: FileManager) -> URL {
        var current = url
        // Bounded: a symlink cycle would otherwise spin here.
        for _ in 0..<16 {
            guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: current.path) else {
                return current
            }
            let next = destination.hasPrefix("/")
                ? URL(fileURLWithPath: destination)
                : current.deletingLastPathComponent().appendingPathComponent(destination)
            current = next.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        }
        return current
    }
}
