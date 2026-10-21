import Foundation

// Filesystem capabilities.

/// The encodings `fs.read`/`fs.write` accept. Declared as an enum so the catalog
/// advertises `allowedStringValues` instead of leaving the constraint in prose,
/// where the model cannot discover it.
enum FileEncoding: String, CodeModeStringEnum {
    case utf8
    case base64

    static let codeModeAliases: [String: FileEncoding] = ["utf-8": .utf8]
}

@BuiltInCodeMode(.fsList, path: "apple.fs.list", aliases: ["fs.promises.readdir"])
struct FSListTool: BuiltInCodeModeTool {
    static let codeModeTitle = "List directory"
    static let codeModeSummary = "List files/directories within allowed sandbox roots as entry objects."
    static let codeModeTags = ["filesystem", "io", "fs"]
    static let codeModeExample = "await apple.fs.list({ path: 'tmp:' })"
    static let codeModeResultSummary = "Array of entry objects with name/path/isDirectory/size. Use entry.name for filenames; fs.promises.readdir returns the same entry objects, not strings."

    struct Arguments: Sendable {
        @ToolParam("Directory path using allowed root prefix (tmp:, caches:, documents:).")
        var path: String
        var raw: [String: JSONValue]
    }

    let fs: FileSystemBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try fs.list(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.fsRead, path: "apple.fs.read", aliases: ["fs.promises.readFile"])
struct FSReadTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Read file"
    static let codeModeSummary = "Read text/base64 file data within allowed sandbox roots."
    static let codeModeTags = ["filesystem", "io", "fs"]
    static let codeModeExample = "await apple.fs.read({ path: 'tmp:data.json', encoding: 'utf8' })"
    static let codeModeResultSummary = "Object with path plus text or base64 field."

    struct Arguments: Sendable {
        @ToolParam("File path using allowed root prefix.")
        var path: String
        @ToolParam("utf8 (default) or base64. Binary files must use base64; a utf8 read of undecodable bytes fails rather than returning empty text.")
        var encoding: FileEncoding?
        var raw: [String: JSONValue]
    }

    let fs: FileSystemBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try fs.read(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.fsWrite, path: "apple.fs.write", aliases: ["fs.promises.writeFile"])
struct FSWriteTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Write file"
    static let codeModeSummary = "Write text/base64 file data within allowed sandbox roots."
    static let codeModeTags = ["filesystem", "io", "fs"]
    static let codeModeExample = "await apple.fs.write({ path: 'tmp:data.json', data: '{\"ok\":true}' })"
    static let codeModeResultSummary = "Object with path and bytesWritten."

    struct Arguments: Sendable {
        @ToolParam("File path using allowed root prefix.")
        var path: String
        @ToolParam("UTF-8 text or base64 string depending on encoding.")
        var data: String?
        @ToolParam("utf8 (default) or base64.")
        var encoding: FileEncoding?
        var raw: [String: JSONValue]
    }

    let fs: FileSystemBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try fs.write(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.fsMove, path: "apple.fs.move", aliases: ["fs.promises.rename"])
struct FSMoveTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Move file"
    static let codeModeSummary = "Move file/directory within allowed sandbox roots. Fails rather than clobbering an existing destination unless overwrite is set, and never accepts a sandbox root as the destination."
    static let codeModeTags = ["filesystem", "io", "fs"]
    static let codeModeExample = "await apple.fs.move({ from: 'tmp:a.txt', to: 'tmp:b.txt' })"
    static let codeModeResultSummary = "Object with from/to resolved paths."

    struct Arguments: Sendable {
        @ToolParam("Source sandbox path.")
        var from: String
        @ToolParam("Destination sandbox path. Must name a path inside a root, not the root itself.")
        var to: String
        @ToolParam("Required as true to replace an existing destination; default false.")
        var overwrite: Bool?
        @ToolParam("Required as true alongside overwrite when the existing destination is a directory.")
        var recursive: Bool?
        var raw: [String: JSONValue]
    }

