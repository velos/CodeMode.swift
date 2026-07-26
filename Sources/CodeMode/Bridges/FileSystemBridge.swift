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

        // Check the size before reading: reading first and then rejecting has
        // already spent the memory the cap exists to protect.
        if let size = try? fileSystem.attributesOfItem(at: url).size, size > limits.maxReadBytes {
            throw BridgeError.invalidArguments(
                "fs.read refused \(url.lastPathComponent): \(size) bytes exceeds the \(limits.maxReadBytes)-byte read limit. Read a smaller file, or have the host raise CodeModeConfiguration.fileSystemLimits."
            )
        }

        let data = try fileSystem.readData(at: url)
        guard data.count <= limits.maxReadBytes else {
            throw BridgeError.invalidArguments(
                "fs.read refused \(url.lastPathComponent): \(data.count) bytes exceeds the \(limits.maxReadBytes)-byte read limit."
            )
        }

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
            throw BridgeError.invalidArguments(
                "fs.write refused \(url.lastPathComponent): \(data.count) bytes exceeds the \(limits.maxWriteBytes)-byte write limit."
            )
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
        try prepareDestination(toURL, operation: "fs.move", arguments: arguments, context: context)

        try fileSystem.moveItem(at: fromURL, to: toURL)
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
        try prepareDestination(toURL, operation: "fs.copy", arguments: arguments, context: context)

        try fileSystem.copyItem(at: fromURL, to: toURL)
        return .object([
            "from": .string(fromURL.path),
            "to": .string(toURL.path),
        ])
    }

    /// Clears the way for a move/copy, refusing anything destructive the caller
    /// did not explicitly ask for.
    ///
    /// The previous behavior was an unconditional recursive `removeItem` on any
    /// existing destination, and containment alone admits a root: `documents:`
    /// resolves to the documents root, so `fs.move({ from: 'tmp:junk.txt',
    /// to: 'documents:' })` deleted the user's whole Documents directory. The
    /// gates here match the ones `fs.delete` already enforces.
    private func prepareDestination(
        _ toURL: URL,
        operation: String,
        arguments: [String: JSONValue],
        context: BridgeInvocationContext
    ) throws {
        guard context.pathPolicy.isAllowedRoot(toURL) == false else {
            throw BridgeError.pathViolation(
                "\(operation) refuses a sandbox root as its destination. Name a path inside the root, for example 'documents:archive/file.txt'."
            )
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

        try fileSystem.removeItem(at: toURL)
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
