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
        executionUnsettleablePromise,
        executionTimerBackoff,
        filesystemWholeJobInOneScript,
        reminderCatalogDiscovery,
        catalogFileSystemReadShape,
        catalogConsoleDiagnostics,
        searchRejectsNonFunctionProgram,
        catalogAliasAndPlatformPruning,
        catalogSystemUIPlatformPruning,
        catalogDocumentSystemUIDiscovery,
        catalogInteractionSystemUIDiscovery,
        catalogPhotoCameraSystemUIDiscovery,
        catalogIOSOnlySystemUIDiscovery,
        contactsPermissionDenied,
        weatherArgumentValidation,
        keychainRoundTrip,
        notificationsPermissionRequest,
        locationPermissionStatus,
        networkInvalidURL,
        calendarLifecycleCatalogDiscovery,
        networkBase64TimeoutCatalogDiscovery,
        notificationsDeliveredContentCatalogDiscovery,
        systemUIParameterCatalogDiscovery,
        cloudKitBigTicketCatalogDiscovery,
        notificationsRemoteCatalogDiscovery,
        speechBigTicketCatalogDiscovery,
        mapsBigTicketCatalogDiscovery,
        foundationModelsAppIntentsActivityCatalogDiscovery,
        walletMusicStoreKitSafetyCatalogDiscovery,
        cloudKitInvalidDatabaseValidation,
        mapsInvalidTransportValidation,
        storeKitEmptyProductIDsValidation,
        notificationsMalformedCategoriesValidation,
        activityInvalidDismissalPolicyValidation,
        musicInvalidPlaybackActionValidation,
        calendarWritePermissionDenied,
        homeWriteValidation,
        mediaMetadataValidation,
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
        executeSteps: [
            // Deliberately wrong, so the next step can repair from the structured
            // error. Marked so the runner does not treat it as the run failing.
            CodeModeEvalExecuteStep(
                code: """
                return await apple.fs.read({ encoding: "utf8" });
                """,
                allowedCapabilities: [.fsRead],
                expectsFailure: true
            ),
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

    public static let executionUnsettleablePromise = CodeModeEvalScenario(
        id: "execution.unsettleable-promise",
        title: "Unresolvable promises are reported, not waited out",
        task: "Await a never-resolving JavaScript promise. Do not catch the error in JavaScript; let executeJavaScript surface the structured error.",
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
            expectedErrorCode: "JS_RUNTIME_ERROR"
        )
    )

    public static let executionTimeout = CodeModeEvalScenario(
        id: "execution.timeout",
        title: "CPU-bound scripts hit the execution timeout",
        task: "Run a CPU-bound infinite loop. Do not catch the error in JavaScript; let executeJavaScript surface the structured execution-timeout error.",
        executeCode: """
        while (true) {}
        """,
        allowedCapabilities: [],
        timeoutMs: 200,
        expectation: CodeModeEvalExpectation(
            toolOrder: [.executeJavaScript],
            exactAllowedCapabilities: [],
            requiredExecuteCodeFragments: ["while"],
            expectedErrorCode: "EXECUTION_TIMEOUT"
        )
    )

    public static let filesystemWholeJobInOneScript = CodeModeEvalScenario(
        id: "fs.whole-job-one-script",
        title: "A multi-step job runs as one script",
        task: "Read every .json receipt in documents:receipts, total the amounts for trip 'lisbon', and return { total, count }. Do the whole job in a single executeJavaScript call — list, read, filter, and sum inside the script — and return only the totals, not the receipts.",
        searchCode: """
        async () => {
            return api.references
                .filter(ref => ["fs.list", "fs.read"].includes(ref.capability))
                .map(ref => ref.dts)
                .join("\\n\\n");
        }
        """,
        executeCode: """
        const entries = await apple.fs.list({ path: 'documents:receipts' });
        let total = 0;
        let count = 0;
        for (const entry of entries) {
            if (entry.isDirectory || !entry.name.endsWith('.json')) continue;
            const { text } = await apple.fs.read({ path: entry.path });
            const receipt = JSON.parse(text);
            if (receipt.trip !== 'lisbon') continue;
            total += receipt.amount;
            count += 1;
        }
        return { total, count };
        """,
        allowedCapabilities: [.fsList, .fsRead],
        seedFiles: [
            CodeModeEvalSeedFile(path: "documents:receipts/a.json", text: #"{"trip":"lisbon","amount":12}"#),
            CodeModeEvalSeedFile(path: "documents:receipts/b.json", text: #"{"trip":"porto","amount":99}"#),
            CodeModeEvalSeedFile(path: "documents:receipts/c.json", text: #"{"trip":"lisbon","amount":30}"#),
        ],
        expectation: CodeModeEvalExpectation(
            // One search, one execute. A transcript that splits the list/read/sum
            // across several executions fails here — that is the whole point of
            // the scenario, and it only has teeth against real LLM transcripts.
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.fsList, .fsRead],
            forbiddenCapabilities: [.fsWrite, .fsDelete, .fsMove],
            requiredExecuteCodeFragments: ["apple.fs.list", "apple.fs.read"],
            expectedOutput: .object(["total": .number(42), "count": .number(2)])
        )
    )

    public static let executionTimerBackoff = CodeModeEvalScenario(
        id: "execution.timer-backoff",
        title: "setTimeout honours its delay",
        task: "Use setTimeout to wait before returning, and cancel a second timer with clearTimeout so its callback never runs.",
        executeCode: """
        const marks = [];
        const cancelled = setTimeout(() => { marks.push('cancelled'); }, 5);
        clearTimeout(cancelled);
        await new Promise(resolve => setTimeout(resolve, 20));
        marks.push('resumed');
        return { marks };
        """,
        allowedCapabilities: [],
        timeoutMs: 2_000,
        expectation: CodeModeEvalExpectation(
            toolOrder: [.executeJavaScript],
            exactAllowedCapabilities: [],
            requiredExecuteCodeFragments: ["setTimeout"],
            expectedOutput: .object(["marks": .array([.string("resumed")])])
        )
    )

    public static let reminderCatalogDiscovery = CodeModeEvalScenario(
        id: "catalog.reminder-create",
        title: "Reminder helper discovery",
        task: "Search the catalog for the JavaScript helper and capability used to create reminders. Return the capability, first JS name, optional arguments, and argument hints.",
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
                    optionalArguments: ref.optionalArguments,
                    argumentHints: ref.argumentHints
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
                "apple.photos.presentLimitedLibraryPicker",
                "apple.documents.pick",
                "apple.documents.export",
                "apple.documents.save",
                "apple.documents.openIn",
                "apple.documents.scan",
                "apple.share.present",
                "apple.quicklook.preview",
                "apple.camera.capture",
                "apple.camera.scanData",
                "apple.mail.compose",
                "apple.messages.compose",
                "apple.print.present",
                "apple.web.present",
                "apple.auth.webAuthenticate",
                "apple.ui.presentAlert",
                "apple.ui.presentPrompt",
                "apple.settings.open"
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
                "\"apple.documents.export\":null",
                "\"apple.documents.openIn\":null",
                "\"apple.documents.pick\":null",
                "\"apple.documents.save\":null",
                "\"apple.documents.scan\":null",
                "\"apple.camera.scanData\":null",
                "\"apple.mail.compose\":null",
                "\"apple.messages.compose\":null",
                "\"apple.photos.presentLimitedLibraryPicker\":null",
                "\"apple.photos.pick\":null",
                "\"apple.print.present\":null",
                "\"apple.quicklook.preview\":null",
                "\"apple.settings.open\":null",
                "\"apple.share.present\":null",
                "\"apple.ui.presentAlert\":null",
                "\"apple.ui.presentPrompt\":null",
                "\"apple.web.present\":null",
            ]
        )
    )

    public static let catalogDocumentSystemUIDiscovery = CodeModeEvalScenario(
        id: "catalog.system-ui-documents-discovery",
        title: "Catalog discovers document system UI helpers",
        task: "Search the iOS catalog for Files document picking, document export/save, document open-in, Quick Look preview, and print helpers. Return each capability, JavaScript name, arguments, hints, and result summary.",
        catalogPlatform: .iOS,
        searchCode: """
        async () => {
            const names = [
                "apple.documents.pick",
                "apple.documents.export",
                "apple.documents.openIn",
                "apple.quicklook.preview",
                "apple.print.present"
            ];
            return Object.fromEntries(names.map(name => {
                const ref = api.byJSName[name];
                return [name, ref ? {
                    capability: ref.capability,
                    jsNames: ref.jsNames,
                    summary: ref.summary,
                    tags: ref.tags,
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
                "apple.documents.export",
                "apple.documents.openIn",
                "apple.documents.pick",
                "apple.documents.save",
                "apple.print.present",
                "apple.quicklook.preview",
                "completed",
                "contentTypes",
                "documents.ui.export",
                "documents.ui.openIn",
                "documents.ui.pick",
                "jobName",
                "print.ui.present",
                "quicklook.ui.preview",
            ]
        )
    )

    public static let catalogInteractionSystemUIDiscovery = CodeModeEvalScenario(
        id: "catalog.system-ui-interaction-discovery",
        title: "Catalog discovers interaction system UI helpers",
        task: "Search the iOS catalog for share sheet, Safari, web authentication, alert, prompt, and settings helpers. Return each capability, JavaScript name, arguments, hints, and result summary.",
        catalogPlatform: .iOS,
        searchCode: """
        async () => {
            const names = [
                "apple.share.present",
                "apple.web.present",
                "apple.auth.webAuthenticate",
                "apple.ui.presentAlert",
                "apple.ui.presentPrompt",
                "apple.settings.open"
            ];
            return Object.fromEntries(names.map(name => {
                const ref = api.byJSName[name];
                return [name, ref ? {
                    capability: ref.capability,
                    jsNames: ref.jsNames,
                    summary: ref.summary,
                    tags: ref.tags,
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
                "apple.settings.open",
                "apple.share.present",
                "apple.ui.presentAlert",
                "apple.ui.presentPrompt",
                "apple.web.present",
                "auth.ui.webAuthenticate",
                "buttonID",
                "buttons",
                "callbackURL",
                "callbackURLScheme",
                "excludedActivityTypes",
                "fields",
                "settings.ui.open",
                "share.ui.present",
                "ui.alert.present",
                "ui.prompt.present",
                "web.ui.present",
            ]
        )
    )

    public static let catalogPhotoCameraSystemUIDiscovery = CodeModeEvalScenario(
        id: "catalog.system-ui-photo-camera-discovery",
        title: "Catalog discovers photo and camera system UI helpers",
        task: "Search the iOS catalog for photo picking, Photos limited-library management, and live camera data scanning helpers. Return each capability, JavaScript name, arguments, hints, and result summary.",
        catalogPlatform: .iOS,
        searchCode: """
        async () => {
            const names = [
                "apple.photos.pick",
                "apple.photos.presentLimitedLibraryPicker",
                "apple.camera.scanData"
            ];
            return Object.fromEntries(names.map(name => {
                const ref = api.byJSName[name];
                return [name, ref ? {
                    capability: ref.capability,
                    jsNames: ref.jsNames,
                    summary: ref.summary,
                    tags: ref.tags,
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
                "apple.camera.scanData",
                "apple.photos.pick",
                "apple.photos.presentLimitedLibraryPicker",
                "camera.ui.scanData",
                "limit",
                "mediaType",
                "outputDirectory",
                "photos.ui.pick",
                "photos.ui.presentLimitedLibraryPicker",
                "recognizedDataTypes",
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
                    summary: ref.summary,
                    tags: ref.tags,
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

    public static let keychainRoundTrip = CodeModeEvalScenario(
        id: "keychain.round-trip",
        title: "Keychain round trip",
        task: "First search for the keychain get, set, and delete helpers. Then write the exact value \"eval-secret\" to a temporary keychain key, read it back, delete it, read the key again, and return exactly { value, missing } where value is the string you read before deletion and missing is the post-delete read result, which should be null.",
        searchCode: """
        async () => {
            return {
                get: api.byJSName["apple.keychain.get"],
                set: api.byJSName["apple.keychain.set"],
                delete: api.byJSName["apple.keychain.delete"]
            };
        }
        """,
        executeCode: """
        const key = "codemode-eval-keychain-" + String(Date.now());
        await apple.keychain.set(key, "eval-secret");
        const read = await apple.keychain.get(key);
        await apple.keychain.delete(key);
        const missing = await apple.keychain.get(key);
        return {
            value: read ? read.value : null,
            missing
        };
        """,
        allowedCapabilities: [.keychainWrite, .keychainRead, .keychainDelete],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.keychainWrite, .keychainRead, .keychainDelete],
            requiredSearchResultFragments: [
                "keychain.read",
                "keychain.write",
                "keychain.delete",
                "apple.keychain.get",
                "apple.keychain.set",
                "apple.keychain.delete",
            ],
            requiredExecuteCodeFragments: [
                "apple.keychain.set",
                "apple.keychain.get",
                "apple.keychain.delete",
            ],
            expectedOutput: .object([
                "missing": .null,
                "value": .string("eval-secret"),
            ])
        )
    )

    public static let notificationsPermissionRequest = CodeModeEvalScenario(
        id: "notifications.permission-request",
        title: "Notifications permission request",
        task: "First search for apple.notifications.requestPermission, then request notification permission and return the status payload.",
        searchCode: """
        async () => {
            return api.byJSName["apple.notifications.requestPermission"];
        }
        """,
        executeCode: """
        return await apple.notifications.requestPermission();
        """,
        allowedCapabilities: [.notificationsPermissionRequest],
        permissions: CodeModeEvalPermissions(
            statuses: [.notifications: .notDetermined],
            requestStatuses: [.notifications: .granted]
        ),
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.notificationsPermissionRequest],
            requiredSearchResultFragments: [
                "notifications.permission.request",
                "apple.notifications.requestPermission",
            ],
            requiredExecuteCodeFragments: ["apple.notifications.requestPermission"],
            expectedOutput: .object([
                "granted": .bool(true),
                "status": .string("granted"),
            ])
        )
    )

    public static let locationPermissionStatus = CodeModeEvalScenario(
        id: "location.permission-status",
        title: "Location permission status",
        task: "First search for apple.location.getPermissionStatus, then read the current location permission status without requesting location coordinates and return exactly { status }.",
        searchCode: """
        async () => {
            return api.byJSName["apple.location.getPermissionStatus"];
        }
        """,
        executeCode: """
        const status = await apple.location.getPermissionStatus();
        return { status };
        """,
        allowedCapabilities: [.locationRead],
        permissions: CodeModeEvalPermissions(statuses: [.locationWhenInUse: .restricted]),
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.locationRead],
            forbiddenCapabilities: [.locationPermissionRequest],
            requiredSearchResultFragments: [
                "location.read",
                "apple.location.getPermissionStatus",
            ],
            requiredExecuteCodeFragments: ["apple.location.getPermissionStatus"],
            expectedOutput: .object(["status": .string("restricted")])
        )
    )

    public static let networkInvalidURL = CodeModeEvalScenario(
        id: "network.invalid-url",
        title: "Network invalid URL",
        task: "First search for fetch. Then call fetch with the invalid URL string \"http://%zz\" and let executeJavaScript surface the structured invalid-arguments error.",
        searchCode: """
        async () => {
            return api.byJSName["fetch"];
        }
        """,
        executeCode: """
        return await fetch("http://%zz");
        """,
        allowedCapabilities: [.networkFetch],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.networkFetch],
            requiredSearchResultFragments: ["network.fetch", "fetch"],
            requiredErrorSuggestionFragments: ["url", "Example:"],
            requiredExecuteCodeFragments: ["fetch", "http://%zz"],
            expectedErrorCode: "INVALID_ARGUMENTS"
        )
    )

    public static let calendarLifecycleCatalogDiscovery = CodeModeEvalScenario(
        id: "calendar.lifecycle-catalog",
        title: "EventKit lifecycle catalog discovery",
        task: "Search for calendar and reminders lifecycle helpers. Return each capability, JavaScript name, optional arguments, argument hints, and result summary, including create/update/delete helpers and calendar filtering arguments.",
        searchCode: """
        async () => {
            const names = [
                "apple.calendar.listEvents",
                "apple.calendar.createEvent",
                "apple.calendar.updateEvent",
                "apple.calendar.deleteEvent",
                "apple.reminders.listReminders",
                "apple.reminders.createReminder",
                "apple.reminders.updateReminder",
                "apple.reminders.completeReminder",
                "apple.reminders.deleteReminder"
            ];
            return Object.fromEntries(names.map(name => {
                const ref = api.byJSName[name];
                return [name, ref ? {
                    capability: ref.capability,
                    jsNames: ref.jsNames,
                    summary: ref.summary,
                    tags: ref.tags,
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
                "apple.calendar.deleteEvent",
                "apple.calendar.updateEvent",
                "apple.reminders.completeReminder",
                "apple.reminders.deleteReminder",
                "apple.reminders.updateReminder",
                "calendar.delete",
                "calendar.write",
                "calendarIdentifier",
                "calendarIdentifiers",
                "includeCompleted",
                "isAllDay",
                "isCompleted",
                "reminders.delete",
                "span",
            ]
        )
    )

    public static let networkBase64TimeoutCatalogDiscovery = CodeModeEvalScenario(
        id: "network.base64-timeout-catalog",
        title: "Network base64 and timeout catalog discovery",
        task: "Search for fetch and return the network.fetch JavaScript name, arguments, hints, and result summary. The result must include timeoutMs, bodyBase64, responseEncoding, and base64 response support.",
        searchCode: """
        async () => {
            const ref = api.byJSName["fetch"];
            return {
                capability: ref.capability,
                jsNames: ref.jsNames,
                requiredArguments: ref.requiredArguments,
                optionalArguments: ref.optionalArguments,
                argumentHints: ref.argumentHints,
                resultSummary: ref.resultSummary
            };
        }
        """,
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI],
            requiredSearchResultFragments: [
                "network.fetch",
                "fetch",
                "options.bodyBase64",
                "options.responseEncoding",
                "options.timeoutMs",
                "base64",
                "HTTP(S)",
            ]
        )
    )

    public static let notificationsDeliveredContentCatalogDiscovery = CodeModeEvalScenario(
        id: "notifications.delivered-content-catalog",
        title: "Notifications delivered/content catalog discovery",
        task: "Search for notification scheduling, pending, and delivered helpers. Return each capability, JavaScript name, arguments, hints, and result summary, including richer schedule content fields and delivered-notification management.",
        searchCode: """
        async () => {
            const names = [
                "apple.notifications.schedule",
                "apple.notifications.listPending",
                "apple.notifications.cancelPending",
                "apple.notifications.listDelivered",
                "apple.notifications.removeDelivered"
            ];
            return Object.fromEntries(names.map(name => {
                const ref = api.byJSName[name];
                return [name, ref ? {
                    capability: ref.capability,
                    jsNames: ref.jsNames,
                    summary: ref.summary,
                    tags: ref.tags,
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
                "apple.notifications.listDelivered",
                "apple.notifications.removeDelivered",
                "badge",
                "categoryIdentifier",
                "notifications.delivered.delete",
                "notifications.delivered.read",
                "sound",
                "threadIdentifier",
                "userInfo",
            ]
        )
    )

    public static let systemUIParameterCatalogDiscovery = CodeModeEvalScenario(
        id: "system-ui.parameter-catalog",
        title: "UIKit parameter catalog discovery",
        task: "Search the iOS system UI catalog for calendar editor, camera capture, live data scanner, and alert helpers. Return arguments, hints, and result summaries that expose the new timeout/sourceRect/camera/scanner parameters.",
        catalogPlatform: .iOS,
        searchCode: """
        async () => {
            const names = [
                "apple.calendar.presentNewEvent",
                "apple.camera.capture",
                "apple.camera.scanData",
                "apple.ui.presentAlert"
            ];
            return Object.fromEntries(names.map(name => {
                const ref = api.byJSName[name];
                return [name, ref ? {
                    capability: ref.capability,
                    jsNames: ref.jsNames,
                    summary: ref.summary,
                    tags: ref.tags,
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
                "allowsEditing",
                "apple.calendar.presentNewEvent",
                "apple.camera.capture",
                "apple.camera.scanData",
                "apple.ui.presentAlert",
                "cameraDevice",
                "flashMode",
                "isGuidanceEnabled",
                "isHighFrameRateTrackingEnabled",
                "isHighlightingEnabled",
                "isPinchToZoomEnabled",
                "maximumDurationSeconds",
                "sourceRect",
                "timeoutMs",
                "videoQuality",
            ]
        )
    )

    public static let cloudKitBigTicketCatalogDiscovery = CodeModeEvalScenario(
        id: "cloudkit.big-ticket-catalog",
        title: "CloudKit serverless catalog discovery",
        task: "Search for CloudKit account, query, write, delete, subscription, and subscription-inbox helpers. Return capability names, JavaScript names, arguments, hints, and result summaries for serverless synced state.",
        searchCode: """
        async () => {
            const names = [
                "apple.cloudkit.getAccountStatus",
                "apple.cloudkit.queryRecords",
                "apple.cloudkit.saveRecord",
                "apple.cloudkit.deleteRecord",
                "apple.cloudkit.subscribe",
                "apple.cloudkit.listEvents"
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
                "apple.cloudkit.queryRecords",
                "apple.cloudkit.saveRecord",
                "apple.cloudkit.subscribe",
                "cloudkit.records.query",
                "cloudkit.record.save",
                "cloudkit.subscription.save",
                "cloudkit.subscriptionEvents.read",
                "containerIdentifier",
                "database",
                "private",
                "public",
                "shared",
                "recordType",
                "inbox",
            ]
        )
    )

    public static let notificationsRemoteCatalogDiscovery = CodeModeEvalScenario(
        id: "notifications.remote-catalog",
        title: "APNs remote notification catalog discovery",
        task: "Search for client-side APNs registration, token, settings, categories/actions, and response inbox helpers. Return arguments, hints, and result summaries; do not include APNs provider-send APIs.",
        searchCode: """
        async () => {
            const names = [
                "apple.notifications.registerRemote",
                "apple.notifications.getRemoteToken",
                "apple.notifications.getSettings",
                "apple.notifications.setCategories",
                "apple.notifications.listResponses"
            ];
            return Object.fromEntries(names.map(name => {
                const ref = api.byJSName[name];
                return [name, ref ? {
                    capability: ref.capability,
                    jsNames: ref.jsNames,
                    summary: ref.summary,
                    tags: ref.tags,
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
                "APNs",
                "apple.notifications.registerRemote",
                "apple.notifications.getRemoteToken",
                "apple.notifications.getSettings",
                "apple.notifications.setCategories",
                "apple.notifications.listResponses",
                "notifications.remote.register",
                "notifications.remote.token.read",
                "notifications.settings.read",
                "notifications.categories.set",
                "notifications.responses.read",
                "categories",
                "actionIdentifier",
                "inbox",
            ]
        )
    )

    public static let speechBigTicketCatalogDiscovery = CodeModeEvalScenario(
        id: "speech.big-ticket-catalog",
        title: "Speech transcription catalog discovery",
        task: "Search for Speech permission/status, file transcription, and microphone transcription helpers. Return arguments, permissions, hints, and result summaries including timeout and locale options.",
        searchCode: """
        async () => {
            const names = [
                "apple.speech.requestPermission",
                "apple.speech.getStatus",
                "apple.speech.transcribeFile",
                "apple.speech.transcribeMicrophone"
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
                "apple.speech.requestPermission",
                "apple.speech.transcribeFile",
                "apple.speech.transcribeMicrophone",
                "speech.file.transcribe",
                "speech.microphone.transcribe",
                "locale",
                "microphone",
                "requiresOnDeviceRecognition",
                "timeoutMs",
                "transcript",
            ]
        )
    )

    public static let mapsBigTicketCatalogDiscovery = CodeModeEvalScenario(
        id: "maps.big-ticket-catalog",
        title: "MapKit catalog discovery",
        task: "Search for MapKit geocode, reverse-geocode, local search, route estimate, and open-Maps helpers. Return arguments, hints, and result summaries.",
        searchCode: """
        async () => {
            const names = [
                "apple.maps.geocode",
                "apple.maps.reverseGeocode",
                "apple.maps.search",
                "apple.maps.routeEstimate",
                "apple.maps.open"
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
                "apple.maps.geocode",
                "apple.maps.reverseGeocode",
                "apple.maps.search",
                "apple.maps.routeEstimate",
                "apple.maps.open",
                "maps.geocode",
                "maps.search",
                "address",
                "latitude",
                "longitude",
                "origin",
                "destination",
                "transportType",
            ]
        )
    )

    public static let foundationModelsAppIntentsActivityCatalogDiscovery = CodeModeEvalScenario(
        id: "foundation-appintents-activity.catalog",
        title: "Foundation Models, App Intents, and Activity catalog discovery",
        task: "Search for Foundation Models generation/extraction, host App Intents adapters, and iOS Live Activity adapter helpers. Return capability names, arguments, hints, and result summaries.",
        catalogPlatform: .iOS,
        searchCode: """
        async () => {
            const names = [
                "apple.foundationModels.getStatus",
                "apple.foundationModels.generate",
                "apple.foundationModels.extract",
                "apple.appIntents.list",
                "apple.appIntents.run",
                "apple.appIntents.listHandoffs",
                "apple.activity.start",
                "apple.activity.update",
                "apple.activity.getPushToken"
            ];
            return Object.fromEntries(names.map(name => {
                const ref = api.byJSName[name];
                return [name, ref ? {
                    capability: ref.capability,
                    jsNames: ref.jsNames,
                    summary: ref.summary,
                    tags: ref.tags,
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
                "apple.foundationModels.generate",
                "apple.foundationModels.extract",
                "foundationModels.generate",
                "schemaIdentifier",
                "host-defined",
                "apple.appIntents.run",
                "appintents.run",
                "host-registered",
                "apple.appIntents.listHandoffs",
                "apple.activity.start",
                "activity.start",
                "activityType",
                "pushToken",
            ]
        )
    )

    public static let walletMusicStoreKitSafetyCatalogDiscovery = CodeModeEvalScenario(
        id: "wallet-music-storekit.safety-catalog",
        title: "Wallet, MusicKit, and StoreKit safety catalog discovery",
        task: "Search the iOS catalog for Wallet/Apple Pay, MusicKit, and StoreKit helpers. Return capability names, arguments, hints, and result summaries, especially user-mediated and explicit-confirmation constraints.",
        catalogPlatform: .iOS,
        searchCode: """
        async () => {
            const names = [
                "apple.wallet.getStatus",
                "apple.wallet.addPass",
                "apple.wallet.presentPayment",
                "apple.music.getSubscriptionStatus",
                "apple.music.search",
                "apple.music.play",
                "apple.storekit.listProducts",
                "apple.storekit.purchase",
                "apple.storekit.listTransactions"
            ];
            return Object.fromEntries(names.map(name => {
                const ref = api.byJSName[name];
                return [name, ref ? {
                    capability: ref.capability,
                    jsNames: ref.jsNames,
                    summary: ref.summary,
                    tags: ref.tags,
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
                "apple.wallet.addPass",
                "apple.wallet.presentPayment",
                "passkit.applePay.present",
                "host merchant configuration",
                "explicit user-visible confirmation",
                "apple.music.search",
                "apple.music.play",
                "music.catalog.search",
                "music.playback.control",
                "subscription",
                "apple.storekit.purchase",
                "storekit.purchase",
                "confirmed",
                "apple.storekit.listTransactions",
                "inbox",
            ]
        )
    )

    public static let cloudKitInvalidDatabaseValidation = CodeModeEvalScenario(
        id: "cloudkit.invalid-database-validation",
        title: "CloudKit database validation",
        task: "First search for apple.cloudkit.queryRecords. Then call it with database exactly \"archive\" and recordType \"Task\". Do not catch the error in JavaScript; let executeJavaScript surface structured INVALID_ARGUMENTS before any CloudKit client is required.",
        searchCode: """
        async () => {
            return api.byJSName["apple.cloudkit.queryRecords"];
        }
        """,
        executeCode: """
        return await apple.cloudkit.queryRecords({ database: "archive", recordType: "Task" });
        """,
        allowedCapabilities: [.cloudKitRecordsQuery],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.cloudKitRecordsQuery],
            requiredSearchResultFragments: ["apple.cloudkit.queryRecords", "database", "private", "shared", "public"],
            requiredExecuteCodeFragments: ["apple.cloudkit.queryRecords", "archive"],
            expectedErrorCode: "INVALID_ARGUMENTS"
        )
    )

    public static let mapsInvalidTransportValidation = CodeModeEvalScenario(
        id: "maps.invalid-transport-validation",
        title: "MapKit transport validation",
        task: "First search for apple.maps.routeEstimate. Then call it with valid origin/destination coordinates but transportType exactly \"hoverboard\". Do not catch the error in JavaScript; let executeJavaScript surface structured INVALID_ARGUMENTS before any Maps client is required.",
        searchCode: """
        async () => {
            return api.byJSName["apple.maps.routeEstimate"];
        }
        """,
        executeCode: """
        return await apple.maps.routeEstimate({
            origin: { latitude: 37.33, longitude: -122.03 },
            destination: { latitude: 37.77, longitude: -122.42 },
            transportType: "hoverboard"
        });
        """,
        allowedCapabilities: [.mapsRouteEstimate],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.mapsRouteEstimate],
            requiredSearchResultFragments: ["apple.maps.routeEstimate", "transportType", "automobile"],
            requiredExecuteCodeFragments: ["apple.maps.routeEstimate", "hoverboard"],
            expectedErrorCode: "INVALID_ARGUMENTS"
        )
    )

    public static let storeKitEmptyProductIDsValidation = CodeModeEvalScenario(
        id: "storekit.empty-productids-validation",
        title: "StoreKit productIDs validation",
        task: "First search for apple.storekit.listProducts. Then call it with productIDs as an empty array. Do not catch the error in JavaScript; let executeJavaScript surface structured INVALID_ARGUMENTS before any StoreKit client is required.",
        searchCode: """
        async () => {
            return api.byJSName["apple.storekit.listProducts"];
        }
        """,
        executeCode: """
        return await apple.storekit.listProducts({ productIDs: [] });
        """,
        allowedCapabilities: [.storeKitProductsRead],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.storeKitProductsRead],
            requiredSearchResultFragments: ["apple.storekit.listProducts", "productIDs"],
            requiredExecuteCodeFragments: ["apple.storekit.listProducts", "productIDs"],
            expectedErrorCode: "INVALID_ARGUMENTS"
        )
    )

    public static let notificationsMalformedCategoriesValidation = CodeModeEvalScenario(
        id: "notifications.malformed-categories-validation",
        title: "APNs category shape validation",
        task: "First search for apple.notifications.setCategories. Then call it with a category missing identifier. Do not catch the error in JavaScript; let executeJavaScript surface structured INVALID_ARGUMENTS before any remote notification client is required.",
        searchCode: """
        async () => {
            return api.byJSName["apple.notifications.setCategories"];
        }
        """,
        executeCode: """
        return await apple.notifications.setCategories({
            categories: [{ actions: [{ identifier: "done", title: "Done" }] }]
        });
        """,
        allowedCapabilities: [.notificationsCategoriesSet],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.notificationsCategoriesSet],
            requiredSearchResultFragments: ["apple.notifications.setCategories", "categories", "actions"],
            requiredExecuteCodeFragments: ["apple.notifications.setCategories", "categories"],
            expectedErrorCode: "INVALID_ARGUMENTS"
        )
    )

    public static let activityInvalidDismissalPolicyValidation = CodeModeEvalScenario(
        id: "activity.invalid-dismissal-policy-validation",
        title: "ActivityKit dismissal policy validation",
        task: "First search for apple.activity.end on iOS. Then call it with dismissalPolicy exactly \"later\". Do not catch the error in JavaScript; let executeJavaScript surface structured INVALID_ARGUMENTS before any ActivityKit client is required.",
        catalogPlatform: .iOS,
        searchCode: """
        async () => {
            return api.byJSName["apple.activity.end"];
        }
        """,
        executeCode: """
        return await apple.activity.end({ identifier: "activity-1", dismissalPolicy: "later" });
        """,
        allowedCapabilities: [.activityEnd],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.activityEnd],
            requiredSearchResultFragments: ["apple.activity.end", "dismissalPolicy", "immediate"],
            requiredExecuteCodeFragments: ["apple.activity.end", "later"],
            expectedErrorCode: "INVALID_ARGUMENTS"
        )
    )

    public static let musicInvalidPlaybackActionValidation = CodeModeEvalScenario(
        id: "music.invalid-playback-action-validation",
        title: "Music playback action validation",
        task: "First search for apple.music.play. Then call it with action exactly \"shuffleEverything\". Do not catch the error in JavaScript; let executeJavaScript surface structured INVALID_ARGUMENTS before any Music permission or client is required.",
        searchCode: """
        async () => {
            return api.byJSName["apple.music.play"];
        }
        """,
        executeCode: """
        return await apple.music.play({ action: "shuffleEverything" });
        """,
        allowedCapabilities: [.musicPlaybackControl],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.musicPlaybackControl],
            requiredSearchResultFragments: ["apple.music.play", "action", "playCatalog"],
            requiredExecuteCodeFragments: ["apple.music.play", "shuffleEverything"],
            expectedErrorCode: "INVALID_ARGUMENTS"
        )
    )

    public static let calendarWritePermissionDenied = CodeModeEvalScenario(
        id: "calendar.write-permission-denied",
        title: "Calendar write permission denied",
        task: "First search for apple.calendar.createEvent. Then call executeJavaScript with exactly the calendar.write allowed capability and try to create a valid event titled \"Eval Standup\" from 2026-02-22T16:00:00Z to 2026-02-22T16:15:00Z while calendar write-only privacy permission is denied. Do not omit the capability and do not catch the error in JavaScript; let executeJavaScript surface the structured PERMISSION_DENIED error.",
        searchCode: """
        async () => {
            return api.byJSName["apple.calendar.createEvent"];
        }
        """,
        executeCode: """
        return await apple.calendar.createEvent({
            title: "Eval Standup",
            start: "2026-02-22T16:00:00Z",
            end: "2026-02-22T16:15:00Z"
        });
        """,
        allowedCapabilities: [.calendarWrite],
        permissions: CodeModeEvalPermissions(statuses: [.calendarWriteOnly: .denied]),
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.calendarWrite],
            requiredSearchResultFragments: [
                "calendar.write",
                "apple.calendar.createEvent",
            ],
            requiredExecuteCodeFragments: ["apple.calendar.createEvent", "Eval Standup"],
            expectedErrorCode: "PERMISSION_DENIED"
        )
    )

    public static let homeWriteValidation = CodeModeEvalScenario(
        id: "home.write-validation",
        title: "Home write validation",
        task: "First search for apple.home.writeCharacteristic. Then call it with only accessoryIdentifier set exactly to \"accessory-1\" and let executeJavaScript surface the structured missing-arguments error before any HomeKit permission flow.",
        searchCode: """
        async () => {
            return api.byJSName["apple.home.writeCharacteristic"];
        }
        """,
        executeCode: """
        return await apple.home.writeCharacteristic({ accessoryIdentifier: "accessory-1" });
        """,
        allowedCapabilities: [.homeWrite],
        permissions: CodeModeEvalPermissions(statuses: [.homeKit: .granted]),
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.homeWrite],
            requiredSearchResultFragments: [
                "home.write",
                "apple.home.writeCharacteristic",
                "characteristicType",
                "value",
            ],
            requiredErrorSuggestionFragments: ["characteristicType:string", "value", "Example:"],
            requiredExecuteCodeFragments: ["apple.home.writeCharacteristic", "accessory-1"],
            expectedErrorCode: "INVALID_ARGUMENTS"
        )
    )

    public static let mediaMetadataValidation = CodeModeEvalScenario(
        id: "media.metadata-validation",
        title: "Media metadata validation",
        task: "First search for apple.media.metadata. Then call it without a path and let executeJavaScript surface the structured missing-arguments error.",
        searchCode: """
        async () => {
            return api.byJSName["apple.media.metadata"];
        }
        """,
        executeCode: """
        return await apple.media.metadata({});
        """,
        allowedCapabilities: [.mediaMetadataRead],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.searchJavaScriptAPI, .executeJavaScript],
            exactAllowedCapabilities: [.mediaMetadataRead],
            requiredSearchResultFragments: [
                "media.metadata.read",
                "apple.media.metadata",
                "path",
            ],
            requiredErrorSuggestionFragments: ["path", "Example:"],
            requiredExecuteCodeFragments: ["apple.media.metadata"],
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