    let fs: FileSystemBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try fs.move(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.fsCopy, path: "apple.fs.copy", aliases: ["fs.promises.copyFile"])
struct FSCopyTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Copy file"
    static let codeModeSummary = "Copy file/directory within allowed sandbox roots. Fails rather than clobbering an existing destination unless overwrite is set, and never accepts a sandbox root as the destination."
    static let codeModeTags = ["filesystem", "io", "fs"]
    static let codeModeExample = "await apple.fs.copy({ from: 'tmp:a.txt', to: 'tmp:b.txt' })"
    static let codeModeResultSummary = "Object with from/to resolved paths."

    struct Arguments: Sendable {
        @ToolParam("Source sandbox path.")
        var from: String
        @ToolParam("Destination sandbox path. Must name a path inside a root, not the root itself.")
        var to: String
        @ToolParam("Required as true to replace an existing destination; default false.")
        var overwrite: Bool?
        @ToolParam("Required as true alongside overwrite when the existing destination is a directory.")
        var recursive: Bool?
        var raw: [String: JSONValue]
    }

    let fs: FileSystemBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try fs.copy(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.fsDelete, path: "apple.fs.delete", aliases: ["fs.promises.rm"])
struct FSDeleteTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Delete file"
    static let codeModeSummary = "Delete file/directory within allowed sandbox roots."
    static let codeModeTags = ["filesystem", "io", "fs"]
    static let codeModeExample = "await apple.fs.delete({ path: 'tmp:data.json' })"
    static let codeModeResultSummary = "Object with deleted flag and path."

    struct Arguments: Sendable {
        @ToolParam("Path to file or directory.")
        var path: String
        @ToolParam("Required as true when deleting a directory.")
        var recursive: Bool?
        var raw: [String: JSONValue]
    }

    let fs: FileSystemBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try fs.delete(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.fsStat, path: "apple.fs.stat", aliases: ["fs.promises.stat"])
struct FSStatTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Stat path"
    static let codeModeSummary = "Read file metadata within allowed sandbox roots."
    static let codeModeTags = ["filesystem", "io", "fs"]
    static let codeModeExample = "await apple.fs.stat({ path: 'tmp:data.json' })"
    static let codeModeResultSummary = "Object with path/isDirectory/size/createdAt/modifiedAt."

    struct Arguments: Sendable {
        @ToolParam("File or directory path.")
        var path: String
        var raw: [String: JSONValue]
    }

    let fs: FileSystemBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try fs.stat(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.fsMkdir, path: "apple.fs.mkdir", aliases: ["fs.promises.mkdir"])
struct FSMkdirTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Create directory"
    static let codeModeSummary = "Create directories within allowed sandbox roots."
    static let codeModeTags = ["filesystem", "io", "fs"]
    static let codeModeExample = "await apple.fs.mkdir({ path: 'tmp:artifacts', recursive: true })"
    static let codeModeResultSummary = "Object with created flag and path."

    struct Arguments: Sendable {
        @ToolParam("Directory path to create.")
        var path: String
        @ToolParam("Boolean; default true.")
        var recursive: Bool?
        var raw: [String: JSONValue]
    }

    let fs: FileSystemBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try fs.mkdir(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.fsExists, path: "apple.fs.exists")
struct FSExistsTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Check path exists"
    static let codeModeSummary = "Check if file/directory exists within allowed sandbox roots."
    static let codeModeTags = ["filesystem", "io", "fs"]
    static let codeModeExample = "await apple.fs.exists({ path: 'tmp:data.json' })"
    static let codeModeResultSummary = "Boolean."

    struct Arguments: Sendable {
        @ToolParam("File or directory path to check.")
        var path: String
        var raw: [String: JSONValue]
    }

    let fs: FileSystemBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try fs.exists(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.fsAccess, path: "apple.fs.access", aliases: ["fs.promises.access"])
struct FSAccessTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Check path access"
    static let codeModeSummary = "Check read/write access for path within allowed sandbox roots."
    static let codeModeTags = ["filesystem", "io", "fs"]
    static let codeModeExample = "await apple.fs.access({ path: 'tmp:data.json' })"
    static let codeModeResultSummary = "Object with readable/writable/path."

    struct Arguments: Sendable {
        @ToolParam("File or directory path to inspect.")
        var path: String
        var raw: [String: JSONValue]
    }

    let fs: FileSystemBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try fs.access(arguments: arguments.raw, context: context)
    }
}
