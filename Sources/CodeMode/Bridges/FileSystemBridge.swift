import Foundation

public final class FileSystemBridge: @unchecked Sendable {
    private let fileSystem: any CodeModeFileSystem

    public init(fileSystem: any CodeModeFileSystem = LocalCodeModeFileSystem()) {
        self.fileSystem = fileSystem
    }

    public convenience init(fileManager: FileManager) {
        self.init(fileSystem: LocalCodeModeFileSystem(fileManager: fileManager))
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
        let data = try fileSystem.readData(at: url)

        switch encoding.lowercased() {
        case "utf8", "utf-8":
            let text = String(data: data, encoding: .utf8) ?? ""
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

        let parent = url.deletingLastPathComponent()
        try fileSystem.createDirectory(at: parent, recursive: true)

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

        if fileSystem.itemExists(at: toURL) {
            try fileSystem.removeItem(at: toURL)
        }

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

        if fileSystem.itemExists(at: toURL) {
            try fileSystem.removeItem(at: toURL)
        }

        try fileSystem.copyItem(at: fromURL, to: toURL)
        return .object([
            "from": .string(fromURL.path),
            "to": .string(toURL.path),
        ])
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
