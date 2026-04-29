import CodeMode
import Foundation

public enum CodeModeEvalScenarios {
    public static let all: [CodeModeEvalScenario] = [
        filesystemRoundTrip,
        filesystemReadOnlyMinimal,
        filesystemMultiFileSummary,
        filesystemCopyMoveStat,
        filesystemPathPolicyEscape,
        filesystemDeleteDirectoryRequiresRecursive,
        filesystemCapabilityDenied,
        executionConsoleLogs,
        executionTimeout,
        reminderCatalogDiscovery,
        catalogConsoleDiagnostics,
        searchRejectsNonFunctionProgram,
        catalogAliasAndPlatformPruning,
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
        task: "First search for the filesystem copy, move, stat, exists, and read helpers. Then copy seeded file tmp:source.txt to tmp:copy.txt, move the copy to tmp:moved.txt, stat and read tmp:moved.txt, and return booleans for originalExists, copyExists, movedExists plus isDirectory, size, and text.",
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
