import Foundation

extension DefaultCapabilityRegistrationBuilder {
    func networkRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                descriptor: .init(
                    id: .networkFetch,
                    title: "Fetch HTTP resource",
                    summary: "Perform HTTP(S) requests through URLSession via a fetch-compatible API.",
                    tags: ["network", "http", "fetch"],
                    example: "await fetch('https://api.example.com/data').then(r => r.json())",
                    requiredArguments: ["url"],
                    optionalArguments: [
                        "options.method",
                        "options.headers",
                        "options.body",
                        "options.bodyBase64",
                        "options.timeoutMs",
                        "options.responseEncoding",
                    ],
                    argumentHints: [
                        "url": "Absolute HTTP(S) URL string.",
                        "options.method": "HTTP method; defaults to GET.",
                        "options.headers": "Object of header key/value string pairs.",
                        "options.body": "UTF-8 request body string.",
                        "options.bodyBase64": "Base64-encoded request body. Mutually exclusive with options.body.",
                        "options.timeoutMs": "Request and bridge wait timeout in milliseconds; defaults to 30000.",
                        "options.responseEncoding": "text (default) or base64.",
                    ],
                    resultSummary: "Object with ok/status/statusText/headers/bodyText or bodyBase64."
                ),
                handler: { args, context in
                    try network.fetch(arguments: args, context: context)
                }
            ),
        ]
    }


    func keychainRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                descriptor: .init(
                    id: .keychainRead,
                    title: "Read Keychain value",
                    summary: "Read a string value from app-scoped Keychain storage.",
                    tags: ["security", "token", "keychain"],
                    example: "await apple.keychain.get('auth_token')",
                    requiredArguments: ["key"],
                    argumentHints: [
                        "key": "Logical key for this secret value.",
                    ],
                    resultSummary: "Object { key, value } or null when the key does not exist."
                ),
                handler: { args, _ in
                    try keychain.read(arguments: args)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .keychainWrite,
                    title: "Write Keychain value",
                    summary: "Store or update a string value in app-scoped Keychain storage.",
                    tags: ["security", "token", "keychain"],
                    example: "await apple.keychain.set('auth_token', token)",
                    requiredArguments: ["key"],
                    optionalArguments: ["value"],
                    argumentHints: [
                        "key": "Logical key for this secret value.",
                        "value": "Secret string value. Defaults to empty string when omitted.",
                    ],
                    resultSummary: "Object { key, written: true }."
                ),
                handler: { args, _ in
                    try keychain.write(arguments: args)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .keychainDelete,
                    title: "Delete Keychain value",
                    summary: "Delete an app-scoped Keychain value.",
                    tags: ["security", "token", "keychain"],
                    example: "await apple.keychain.delete('auth_token')",
                    requiredArguments: ["key"],
                    argumentHints: [
                        "key": "Logical key for value removal.",
                    ],
                    resultSummary: "Object { key, deleted: true }."
                ),
                handler: { args, _ in
                    try keychain.delete(arguments: args)
                }
            ),
        ]
    }


    func filesystemRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                descriptor: .init(
                    id: .fsList,
                    title: "List directory",
                    summary: "List files/directories within allowed sandbox roots as entry objects.",
                    tags: ["filesystem", "io", "fs"],
                    example: "await apple.fs.list({ path: 'tmp:' })",
                    requiredArguments: ["path"],
                    argumentHints: [
                        "path": "Directory path using allowed root prefix (tmp:, caches:, documents:).",
                    ],
                    resultSummary: "Array of entry objects with name/path/isDirectory/size. Use entry.name for filenames; fs.promises.readdir returns the same entry objects, not strings."
                ),
                handler: { args, context in
                    try fs.list(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .fsRead,
                    title: "Read file",
                    summary: "Read text/base64 file data within allowed sandbox roots.",
                    tags: ["filesystem", "io", "fs"],
                    example: "await apple.fs.read({ path: 'tmp:data.json', encoding: 'utf8' })",
                    requiredArguments: ["path"],
                    optionalArguments: ["encoding"],
                    argumentHints: [
                        "path": "File path using allowed root prefix.",
                        "encoding": "utf8 (default) or base64.",
                    ],
                    resultSummary: "Object with path plus text or base64 field."
                ),
                handler: { args, context in
                    try fs.read(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .fsWrite,
                    title: "Write file",
                    summary: "Write text/base64 file data within allowed sandbox roots.",
                    tags: ["filesystem", "io", "fs"],
                    example: "await apple.fs.write({ path: 'tmp:data.json', data: '{\"ok\":true}' })",
                    requiredArguments: ["path"],
                    optionalArguments: ["data", "encoding"],
                    argumentHints: [
                        "path": "File path using allowed root prefix.",
                        "data": "UTF-8 text or base64 string depending on encoding.",
                        "encoding": "utf8 (default) or base64.",
                    ],
                    resultSummary: "Object with path and bytesWritten."
                ),
                handler: { args, context in
                    try fs.write(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .fsMove,
                    title: "Move file",
                    summary: "Move file/directory within allowed sandbox roots.",
                    tags: ["filesystem", "io", "fs"],
                    example: "await apple.fs.move({ from: 'tmp:a.txt', to: 'tmp:b.txt' })",
                    requiredArguments: ["from", "to"],
                    argumentHints: [
                        "from": "Source sandbox path.",
                        "to": "Destination sandbox path.",
                    ],
                    resultSummary: "Object with from/to resolved paths."
                ),
                handler: { args, context in
                    try fs.move(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .fsCopy,
                    title: "Copy file",
                    summary: "Copy file/directory within allowed sandbox roots.",
                    tags: ["filesystem", "io", "fs"],
                    example: "await apple.fs.copy({ from: 'tmp:a.txt', to: 'tmp:b.txt' })",
                    requiredArguments: ["from", "to"],
                    argumentHints: [
                        "from": "Source sandbox path.",
                        "to": "Destination sandbox path.",
                    ],
                    resultSummary: "Object with from/to resolved paths."
                ),
                handler: { args, context in
                    try fs.copy(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .fsDelete,
                    title: "Delete file",
                    summary: "Delete file/directory within allowed sandbox roots.",
                    tags: ["filesystem", "io", "fs"],
                    example: "await apple.fs.delete({ path: 'tmp:data.json' })",
                    requiredArguments: ["path"],
                    optionalArguments: ["recursive"],
                    argumentHints: [
                        "path": "Path to file or directory.",
                        "recursive": "Required as true when deleting a directory.",
                    ],
                    resultSummary: "Object with deleted flag and path."
                ),
                handler: { args, context in
                    try fs.delete(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .fsStat,
                    title: "Stat path",
                    summary: "Read file metadata within allowed sandbox roots.",
                    tags: ["filesystem", "io", "fs"],
                    example: "await apple.fs.stat({ path: 'tmp:data.json' })",
                    requiredArguments: ["path"],
                    argumentHints: [
                        "path": "File or directory path.",
                    ],
                    resultSummary: "Object with path/isDirectory/size/createdAt/modifiedAt."
                ),
                handler: { args, context in
                    try fs.stat(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .fsMkdir,
                    title: "Create directory",
                    summary: "Create directories within allowed sandbox roots.",
                    tags: ["filesystem", "io", "fs"],
                    example: "await apple.fs.mkdir({ path: 'tmp:artifacts', recursive: true })",
                    requiredArguments: ["path"],
                    optionalArguments: ["recursive"],
                    argumentHints: [
                        "path": "Directory path to create.",
                        "recursive": "Boolean; default true.",
                    ],
                    resultSummary: "Object with created flag and path."
                ),
                handler: { args, context in
                    try fs.mkdir(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .fsExists,
                    title: "Check path exists",
                    summary: "Check if file/directory exists within allowed sandbox roots.",
                    tags: ["filesystem", "io", "fs"],
                    example: "await apple.fs.exists({ path: 'tmp:data.json' })",
                    requiredArguments: ["path"],
                    argumentHints: [
                        "path": "File or directory path to check.",
                    ],
                    resultSummary: "Boolean."
                ),
                handler: { args, context in
                    try fs.exists(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .fsAccess,
                    title: "Check path access",
                    summary: "Check read/write access for path within allowed sandbox roots.",
                    tags: ["filesystem", "io", "fs"],
                    example: "await apple.fs.access({ path: 'tmp:data.json' })",
                    requiredArguments: ["path"],
                    argumentHints: [
                        "path": "File or directory path to inspect.",
                    ],
                    resultSummary: "Object with readable/writable/path."
                ),
                handler: { args, context in
                    try fs.access(arguments: args, context: context)
                }
            ),
        ]
    }
}
