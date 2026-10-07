import Foundation

/// Byte ceilings for the filesystem bridge.
///
/// A sandbox root can hold files far larger than a script's result budget — a
/// 2 GB video in `documents:` read whole and base64-serialized is an immediate
/// jetsam on iOS — so reads and writes are bounded and fail with a diagnostic
/// instead of exhausting memory.
public struct FileSystemLimits: Sendable, Equatable {
    public var maxReadBytes: Int
    public var maxWriteBytes: Int

    public init(maxReadBytes: Int = 16 * 1_024 * 1_024, maxWriteBytes: Int = 16 * 1_024 * 1_024) {
        self.maxReadBytes = maxReadBytes
        self.maxWriteBytes = maxWriteBytes
    }

    public static let standard = FileSystemLimits()

    /// No ceiling. Only appropriate when the host has its own quota.
    public static let unlimited = FileSystemLimits(maxReadBytes: .max, maxWriteBytes: .max)
}

public final class FileSystemBridge: @unchecked Sendable {
    private let fileSystem: any CodeModeFileSystem
    private let limits: FileSystemLimits

    public init(
        fileSystem: any CodeModeFileSystem = LocalCodeModeFileSystem(),
        limits: FileSystemLimits = .standard
    ) {
        self.fileSystem = fileSystem
        self.limits = limits
    }

    public convenience init(fileManager: FileManager, limits: FileSystemLimits = .standard) {
        self.init(fileSystem: LocalCodeModeFileSystem(fileManager: fileManager), limits: limits)
    }

    public func list(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard let path = arguments.string("path") else {
            throw BridgeError.invalidArguments("fs.list requires 'path'")
        }

        let url = try context.pathPolicy.resolve(path: path)
        let entries: [JSONValue] = try fileSystem.listDirectory(at: url).map { item in
            return .object([
                "name": .string(item.name),
                "path": .string(item.path),
                "isDirectory": .bool(item.isDirectory),
                "size": .number(Double(item.size)),
            ])
        }

        return .array(entries)
    }

    public func read(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard let path = arguments.string("path") else {
            throw BridgeError.invalidArguments("fs.read requires 'path'")
        }

        let encoding = arguments.string("encoding") ?? "utf8"
        let url = try context.pathPolicy.resolve(path: path)

        // Checked against stat first: reading and then rejecting has already spent
        // the memory the cap exists to protect. Re-checked after, because a
        // custom CodeModeFileSystem's stat may be absent or stale.
        try enforceReadLimit(try? fileSystem.attributesOfItem(at: url).size, at: url)
        let data = try fileSystem.readData(at: url)
        try enforceReadLimit(data.count, at: url)

        switch encoding.lowercased() {
        case "utf8", "utf-8":
            // Silently substituting "" for undecodable bytes tells the script the
            // file is empty, which is worse than a failure it can act on.
            guard let text = String(data: data, encoding: .utf8) else {
                throw BridgeError.invalidArguments(
                    "fs.read could not decode \(url.lastPathComponent) as UTF-8. Retry with encoding: 'base64' for binary data."
                )
            }
            return .object([
                "path": .string(url.path),
                "text": .string(text),
            ])
        case "base64":
            return .object([
                "path": .string(url.path),
                "base64": .string(data.base64EncodedString()),
            ])
        default:
            throw BridgeError.invalidArguments("Unsupported encoding: \(encoding)")
        }
    }

    public func write(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard let path = arguments.string("path") else {
            throw BridgeError.invalidArguments("fs.write requires 'path'")
        }

        let encoding = arguments.string("encoding") ?? "utf8"
        let url = try context.pathPolicy.resolve(path: path)

        let data: Data
        switch encoding.lowercased() {
        case "utf8", "utf-8":
            let text = arguments.string("data") ?? ""
            data = Data(text.utf8)
        case "base64":
            guard let base64 = arguments.string("data"), let decoded = Data(base64Encoded: base64) else {
                throw BridgeError.invalidArguments("Invalid base64 data")
            }
            data = decoded
        default:
            throw BridgeError.invalidArguments("Unsupported encoding: \(encoding)")
        }

        guard data.count <= limits.maxWriteBytes else {
            throw Self.overLimit("fs.write", url: url, bytes: data.count, limit: limits.maxWriteBytes)
        }

        // Only after the payload is known good, so a rejected write leaves no
        // directories behind.
        try fileSystem.createDirectory(at: url.deletingLastPathComponent(), recursive: true)
        try fileSystem.writeData(data, to: url)
        return .object([
            "path": .string(url.path),
            "bytesWritten": .number(Double(data.count)),
        ])
    }

