import Foundation
import Testing
@testable import CodeMode

@Test func inMemoryArtifactStoreRoundTripsHandles() throws {
    let store = InMemoryArtifactStore()
    let url = URL(fileURLWithPath: "/tmp/example.png")

    let handle = try store.register(url: url, mimeType: "image/png")
    #expect(store.resolve(handle: handle) == url)
    #expect(store.resolve(handle: ArtifactHandle(id: "missing")) == nil)
}

@Test func inMemoryArtifactStoreIssuesUniqueHandles() throws {
    let store = InMemoryArtifactStore()
    let url = URL(fileURLWithPath: "/tmp/example.png")

    let first = try store.register(url: url, mimeType: nil)
    let second = try store.register(url: url, mimeType: nil)
    #expect(first != second)
    #expect(store.resolve(handle: first) == url)
    #expect(store.resolve(handle: second) == url)
}

@Test func syncAuditLoggerDrainReturnsAndClearsEventsInOrder() {
    let logger = SyncAuditLogger()
    let first = AuditEvent(capability: "fs.read", message: "success")
    let second = AuditEvent(capability: "network.fetch", message: "allowed")

    logger.log(first)
    logger.log(second)

    #expect(logger.drain() == [first, second])
    #expect(logger.drain().isEmpty)

    let third = AuditEvent(capability: "fs.write", message: "success")
    logger.log(third)
    #expect(logger.drain() == [third])
}

@Test func syncAuditLoggerIsSafeUnderConcurrentLogging() {
    let logger = SyncAuditLogger()
    let iterations = 200

    DispatchQueue.concurrentPerform(iterations: iterations) { index in
        logger.log(AuditEvent(capability: "cap.\(index)", message: "m"))
    }

    #expect(logger.drain().count == iterations)
}
