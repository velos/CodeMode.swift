import Foundation

public struct CodeModeFileSystemEntry: Sendable, Equatable {
    public var name: String
    public var path: String
    public var isDirectory: Bool
    public var size: Int

    public init(name: String, path: String, isDirectory: Bool, size: Int) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
    }
}

public struct CodeModeFileSystemAttributes: Sendable, Equatable {
    public var isDirectory: Bool
    public var size: Int
    public var creationDate: Date?
    public var modificationDate: Date?

    public init(isDirectory: Bool, size: Int, creationDate: Date?, modificationDate: Date?) {
        self.isDirectory = isDirectory
        self.size = size
        self.creationDate = creationDate
        self.modificationDate = modificationDate
    }
}

public struct CodeModeFileSystemAccess: Sendable, Equatable {
    public var readable: Bool
    public var writable: Bool

    public init(readable: Bool, writable: Bool) {
        self.readable = readable
        self.writable = writable
    }
}

public protocol CodeModeFileSystem: Sendable {
    func listDirectory(at url: URL) throws -> [CodeModeFileSystemEntry]
    func readData(at url: URL) throws -> Data
    func writeData(_ data: Data, to url: URL) throws
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws
    func copyItem(at sourceURL: URL, to destinationURL: URL) throws
    func removeItem(at url: URL) throws
    func attributesOfItem(at url: URL) throws -> CodeModeFileSystemAttributes
    func createDirectory(at url: URL, recursive: Bool) throws
    func itemExists(at url: URL) -> Bool
    func access(at url: URL) -> CodeModeFileSystemAccess
}

public final class LocalCodeModeFileSystem: CodeModeFileSystem, @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func listDirectory(at url: URL) throws -> [CodeModeFileSystemEntry] {
        let values = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        return try values.map { item in
            let resourceValues = try item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            return CodeModeFileSystemEntry(
                name: item.lastPathComponent,
                path: item.path,
                isDirectory: resourceValues.isDirectory ?? false,
                size: resourceValues.fileSize ?? 0
            )
        }
    }

    public func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func writeData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    public func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    public func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    public func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    public func attributesOfItem(at url: URL) throws -> CodeModeFileSystemAttributes {
        let attrs = try fileManager.attributesOfItem(atPath: url.path)
        let type = attrs[.type] as? FileAttributeType
        return CodeModeFileSystemAttributes(
            isDirectory: type == .typeDirectory,
            size: (attrs[.size] as? NSNumber)?.intValue ?? 0,
            creationDate: attrs[.creationDate] as? Date,
            modificationDate: attrs[.modificationDate] as? Date
        )
    }

    public func createDirectory(at url: URL, recursive: Bool) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: recursive)
    }

    public func itemExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    public func access(at url: URL) -> CodeModeFileSystemAccess {
        CodeModeFileSystemAccess(
            readable: fileManager.isReadableFile(atPath: url.path),
            writable: fileManager.isWritableFile(atPath: url.path)
        )
    }
}
