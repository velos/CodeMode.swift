import Foundation

public final class FileSystemBridge: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func list(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard let path = arguments.string("path") else {
            throw BridgeError.invalidArguments("fs.list requires 'path'")
        }

        let url = try context.pathPolicy.resolve(path: path)
        let values = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles])
        let entries: [JSONValue] = try values.map { item in
            let resourceValues = try item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            return .object([
                "name": .string(item.lastPathComponent),
                "path": .string(item.path),
                "isDirectory": .bool(resourceValues.isDirectory ?? false),
                "size": .number(Double(resourceValues.fileSize ?? 0)),
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
        let data = try Data(contentsOf: url)

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
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

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

        try data.write(to: url, options: .atomic)
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

        if fileManager.fileExists(atPath: toURL.path) {
            try fileManager.removeItem(at: toURL)
        }

        try fileManager.moveItem(at: fromURL, to: toURL)
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

        if fileManager.fileExists(atPath: toURL.path) {
            try fileManager.removeItem(at: toURL)
        }

        try fileManager.copyItem(at: fromURL, to: toURL)
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
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .object(["deleted": .bool(false), "path": .string(url.path)])
        }

        if isDirectory.boolValue, recursive == false {
            throw BridgeError.invalidArguments("fs.delete requires recursive=true for directories")
        }

        try fileManager.removeItem(at: url)
        return .object(["deleted": .bool(true), "path": .string(url.path)])
    }

    public func stat(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard let path = arguments.string("path") else {
            throw BridgeError.invalidArguments("fs.stat requires 'path'")
        }

        let url = try context.pathPolicy.resolve(path: path)
        let attrs = try fileManager.attributesOfItem(atPath: url.path)
        let type = attrs[.type] as? FileAttributeType
        let isDirectory = type == .typeDirectory

        return .object([
            "path": .string(url.path),
            "isDirectory": .bool(isDirectory),
            "size": .number(Double((attrs[.size] as? NSNumber)?.intValue ?? 0)),
            "createdAt": .string((attrs[.creationDate] as? Date)?.ISO8601Format() ?? ""),
            "modifiedAt": .string((attrs[.modificationDate] as? Date)?.ISO8601Format() ?? ""),
        ])
    }

    public func mkdir(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard let path = arguments.string("path") else {
            throw BridgeError.invalidArguments("fs.mkdir requires 'path'")
        }

        let recursive = arguments.bool("recursive") ?? true
        let url = try context.pathPolicy.resolve(path: path)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: recursive)

        return .object(["created": .bool(true), "path": .string(url.path)])
    }

    public func exists(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard let path = arguments.string("path") else {
            throw BridgeError.invalidArguments("fs.exists requires 'path'")
        }

        let url = try context.pathPolicy.resolve(path: path)
        return .bool(fileManager.fileExists(atPath: url.path))
    }

    public func access(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard let path = arguments.string("path") else {
            throw BridgeError.invalidArguments("fs.access requires 'path'")
        }

        let url = try context.pathPolicy.resolve(path: path)
        let readable = fileManager.isReadableFile(atPath: url.path)
        let writable = fileManager.isWritableFile(atPath: url.path)
        return .object([
            "readable": .bool(readable),
            "writable": .bool(writable),
            "path": .string(url.path),
        ])
    }
}
