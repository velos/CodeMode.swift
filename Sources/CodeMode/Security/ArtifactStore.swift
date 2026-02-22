import Foundation

public struct ArtifactHandle: Sendable, Codable, Hashable {
    public var id: String

    public init(id: String) {
        self.id = id
    }
}

public protocol ArtifactStore: Sendable {
    func register(url: URL, mimeType: String?) throws -> ArtifactHandle
    func resolve(handle: ArtifactHandle) -> URL?
}

public final class InMemoryArtifactStore: ArtifactStore, @unchecked Sendable {
    private let lock = NSLock()
    private var map: [ArtifactHandle: URL] = [:]

    public init() {}

    public func register(url: URL, mimeType: String?) throws -> ArtifactHandle {
        _ = mimeType
        let handle = ArtifactHandle(id: UUID().uuidString)
        lock.lock()
        map[handle] = url
        lock.unlock()
        return handle
    }

    public func resolve(handle: ArtifactHandle) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        return map[handle]
    }
}