    public func move(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard let from = arguments.string("from"), let to = arguments.string("to") else {
            throw BridgeError.invalidArguments("fs.move requires 'from' and 'to'")
        }

        let fromURL = try context.pathPolicy.resolve(path: from)
        let toURL = try context.pathPolicy.resolve(path: to)
        try validateTransfer(from: fromURL, to: toURL, operation: "fs.move", arguments: arguments, context: context)

        try replacing(toURL, operation: "fs.move", arguments: arguments) {
            try fileSystem.moveItem(at: fromURL, to: toURL)
        }
        return .object([
            "from": .string(fromURL.path),
            "to": .string(toURL.path),
        ])
    }

    public func copy(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard let from = arguments.string("from"), let to = arguments.string("to") else {
            throw BridgeError.invalidArguments("fs.copy requires 'from' and 'to'")
        }

        let fromURL = try context.pathPolicy.resolve(path: from)
        let toURL = try context.pathPolicy.resolve(path: to)
        try validateTransfer(from: fromURL, to: toURL, operation: "fs.copy", arguments: arguments, context: context)

        // A copy writes new bytes, so it answers to the write limit — otherwise
        // copying a large tree is a way around it, and fills the disk.
        let bytes = try totalSize(of: fromURL, stoppingAbove: limits.maxWriteBytes)
        guard bytes <= limits.maxWriteBytes else {
            throw Self.overLimit("fs.copy", url: fromURL, bytes: bytes, limit: limits.maxWriteBytes)
        }

        try replacing(toURL, operation: "fs.copy", arguments: arguments) {
            try fileSystem.copyItem(at: fromURL, to: toURL)
        }
        return .object([
            "from": .string(fromURL.path),
            "to": .string(toURL.path),
        ])
    }

    private func enforceReadLimit(_ bytes: Int?, at url: URL) throws {
        guard let bytes, bytes > limits.maxReadBytes else {
            return
        }
        throw Self.overLimit("fs.read", url: url, bytes: bytes, limit: limits.maxReadBytes)
    }

    private static func overLimit(_ operation: String, url: URL, bytes: Int, limit: Int) -> BridgeError {
        .invalidArguments(
            "\(operation) refused \(url.lastPathComponent): \(bytes) bytes exceeds the \(limit)-byte limit. Use a smaller payload, or have the host raise CodeModeConfiguration.fileSystemLimits."
        )
    }

    /// Everything that must hold before a move or copy touches the disk.
    ///
    /// Containment alone admits a sandbox root: `documents:` resolves to the
    /// documents root itself. On the destination side that let
    /// `fs.move({ to: 'documents:' })` delete Documents; on the source side
    /// `fs.move({ from: 'documents:', to: 'tmp:x' })` moved Documents into a
    /// purgeable directory, and `fs.copy` from a root duplicated the whole tree.
    /// Both sides are refused, matching `fs.delete`.
    private func validateTransfer(
        from fromURL: URL,
        to toURL: URL,
        operation: String,
        arguments: [String: JSONValue],
        context: BridgeInvocationContext
    ) throws {
        guard context.pathPolicy.isAllowedRoot(fromURL) == false else {
            throw BridgeError.pathViolation(
                "\(operation) refuses a sandbox root as its source. Name a path inside the root, for example 'documents:archive'."
            )
        }
        guard context.pathPolicy.isAllowedRoot(toURL) == false else {
            throw BridgeError.pathViolation(
                "\(operation) refuses a sandbox root as its destination. Name a path inside the root, for example 'documents:archive/file.txt'."
            )
        }

        // Checked before anything is removed. Without it, a missing source with
        // overwrite: true deleted the destination and then failed.
        guard fileSystem.itemExists(at: fromURL) else {
            throw BridgeError.invalidArguments("\(operation) source does not exist: \(fromURL.lastPathComponent)")
        }

        // Same path, or a destination inside the source: the operation can never
        // succeed, and with overwrite: true the old order removed the destination
        // first — for `from == to`, that was the source itself.
        let fromPath = fromURL.standardizedFileURL.path
        let toPath = toURL.standardizedFileURL.path
        guard toPath != fromPath, toPath.hasPrefix(fromPath + "/") == false else {
            throw BridgeError.invalidArguments("\(operation) destination cannot be the source or a path inside it.")
        }

        guard fileSystem.itemExists(at: toURL) else {
            return
        }

        guard arguments.bool("overwrite") == true else {
            throw BridgeError.invalidArguments(
                "\(operation) destination already exists. Pass overwrite: true to replace it, or choose a different 'to' path."
            )
        }

        let isDirectory = (try? fileSystem.attributesOfItem(at: toURL))?.isDirectory ?? false
        if isDirectory, arguments.bool("recursive") != true {
            throw BridgeError.invalidArguments(
                "\(operation) destination is a directory. Pass recursive: true along with overwrite: true to replace it and everything under it."
            )
        }
    }

