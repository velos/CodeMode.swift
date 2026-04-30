import CodeMode
import Foundation

public enum CodeModeEvalScenarios {
    public static let all: [CodeModeEvalScenario] = [
        filesystemRoundTrip,
        filesystemReadOnlyMinimal,
        filesystemMultiFileSummary,
        filesystemCopyMoveStat,
        filesystemNestedReportSummary,
        filesystemReadAPIShapes,
        filesystemRepairAfterInvalidArguments,
        filesystemCopyReadStatMinimal,
        filesystemPathPolicyEscape,
        filesystemDeleteDirectoryRequiresRecursive,
        filesystemCapabilityDenied,
        executionConsoleLogs,
        executionTimeout,
        reminderCatalogDiscovery,
        catalogFileSystemReadShape,
        catalogConsoleDiagnostics,
        searchRejectsNonFunctionProgram,
        catalogAliasAndPlatformPruning,
        catalogSystemUIPlatformPruning,
        catalogSharedSystemUIDiscovery,
        catalogIOSOnlySystemUIDiscovery,
        contactsPermissionDenied,
        weatherArgumentValidation,
        badFileSystemHelperSuggestion,
    ]

    public static let filesystemRoundTrip = CodeModeEvalScenario(
        id: "fs.round-trip",
        title: "Filesystem round trip",
        task: "First search for the filesystem write and read helpers, then create tmp:note.txt with the exact text \"hello eval\" and return the file contents as a string.",
        searchCode: """
        async () => {
            return {
                write: api.byJSName["apple.fs.write"],
                read: api.byJSName["fs.promises.readFile"]
            };
        }
        """,
        executeCode: """
        await apple.fs.write({ path: "tmp:note.txt", data: "hello eval" });
        return await fs.promises.readFile("tmp:note.txt", "utf8");
        """,
        allowedCapabilities: [.fsWrite, .fsRead],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.fsWrite, .fsRead],
            requiredSearchResultFragments: ["fs.write", "fs.read", "apple.fs.write", "fs.promises.readFile"],
            requiredExecuteCodeAlternativeFragments: [
                ["apple.fs.write", "fs.promises.writeFile"],
                ["fs.promises.readFile", "apple.fs.read"],
            ],
            expectedOutput: .string("hello eval")
        )
    )

    public static let filesystemReadOnlyMinimal = CodeModeEvalScenario(
        id: "fs.read-only-minimal",
        title: "Read-only capability minimization",
        task: "First search for the filesystem read helper, then read seeded file tmp:seed.txt without requesting write capabilities and return an object with text and length.",
        searchCode: """
        async () => {
            return api.byJSName["fs.promises.readFile"];
        }
        """,
        executeCode: """
        const text = await fs.promises.readFile("tmp:seed.txt", "utf8");
        return { text, length: text.length };
        """,
        allowedCapabilities: [.fsRead],
        seedFiles: [
            CodeModeEvalSeedFile(path: "tmp:seed.txt", text: "seed data")
        ],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.fsRead],
            forbiddenCapabilities: [.fsWrite],
            requiredSearchResultFragments: ["fs.read", "fs.promises.readFile"],
            requiredExecuteCodeAlternativeFragments: [["fs.promises.readFile", "apple.fs.read"]],
            expectedOutput: .object([
                "length": .number(9),
                "text": .string("seed data"),
            ])
        )
    )

    public static let filesystemMultiFileSummary = CodeModeEvalScenario(
        id: "fs.multi-file-summary",
        title: "Multi-step filesystem workflow",
        task: "First search for the filesystem write, list, and read helpers. Then create tmp:alpha.txt, tmp:beta.txt, and tmp:gamma.txt with text A, B, and C. List tmp:, read the txt files back in sorted name order, and return { count, names, combined }.",
        searchCode: """
        async () => {
            return api.references
                .filter(ref => ref.tags.includes("filesystem"))
                .filter(ref => ["fs.write", "fs.read", "fs.list"].includes(ref.capability))
                .map(ref => ({ capability: ref.capability, jsNames: ref.jsNames, requiredArguments: ref.requiredArguments }));
        }
        """,
        executeCode: """
        const items = [
            { name: "alpha.txt", value: "A" },
            { name: "beta.txt", value: "B" },
            { name: "gamma.txt", value: "C" }
        ];
        await Promise.all(items.map(item => fs.promises.writeFile(`tmp:${item.name}`, item.value, "utf8")));
        const entries = await apple.fs.list({ path: "tmp:" });
        const names = entries.map(entry => entry.name).filter(name => name.endsWith(".txt")).sort();
        const values = await Promise.all(names.map(name => fs.promises.readFile(`tmp:${name}`, "utf8")));
        return { count: names.length, names, combined: values.join("") };
        """,
        allowedCapabilities: [.fsWrite, .fsList, .fsRead],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.fsWrite, .fsList, .fsRead],
            requiredSearchResultFragments: ["fs.write", "fs.read", "fs.list"],
            requiredExecuteCodeAlternativeFragments: [
                ["apple.fs.list", "fs.promises.readdir"],
                ["fs.promises.readFile", "apple.fs.read"],
            ],
            expectedOutput: .object([
                "combined": .string("ABC"),
                "count": .number(3),
                "names": .array([
                    .string("alpha.txt"),
                    .string("beta.txt"),
                    .string("gamma.txt"),
                ]),
            ])
        )
    )

    public static let filesystemCopyMoveStat = CodeModeEvalScenario(
        id: "fs.copy-move-stat",
        title: "Copy, move, stat, exists workflow",
        task: "First search for the filesystem copy, move, stat, exists, and read helpers. Then copy seeded file tmp:source.txt to tmp:copy.txt, move the copy to tmp:moved.txt, and only after the move check existence for tmp:source.txt, tmp:copy.txt, and tmp:moved.txt. copyExists must reflect the post-move tmp:copy.txt path, so it should be false. Stat and read tmp:moved.txt, then return exactly { originalExists, copyExists, movedExists, isDirectory, size, text }.",
        searchCode: """
        async () => {
            const capabilities = ["fs.copy", "fs.move", "fs.stat", "fs.exists", "fs.read"];
            return api.references
                .filter(ref => capabilities.includes(ref.capability))
                .map(ref => ({ capability: ref.capability, jsNames: ref.jsNames }));
        }
        """,
        executeCode: """
        await fs.promises.copyFile("tmp:source.txt", "tmp:copy.txt");
        await fs.promises.rename("tmp:copy.txt", "tmp:moved.txt");
        const stat = await fs.promises.stat("tmp:moved.txt");
        const text = await fs.promises.readFile("tmp:moved.txt", "utf8");
        return {
            originalExists: await apple.fs.exists({ path: "tmp:source.txt" }),
            copyExists: await apple.fs.exists({ path: "tmp:copy.txt" }),
            movedExists: await apple.fs.exists({ path: "tmp:moved.txt" }),
            isDirectory: stat.isDirectory,
            size: stat.size,
            text
        };
        """,
        allowedCapabilities: [.fsCopy, .fsMove, .fsStat, .fsRead, .fsExists],
        seedFiles: [
            CodeModeEvalSeedFile(path: "tmp:source.txt", text: "copy me")
        ],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.fsCopy, .fsMove, .fsStat, .fsRead, .fsExists],
            requiredSearchResultFragments: ["fs.copy", "fs.move", "fs.stat", "fs.exists", "fs.read"],
            requiredExecuteCodeAlternativeFragments: [
                ["fs.promises.copyFile", "apple.fs.copy"],
                ["fs.promises.rename", "apple.fs.move"],
                ["fs.promises.stat", "apple.fs.stat"],
            ],
            expectedOutput: .object([
                "copyExists": .bool(false),
                "isDirectory": .bool(false),
                "movedExists": .bool(true),
                "originalExists": .bool(true),
                "size": .number(7),
                "text": .string("copy me"),
            ])
        )
    )

    public static let filesystemNestedReportSummary = CodeModeEvalScenario(
        id: "fs.nested-report-summary",
        title: "Nested filesystem report summary",
        task: "First search for filesystem mkdir, write, list, read, and stat helpers. Create tmp:reports/2026, write jan.txt with JAN, apr.txt with APR, and ignore.md with SKIP inside it. List the reports directory and the 2026 directory. For the result, directories must be an array of directory name strings only, so [\"2026\"], not full entry objects. names must include only .txt file names sorted alphabetically, combined must join only those .txt file contents with a | separator, and ignore.md must not appear in names or combined. Stat the 2026 directory and return exactly { directories, names, combined, reportDirIsDirectory }.",
        searchCode: """
        async () => {
            const capabilities = ["fs.mkdir", "fs.write", "fs.list", "fs.read", "fs.stat"];
            return api.references
                .filter(ref => capabilities.includes(ref.capability))
                .map(ref => ({ capability: ref.capability, jsNames: ref.jsNames, requiredArguments: ref.requiredArguments }));
        }
        """,
        executeCode: """
        await fs.promises.mkdir("tmp:reports/2026", { recursive: true });
        await fs.promises.writeFile("tmp:reports/2026/jan.txt", "JAN", "utf8");
        await fs.promises.writeFile("tmp:reports/2026/apr.txt", "APR", "utf8");
        await fs.promises.writeFile("tmp:reports/2026/ignore.md", "SKIP", "utf8");

        const rootEntries = await fs.promises.readdir("tmp:reports");
        const yearEntries = await fs.promises.readdir("tmp:reports/2026");
        const reportDir = await fs.promises.stat("tmp:reports/2026");
        const names = yearEntries
            .filter(entry => !entry.isDirectory && entry.name.endsWith(".txt"))
            .map(entry => entry.name)
            .sort();
        const values = await Promise.all(names.map(name => fs.promises.readFile(`tmp:reports/2026/${name}`, "utf8")));

        return {
            directories: rootEntries.filter(entry => entry.isDirectory).map(entry => entry.name).sort(),
            names,
            combined: values.join("|"),
            reportDirIsDirectory: reportDir.isDirectory
        };
        """,
        allowedCapabilities: [.fsMkdir, .fsWrite, .fsList, .fsRead, .fsStat],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.fsMkdir, .fsWrite, .fsList, .fsRead, .fsStat],
            forbiddenCapabilities: [.fsDelete, .fsMove, .fsCopy],
            requiredSearchResultFragments: ["fs.mkdir", "fs.write", "fs.list", "fs.read", "fs.stat"],
            requiredExecuteCodeAlternativeFragments: [
                ["fs.promises.mkdir", "apple.fs.mkdir"],
                ["fs.promises.writeFile", "apple.fs.write"],
                ["fs.promises.readdir", "apple.fs.list"],
                ["fs.promises.readFile", "apple.fs.read"],
                ["fs.promises.stat", "apple.fs.stat"],
            ],
            expectedOutput: .object([
                "combined": .string("APR|JAN"),
                "directories": .array([.string("2026")]),
                "names": .array([.string("apr.txt"), .string("jan.txt")]),
                "reportDirIsDirectory": .bool(true),
            ])
        )
    )

    public static let filesystemReadAPIShapes = CodeModeEvalScenario(
        id: "fs.read-api-shapes",
        title: "Filesystem read API shapes",
        task: "First search for apple.fs.read and fs.promises.readFile. Then read tmp:apple-shape.txt with apple.fs.read using object arguments and read tmp:node-shape.txt with fs.promises.readFile using positional arguments. Return { appleText, appleHasPath, nodeText, nodeType }.",
        searchCode: """
        async () => {
            return {
                appleRead: api.byJSName["apple.fs.read"],
                nodeRead: api.byJSName["fs.promises.readFile"]
            };
        }
        """,
        executeCode: """
        const appleResult = await apple.fs.read({ path: "tmp:apple-shape.txt", encoding: "utf8" });
        const nodeResult = await fs.promises.readFile("tmp:node-shape.txt", "utf8");
        return {
            appleText: appleResult.text,
            appleHasPath: typeof appleResult.path === "string",
            nodeText: nodeResult,
            nodeType: typeof nodeResult
        };
        """,
        allowedCapabilities: [.fsRead],
        seedFiles: [
            CodeModeEvalSeedFile(path: "tmp:apple-shape.txt", text: "apple object"),
            CodeModeEvalSeedFile(path: "tmp:node-shape.txt", text: "node string"),
        ],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.fsRead],
            forbiddenCapabilities: [.fsWrite],
            requiredSearchResultFragments: ["apple.fs.read", "fs.promises.readFile", "requiredArguments"],
            requiredExecuteCodeFragments: [
                "apple.fs.read",
                "fs.promises.readFile",
                "tmp:node-shape.txt",
            ],
            expectedOutput: .object([
                "appleHasPath": .bool(true),
                "appleText": .string("apple object"),
                "nodeText": .string("node string"),
                "nodeType": .string("string"),
            ])
        )
    )

    public static let filesystemRepairAfterInvalidArguments = CodeModeEvalScenario(
        id: "fs.repair-invalid-read-arguments",
        title: "Repair invalid filesystem read arguments",
        task: "First search for apple.fs.read. Then intentionally call apple.fs.read without a path and let executeJavaScript return the structured invalid-arguments error. Use that error to retry with path tmp:repair.txt and return the repaired file text.",
        searchCode: """
        async () => {
            return api.byJSName["apple.fs.read"];
        }
        """,
        executeCode: """
        return await apple.fs.read({ encoding: "utf8" });
        """,
        executeSteps: [
            CodeModeEvalExecuteStep(
                code: """
                const result = await apple.fs.read({ path: "tmp:repair.txt", encoding: "utf8" });
                return result.text;
                """,
                allowedCapabilities: [.fsRead]
            ),
        ],
        allowedCapabilities: [.fsRead],
        seedFiles: [
            CodeModeEvalSeedFile(path: "tmp:repair.txt", text: "repair target")
        ],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript, .executeJavaScript],
            exactAllowedCapabilities: [.fsRead],
            forbiddenCapabilities: [.fsWrite],
            requiredSearchResultFragments: ["fs.read", "apple.fs.read", "path"],
            requiredExecuteCodeFragments: ["tmp:repair.txt", "apple.fs.read"],
            expectedOutput: .string("repair target")
        )
    )

    public static let filesystemCopyReadStatMinimal = CodeModeEvalScenario(
        id: "fs.copy-read-stat-minimal",
        title: "Copy/read/stat capability minimization",
        task: "First search for filesystem copy, read, stat, and exists helpers. Copy seeded tmp:min-source.txt to tmp:min-copy.txt, read and stat only the copied file, check that the source still exists, and return { sourceExists, copiedText, copiedSize, copiedIsDirectory } without requesting write, move, list, or delete capabilities.",
        searchCode: """
        async () => {
            const capabilities = ["fs.copy", "fs.read", "fs.stat", "fs.exists"];
            return api.references
                .filter(ref => capabilities.includes(ref.capability))
                .map(ref => ({ capability: ref.capability, jsNames: ref.jsNames }));
        }
        """,
        executeCode: """
        await fs.promises.copyFile("tmp:min-source.txt", "tmp:min-copy.txt");
        const copiedText = await fs.promises.readFile("tmp:min-copy.txt", "utf8");
        const copiedStat = await fs.promises.stat("tmp:min-copy.txt");
        return {
            sourceExists: await apple.fs.exists({ path: "tmp:min-source.txt" }),
            copiedText,
            copiedSize: copiedStat.size,
            copiedIsDirectory: copiedStat.isDirectory
        };
        """,
        allowedCapabilities: [.fsCopy, .fsRead, .fsStat, .fsExists],
        seedFiles: [
            CodeModeEvalSeedFile(path: "tmp:min-source.txt", text: "minimal")
        ],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.fsCopy, .fsRead, .fsStat, .fsExists],
            forbiddenCapabilities: [.fsWrite, .fsMove, .fsList, .fsDelete],
            requiredSearchResultFragments: ["fs.copy", "fs.read", "fs.stat", "fs.exists"],
            requiredExecuteCodeAlternativeFragments: [
                ["fs.promises.copyFile", "apple.fs.copy"],
                ["fs.promises.readFile", "apple.fs.read"],
                ["fs.promises.stat", "apple.fs.stat"],
                ["apple.fs.exists"],
            ],
            expectedOutput: .object([
                "copiedIsDirectory": .bool(false),
                "copiedSize": .number(7),
                "copiedText": .string("minimal"),
                "sourceExists": .bool(true),
            ])
        )
    )

    public static let filesystemPathPolicyEscape = CodeModeEvalScenario(
        id: "fs.path-policy-escape",
        title: "Filesystem path policy blocks traversal",
        task: "First search for apple.fs.write, then attempt to write the text \"nope\" to tmp:../escape.txt. Do not catch the error in JavaScript; let executeJavaScript surface the structured path-policy failure.",
        searchCode: """
        async () => {
            return api.byJSName["apple.fs.write"];
        }
        """,
        executeCode: """
        return await apple.fs.write({ path: "tmp:../escape.txt", data: "nope" });
        """,
        allowedCapabilities: [.fsWrite],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.fsWrite],
            requiredSearchResultFragments: ["fs.write", "apple.fs.write"],
            requiredExecuteCodeFragments: ["apple.fs.write", "../escape.txt"],
            expectedErrorCode: "PATH_POLICY_VIOLATION"
        )
    )

    public static let filesystemDeleteDirectoryRequiresRecursive = CodeModeEvalScenario(
        id: "fs.delete-directory-recursive",
        title: "Directory delete requires recursive flag",
        task: "First search for apple.fs.delete, then attempt to delete seeded directory tmp:nested without recursive=true. Do not catch the error in JavaScript; let executeJavaScript surface the structured error with repair hints.",
        searchCode: """
        async () => {
            return api.byJSName["apple.fs.delete"];
        }
        """,
        executeCode: """
        return await apple.fs.delete({ path: "tmp:nested" });
        """,
        allowedCapabilities: [.fsDelete],
        seedFiles: [
            CodeModeEvalSeedFile(path: "tmp:nested/file.txt", text: "inside")
        ],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.fsDelete],
            requiredSearchResultFragments: ["fs.delete", "recursive"],
            requiredErrorSuggestionFragments: ["recursive:bool", "Example:"],
            requiredExecuteCodeFragments: ["apple.fs.delete"],
            expectedErrorCode: "INVALID_ARGUMENTS"
        )
    )

    public static let filesystemCapabilityDenied = CodeModeEvalScenario(
        id: "fs.capability-denied",
        title: "Capability allowlist denies undeclared reads",
        task: "First search for apple.fs.read, then call the filesystem read helper for seeded file tmp:secret.txt while passing no allowed capabilities. Do not catch the error in JavaScript; let executeJavaScript surface the structured capability-denied error.",
        searchCode: """
        async () => {
            return api.byJSName["apple.fs.read"];
        }
        """,
        executeCode: """
        return await apple.fs.read({ path: "tmp:secret.txt" });
        """,
        allowedCapabilities: [],
        seedFiles: [
            CodeModeEvalSeedFile(path: "tmp:secret.txt", text: "secret")
        ],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [],
            forbiddenCapabilities: [.fsRead],
            requiredSearchResultFragments: ["fs.read", "apple.fs.read"],
            requiredErrorSuggestionFragments: ["apple.fs.read"],
            requiredExecuteCodeFragments: ["apple.fs.read"],
            expectedErrorCode: "CAPABILITY_DENIED"
        )
    )

    public static let executionConsoleLogs = CodeModeEvalScenario(
        id: "execution.console-logs",
        title: "Execution streams console logs",
        task: "Log \"starting eval log\" and \"finishing eval log\", then return { ok: true }.",
        executeCode: """
        console.log("starting eval log");
        console.warn("finishing eval log");
        return { ok: true };
        """,
        allowedCapabilities: [],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.executeJavaScript],
            exactAllowedCapabilities: [],
            requiredExecutionLogFragments: ["starting eval log", "finishing eval log"],
            expectedOutput: .object(["ok": .bool(true)])
        )
    )

    public static let executionTimeout = CodeModeEvalScenario(
        id: "execution.timeout",
        title: "Unresolved promises time out",
        task: "Await a never-resolving JavaScript promise. Do not catch the error in JavaScript; let executeJavaScript surface the structured execution-timeout error.",
        executeCode: """
        await new Promise(() => {});
        return { never: true };
        """,
        allowedCapabilities: [],
        timeoutMs: 50,
        expectation: CodeModeEvalExpectation(
            toolOrder: [.executeJavaScript],
            exactAllowedCapabilities: [],
            requiredExecuteCodeFragments: ["new Promise"],
            expectedErrorCode: "EXECUTION_TIMEOUT"
        )
    )

    public static let reminderCatalogDiscovery = CodeModeEvalScenario(
        id: "catalog.reminder-create",
        title: "Reminder helper discovery",
        task: "Search the catalog for the JavaScript helper and capability used to create reminders. Return the capability, first JS name, and required arguments.",
        searchCode: """
        async () => {
            const wanted = ["reminders", "create"];
            return api.references
                .filter(ref => {
                    const haystack = [
                        ref.capability,
                        ...ref.jsNames,
                        ref.summary,
                        ref.example,
                        ...ref.tags
                    ].join(" ").toLowerCase();
                    return wanted.every(term => haystack.includes(term));
                })
                .map(ref => ({
                    capability: ref.capability,
                    jsName: ref.jsNames[0],
                    requiredArguments: ref.requiredArguments
                }));
        }
        """,
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI],
            requiredSearchResultFragments: ["reminders.write", "apple.reminders.createReminder", "title"]
        )
    )

    public static let catalogFileSystemReadShape = CodeModeEvalScenario(
        id: "catalog.fs-read-shape",
        title: "Catalog exposes filesystem read argument shapes",
        task: "Search the catalog by capability and direct JavaScript names for filesystem read. Return the fs.read capability reference, the apple.fs.read reference, and the fs.promises.readFile reference, including required arguments and result summary.",
        searchCode: """
        async () => {
            const byCapability = api.byCapability["fs.read"];
            const appleRead = api.byJSName["apple.fs.read"];
            const nodeRead = api.byJSName["fs.promises.readFile"];
            return {
                byCapability: {
                    capability: byCapability.capability,
                    jsNames: byCapability.jsNames,
                    requiredArguments: byCapability.requiredArguments,
                    resultSummary: byCapability.resultSummary
                },
                appleRead: {
                    capability: appleRead.capability,
                    requiredArguments: appleRead.requiredArguments,
                    example: appleRead.example
                },
                nodeRead: {
                    capability: nodeRead.capability,
                    requiredArguments: nodeRead.requiredArguments,
                    resultSummary: nodeRead.resultSummary
                }
            };
        }
        """,
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI],
            requiredSearchResultFragments: [
                "\"capability\":\"fs.read\"",
                "apple.fs.read",
                "fs.promises.readFile",
                "\"requiredArguments\":[\"path\"]",
                "text or base64",
            ]
        )
    )

    public static let catalogConsoleDiagnostics = CodeModeEvalScenario(
        id: "catalog.console-diagnostics",
        title: "Catalog search captures console diagnostics",
        task: "During catalog search, console.warn the exact text \"searching filesystem helpers\", then return the first two filesystem references.",
        searchCode: """
        async () => {
            console.warn("searching filesystem helpers");
            return api.references.filter(ref => ref.tags.includes("filesystem")).slice(0, 2);
        }
        """,
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI],
            requiredSearchResultFragments: ["filesystem"],
            requiredSearchDiagnosticFragments: ["searching filesystem helpers"]
        )
    )

    public static let searchRejectsNonFunctionProgram = CodeModeEvalScenario(
        id: "catalog.rejects-non-function",
        title: "Catalog search rejects non-function programs",
        task: "Call searchJavaScriptAPI with code that evaluates to the non-function object ({ not: \"a function\" }) and return the structured invalid-request error.",
        searchCode: """
        ({ not: "a function" })
        """,
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI],
            expectedErrorCode: "INVALID_REQUEST"
        )
    )

    public static let catalogAliasAndPlatformPruning = CodeModeEvalScenario(
        id: "catalog.alias-platform-pruning",
        title: "Catalog keeps canonical aliases and hides unsupported helpers",
        task: "Search for apple.fs.read, fs.promises.readFile, ios.fs.read, and the alarm.schedule capability. Use api.byJSName for JavaScript names, api.byCapability for capability IDs, and ?? null for missing values. Return an object where appleRead and nodeRead contain the discovered references, staleIOSAlias is null, and iOSAlarmSchedule is null on this macOS host.",
        searchCode: """
        async () => {
            return {
                appleRead: api.byJSName["apple.fs.read"] ?? null,
                nodeRead: api.byJSName["fs.promises.readFile"] ?? null,
                staleIOSAlias: api.byJSName["ios.fs.read"] ?? null,
                iOSAlarmSchedule: api.byCapability["alarm.schedule"] ?? null
            };
        }
        """,
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI],
            requiredSearchResultFragments: [
                "apple.fs.read",
                "fs.promises.readFile",
                "\"staleIOSAlias\":null",
                "\"iOSAlarmSchedule\":null",
            ]
        )
    )

    public static let catalogSystemUIPlatformPruning = CodeModeEvalScenario(
        id: "catalog.system-ui-platform-pruning",
        title: "Catalog hides system UI helpers on unsupported hosts",
        task: "Search for the system UI helper family. On this macOS host these iOS/visionOS helpers should be hidden, so return null for each missing helper.",
        searchCode: """
        async () => {
            const names = [
                "apple.calendar.pickCalendar",
                "apple.calendar.presentEvent",
                "apple.calendar.presentNewEvent",
                "apple.contacts.pick",
                "apple.contacts.presentContact",
                "apple.contacts.presentNewContact",
                "apple.photos.pick",
                "apple.documents.pick",
                "apple.documents.scan",
                "apple.share.present",
                "apple.quicklook.preview",
                "apple.camera.capture",
                "apple.mail.compose",
                "apple.messages.compose",
                "apple.web.present",
                "apple.auth.webAuthenticate",
                "apple.ui.presentAlert"
            ];
            return Object.fromEntries(names.map(name => [name, api.byJSName[name] ?? null]));
        }
        """,
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI],
            requiredSearchResultFragments: [
                "\"apple.auth.webAuthenticate\":null",
                "\"apple.calendar.pickCalendar\":null",
                "\"apple.calendar.presentEvent\":null",
                "\"apple.calendar.presentNewEvent\":null",
                "\"apple.camera.capture\":null",
                "\"apple.contacts.pick\":null",
                "\"apple.contacts.presentContact\":null",
                "\"apple.contacts.presentNewContact\":null",
                "\"apple.documents.pick\":null",
                "\"apple.documents.scan\":null",
                "\"apple.mail.compose\":null",
                "\"apple.messages.compose\":null",
                "\"apple.photos.pick\":null",
                "\"apple.quicklook.preview\":null",
                "\"apple.share.present\":null",
                "\"apple.ui.presentAlert\":null",
                "\"apple.web.present\":null",
            ]
        )
    )

    public static let catalogSharedSystemUIDiscovery = CodeModeEvalScenario(
        id: "catalog.system-ui-shared-discovery",
        title: "Catalog discovers shared iOS and visionOS system UI helpers",
        task: "Search the iOS catalog for Files document picking, share sheet, Quick Look preview, Safari presentation, web authentication, and custom alert helpers. Return each capability, JavaScript name, arguments, hints, and result summary.",
        catalogPlatform: .iOS,
        searchCode: """
        async () => {
            const names = [
                "apple.documents.pick",
                "apple.share.present",
                "apple.quicklook.preview",
                "apple.web.present",
                "apple.auth.webAuthenticate",
                "apple.ui.presentAlert"
            ];
            return Object.fromEntries(names.map(name => {
                const ref = api.byJSName[name];
                return [name, ref ? {
                    capability: ref.capability,
                    jsNames: ref.jsNames,
                    requiredArguments: ref.requiredArguments,
                    optionalArguments: ref.optionalArguments,
                    argumentHints: ref.argumentHints,
                    resultSummary: ref.resultSummary
                } : null];
            }));
        }
        """,
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI],
            requiredSearchResultFragments: [
                "apple.auth.webAuthenticate",
                "apple.documents.pick",
                "apple.quicklook.preview",
                "apple.share.present",
                "apple.ui.presentAlert",
                "apple.web.present",
                "auth.ui.webAuthenticate",
                "buttonID",
                "buttons",
                "callbackURL",
                "callbackURLScheme",
                "completed",
                "contentTypes",
                "documents.ui.pick",
                "excludedActivityTypes",
                "outputDirectory",
                "quicklook.ui.preview",
                "share.ui.present",
                "ui.alert.present",
                "web.ui.present",
            ]
        )
    )

    public static let catalogIOSOnlySystemUIDiscovery = CodeModeEvalScenario(
        id: "catalog.system-ui-ios-only-discovery",
        title: "Catalog discovers iOS-only system UI helpers",
        task: "Search the iOS catalog for document scanning, camera capture, mail compose, and Messages compose helpers. Return each capability, JavaScript name, arguments, hints, and result summary.",
        catalogPlatform: .iOS,
        searchCode: """
        async () => {
            const names = [
                "apple.documents.scan",
                "apple.camera.capture",
                "apple.mail.compose",
                "apple.messages.compose"
            ];
            return Object.fromEntries(names.map(name => {
                const ref = api.byJSName[name];
                return [name, ref ? {
                    capability: ref.capability,
                    jsNames: ref.jsNames,
                    requiredArguments: ref.requiredArguments,
                    optionalArguments: ref.optionalArguments,
                    argumentHints: ref.argumentHints,
                    resultSummary: ref.resultSummary
                } : null];
            }));
        }
        """,
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI],
            requiredSearchResultFragments: [
                "apple.camera.capture",
                "apple.documents.scan",
                "apple.mail.compose",
                "apple.messages.compose",
                "artifactID",
                "attachments",
                "camera.ui.capture",
                "documents.ui.scan",
                "mail.ui.compose",
                "mediaType",
                "messages.ui.compose",
                "outputDirectory",
                "recipients",
                "sent",
            ]
        )
    )

    public static let contactsPermissionDenied = CodeModeEvalScenario(
        id: "contacts.permission-denied",
        title: "Permission denial stays structured",
        task: "First search for apple.contacts.search, then search contacts for \"Alex\" with limit 5 while Contacts permission is denied. Do not catch the error in JavaScript; pass contacts.search in allowedCapabilities and let executeJavaScript surface the structured permission-denied error.",
        searchCode: """
        async () => {
            return api.byJSName["apple.contacts.search"];
        }
        """,
        executeCode: """
        return await apple.contacts.search({ query: "Alex", limit: 5 });
        """,
        allowedCapabilities: [.contactsSearch],
        permissions: CodeModeEvalPermissions(statuses: [.contacts: .denied]),
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.contactsSearch],
            requiredSearchResultFragments: ["contacts.search", "apple.contacts.search"],
            requiredExecuteCodeFragments: ["apple.contacts.search"],
            expectedErrorCode: "PERMISSION_DENIED"
        )
    )

    public static let weatherArgumentValidation = CodeModeEvalScenario(
        id: "weather.argument-validation",
        title: "Argument validation gives repair hints",
        task: "First search for apple.weather.getCurrentWeather, then call it with latitude 37.77 and no longitude. Do not catch the error in JavaScript; let executeJavaScript surface the structured argument-validation error and repair hints.",
        searchCode: """
        async () => {
            return api.byJSName["apple.weather.getCurrentWeather"];
        }
        """,
        executeCode: """
        return await apple.weather.getCurrentWeather({ latitude: 37.77 });
        """,
        allowedCapabilities: [.weatherRead],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.weatherRead],
            requiredSearchResultFragments: ["weather.read", "longitude"],
            requiredErrorSuggestionFragments: ["longitude:number", "Example:"],
            requiredExecuteCodeFragments: ["apple.weather.getCurrentWeather"],
            expectedErrorCode: "INVALID_ARGUMENTS"
        )
    )

    public static let badFileSystemHelperSuggestion = CodeModeEvalScenario(
        id: "fs.bad-helper-suggestion",
        title: "Bad helper names get suggestions",
        task: "First search for apple.fs.read, then mistype the filesystem read helper as apple.fs.reed for tmp:missing.txt. Do not catch the error in JavaScript; let executeJavaScript surface the structured missing-helper error with suggestions.",
        searchCode: """
        async () => {
            return api.byJSName["apple.fs.read"];
        }
        """,
        executeCode: """
        return await apple.fs.reed({ path: "tmp:missing.txt" });
        """,
        allowedCapabilities: [.fsRead],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.fsRead],
            requiredSearchResultFragments: ["fs.read", "apple.fs.read"],
            requiredErrorSuggestionFragments: ["apple.fs.read"],
            requiredExecuteCodeFragments: ["apple.fs.reed"],
            expectedErrorCode: "JS_API_NOT_FOUND",
            expectedFunctionName: "apple.fs.reed"
        )
    )
}