    /// Runs `operation`, replacing an existing destination only if it succeeds.
    ///
    /// The destination is moved aside rather than deleted, the operation runs,
    /// and only then is the old item removed; on failure it is moved back. The
    /// previous remove-then-act order meant any failure after the remove — a
    /// missing source, a full disk, a permissions error — lost the destination
    /// along with the operation.
    private func replacing(
        _ toURL: URL,
        operation: String,
        arguments: [String: JSONValue],
        _ body: () throws -> Void
    ) throws {
        guard fileSystem.itemExists(at: toURL) else {
            try body()
            return
        }

        // Same directory, so the aside move is a rename, not a copy.
        let aside = toURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(toURL.lastPathComponent).codemode-replacing-\(UUID().uuidString)")
        try fileSystem.moveItem(at: toURL, to: aside)

        do {
            try body()
        } catch {
            try? fileSystem.moveItem(at: aside, to: toURL)
            throw error
        }
        try? fileSystem.removeItem(at: aside)
    }

    /// Total bytes under `url`, stopping as soon as the running total exceeds
    /// `limit` so a huge tree is not walked in full just to be refused.
    private func totalSize(of url: URL, stoppingAbove limit: Int) throws -> Int {
        let attributes = try fileSystem.attributesOfItem(at: url)
        guard attributes.isDirectory else {
            return attributes.size
        }

        var total = 0
        var pending = [url]
        while let directory = pending.popLast() {
            for entry in try fileSystem.listDirectory(at: directory) {
                if entry.isDirectory {
                    pending.append(URL(fileURLWithPath: entry.path))
                } else {
                    total += entry.size
                    if total > limit {
                        return total
                    }
                }
            }
        }
        return total
    }

    public func delete(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard let path = arguments.string("path") else {
            throw BridgeError.invalidArguments("fs.delete requires 'path'")
        }

        let recursive = arguments.bool("recursive") ?? false
        let url = try context.pathPolicy.resolve(path: path)

        guard fileSystem.itemExists(at: url) else {
            return .object(["deleted": .bool(false), "path": .string(url.path)])
        }

        guard context.pathPolicy.isAllowedRoot(url) == false else {
            throw BridgeError.pathViolation(
                "fs.delete refuses a sandbox root. Delete entries inside it individually."
            )
        }

        let attrs = try fileSystem.attributesOfItem(at: url)
        if attrs.isDirectory, recursive == false {
            throw BridgeError.invalidArguments("fs.delete requires recursive=true for directories")
        }

        try fileSystem.removeItem(at: url)
        return .object(["deleted": .bool(true), "path": .string(url.path)])
    }

    public func stat(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard let path = arguments.string("path") else {
            throw BridgeError.invalidArguments("fs.stat requires 'path'")
        }

        let url = try context.pathPolicy.resolve(path: path)
        let attrs = try fileSystem.attributesOfItem(at: url)

        return .object([
            "path": .string(url.path),
            "isDirectory": .bool(attrs.isDirectory),
            "size": .number(Double(attrs.size)),
            "createdAt": .string(attrs.creationDate?.ISO8601Format() ?? ""),
            "modifiedAt": .string(attrs.modificationDate?.ISO8601Format() ?? ""),
        ])
    }

    public func mkdir(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard let path = arguments.string("path") else {
            throw BridgeError.invalidArguments("fs.mkdir requires 'path'")
        }

        let recursive = arguments.bool("recursive") ?? true
        let url = try context.pathPolicy.resolve(path: path)
        try fileSystem.createDirectory(at: url, recursive: recursive)

        return .object(["created": .bool(true), "path": .string(url.path)])
    }

    public func exists(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard let path = arguments.string("path") else {
            throw BridgeError.invalidArguments("fs.exists requires 'path'")
        }

        let url = try context.pathPolicy.resolve(path: path)
        return .bool(fileSystem.itemExists(at: url))
    }

    public func access(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard let path = arguments.string("path") else {
            throw BridgeError.invalidArguments("fs.access requires 'path'")
        }

        let url = try context.pathPolicy.resolve(path: path)
        let access = fileSystem.access(at: url)
        return .object([
            "readable": .bool(access.readable),
            "writable": .bool(access.writable),
            "path": .string(url.path),
        ])
    }
}
