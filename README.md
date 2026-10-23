# CodeMode.swift

A Swift package that implements [Code Mode](https://blog.cloudflare.com/code-mode/) for Apple platform APIs.

Instead of handing an agent one tool per API, CodeMode gives it two:

- **`searchJavaScriptAPI`**: the agent writes a small JavaScript function that filters a catalog of available helpers.
- **`executeJavaScript`**: the agent writes one script that does the whole job — read the calendar, filter it, write a file, return a summary — against helpers like `apple.calendar.read` and `apple.fs.write`.

Models are better at writing code than at chaining dozens of tool calls, and a script that does its filtering locally returns the answer rather than every intermediate result. One execution replaces a round trip per operation.

Platforms: iOS 18+, macOS 15+, visionOS 2+. watchOS is out of scope because the runtime depends on JavaScriptCore.

## Installation

```swift
.package(url: "https://github.com/velos/CodeMode.swift", from: "0.2.2")
```

`main` may be ahead of the latest tag; depend on `branch: "main"` for unreleased changes. Add the product to your target:

```swift
.product(name: "CodeMode", package: "CodeMode")
```

## Quick start

```swift
import CodeMode

let tools = CodeModeAgentTools(
    config: CodeModeConfiguration(
        // The host's ceiling on what any script may use. See "Security model".
        capabilityGrant: .only([.fsRead, .fsWrite])
    )
)

let call = try await tools.executeJavaScript(
    JavaScriptExecutionRequest(
        code: """
        await apple.fs.write({ path: "tmp:note.txt", data: "hello" });
        return await fs.promises.readFile("tmp:note.txt", "utf8");
        """,
        allowedCapabilities: [.fsWrite, .fsRead]
    )
)

for await event in call.events {
    if case .log(let entry) = event { print(entry.message) }
}

let result = try await call.result   // throws CodeModeToolError on failure
print(result.output ?? .null)          // "hello"
```

In an agent, the model writes `code` and `allowedCapabilities`; your host passes them through.

## How it works

1. **Search.** `searchJavaScriptAPI` runs the model's function against an `api` object listing every helper available on this platform: names, arguments, types, examples, and a TypeScript declaration for each. The model gets back only what its function returns.
2. **Execute.** Each execution gets a fresh `JSContext` with this platform's helpers installed. The script is compiled as the body of an async function, so it can use top-level `await` and `return`.
3. **Bridge.** Each `apple.*` call crosses into Swift, is checked against the capability grant, path policy, and network policy, handles any system permission prompt, and calls the real framework (EventKit, CoreLocation, HealthKit, and so on).
4. **Report.** Logs, diagnostics, and errors stream as events while the script runs. The final result is JSON, or a `CodeModeToolError` with a code, the failing helper, a line, and repair suggestions the model can act on.

Calls into native code are synchronous, so `Promise.all` over several helpers runs them one at a time. `setTimeout` and `clearTimeout` are real timers, so `await new Promise(r => setTimeout(r, 1000))` actually waits.

### The JavaScript surface

- **Web-style globals:** `fetch`, `URL`, `URLSearchParams`, `setTimeout`/`clearTimeout`, `console`, and Node-style `fs.promises` and `path`.
- **`apple.*` namespaces:** `keychain`, `location`, `weather`, `calendar`, `reminders`, `contacts`, `photos`, `vision`, `notifications`, `health`, `home`, `media`, `fs`, `cloudkit`, `maps`, `storekit`, `speech`, `appIntents`, `activity`, `foundationModels`, `music`, `wallet`.
- **Platform-specific namespaces** such as `ios.alarm` (AlarmKit).
- **System UI** on iOS and visionOS: alerts and prompts, pickers for photos, contacts, documents, and calendars, share sheets, Quick Look, web authentication, and on iOS camera capture, document scanning, and mail and message compose. These need a `SystemUIPresenter`, such as `UIKitSystemUIPresenter`, and fail with `UI_PRESENTER_UNAVAILABLE` without one.

`apple.*` is the shared cross-platform namespace, not a promise that every helper exists on every OS. Search and execution only ever expose what the current host supports.

## Wiring it into an agent

Three pieces, all generated from the same registry, so they cannot disagree with what actually runs:

```swift
// Tool definitions: names, descriptions, and JSON parameter schemas.
CodeModeAgentToolDescriptions.searchJavaScriptAPI
CodeModeAgentToolDescriptions.executeJavaScript

// How to use the tools: one script per task, request only what you call,
// repair from the structured error.
let guidance = CodeModeAgentGuidance.systemPrompt(.standard)

// What the helpers are: TypeScript declarations for the granted surface.
let declarations = tools.typeDeclarations()
```

**Guidance** matters more than it looks. The tool descriptions tell a model what helpers are called, not what shape its work should take, and without it agents tend to use `executeJavaScript` as a thin RPC, one call per operation. It comes in three tiers. Each is self-contained, and a smaller tier drops examples, never rules:

| Tier | ~Tokens | Adds |
| --- | --- | --- |
| `.brief` | 160 | One call runs the whole task; request only the capabilities you use. |
| `.standard` | 620 | The search → write → repair workflow, with a worked example. |
| `.full` | 1000 | Partial-failure handling, sequential native calls, and anti-patterns. |

`CodeModeAgentGuidance.systemPrompt(approximateTokenBudget: 800)` picks the largest tier that fits, falling back to `.brief`. Counts are estimated at four characters per token.

**Declarations** follow the host's `CapabilityGrant`, so they never advertise a helper the model would be denied. Size is the reason to grant narrowly: the unrestricted surface is about 21,000 tokens on iOS, while a grant of a few helpers is about 1,000. `typeDeclarations(for:)` renders an explicit subset, and every search result carries its own `dts`, so a model can also fetch declarations through search instead of having them all in its prompt:

```javascript
async () => api.references
  .filter(ref => ref.tags.includes("calendar"))
  .map(ref => ref.dts)
  .join("\n\n")
```

Constrained arguments become string-literal unions and argument hints become doc comments. CI compiles every generated declaration with `tsc --strict`.

## Security model

Scripts are written by a model, which means they may be written by whoever controls the model's input. The defaults assume that.

**Capabilities.** `allowedCapabilities` is part of the tool schema, so the model fills it in. It's a useful least-privilege declaration, but not a sandbox on its own. `CodeModeConfiguration.capabilityGrant` is the host-owned ceiling, and a script gets `requested ∩ granted`:

```swift
CodeModeConfiguration(
    capabilityGrant: .only(
        [.fsRead, .fsWrite, .networkFetch],
        capabilityKeys: ["myapp.tasks.complete"]   // custom providers
    )
)
```

The default is `.unrestricted`, for source compatibility; set a grant whenever tool JSON comes from a model. A capability the grant withholds fails with `CAPABILITY_DENIED`, marked as not fixable by retrying. Built-in capabilities and custom provider keys are separate lists, so a provider key can never name a built-in.

**Filesystem.** Paths are scoped to the `tmp:`, `caches:`, and `documents:` roots. `fs.move`, `fs.copy`, and `fs.delete` refuse a root as source or destination, and replacing an existing file needs `overwrite: true`. If the operation fails, the original file is restored. Reads, writes, and copies are capped at 16 MB by default (`FileSystemLimits`). Provide a `CodeModeFileSystem` to back these operations with your own storage. Paths reach it already resolved by `PathPolicy`. A custom `PathPolicy` must declare its `allowedRoots`.

**Network.** `NetworkAccessPolicy.standard` blocks:

- loopback, private, link-local, CGNAT, and unique-local addresses, including cloud metadata endpoints;
- `localhost`, `.local`, `.internal`, and single-label hosts.

It also re-checks redirect targets and caps response bodies at 10 MB. Matching is by hostname without DNS resolution, so set `allowedHosts` if you need a strict list. `fetch` runs on an isolated ephemeral session, with no cookies, stored credentials, or shared cache, so a script can't use whatever your app is signed in to. Scripts can't set `Cookie`, `Authorization`, or `Proxy-*` headers unless you set `allowsCredentialHeaders`.

**Resources.** `timeoutMs` (default 10 s, maximum 60 s) bounds the whole execution, including time spent in native calls. It is enforced preemptively, so `while (true) {}` is terminated, not waited out. `ExecutionLimits` bounds result size, logs, diagnostics, buffered events, and concurrent executions (8 by default). Each limit truncates with a diagnostic rather than failing.

> **App Store note.** Preemption uses `JSContextGroupSetExecutionTimeLimit`. JavaScriptCore exports it but declares it only in a private header, and CodeMode reaches it through a small C shim (`CCodeModeJSC`). It is JavaScriptCore's only way to interrupt a runaway script.

## Adding your own helpers

Expose app functionality alongside the built-ins with the `@CodeMode` macro from the `CodeModeAuthoring` product:

```swift
import CodeModeAuthoring

@CodeMode(path: "myapp.tasks.complete", description: "Mark a task complete.")
struct TaskComplete: Sendable {
    let store: TaskStore

    struct Arguments {
        @CodeModeParam("Task identifier") var id: String
    }

    func call(arguments: Arguments) async throws {
        try await store.complete(id: arguments.id)
    }
}

let tools = CodeModeAgentTools(
    config: CodeModeConfiguration(codeModeProviders: [TaskComplete(store: store)])
)
```

Scripts call it as `await myapp.tasks.complete({ id: "task-123" })`, and the model requests it through `allowedCapabilityKeys`. It appears in search and in the TypeScript declarations like any built-in. `register(provider:)` adds providers after construction. See [the CodeModeAuthoring README](Sources/CodeModeAuthoring/README.md) for supported types and structured errors.

## Host app setup

Bridged APIs need the usual privacy strings and entitlements. `HostConfigurationValidator` checks them for you:

```swift
let issues = HostConfigurationValidator.validate(requiredCapabilities: [.locationRead, .contactsSearch])
    + HostConfigurationValidator.validate(configuration: config)   // e.g. warns on an unrestricted grant
```

| Capabilities | Info.plist key |
| --- | --- |
| `location.read`, `location.permission.request` (iOS) | `NSLocationWhenInUseUsageDescription` |
| `contacts.read`, `contacts.search`, `contacts.ui.*` | `NSContactsUsageDescription` |
| `calendar.read`, `calendar.ui.presentEvent` | `NSCalendarsFullAccessUsageDescription` |
| `calendar.write`, `calendar.ui.presentNewEvent`, `calendar.ui.pickCalendar` | `NSCalendarsWriteOnlyAccessUsageDescription` |
| `reminders.read`, `reminders.write` | `NSRemindersFullAccessUsageDescription` |
| `photos.read`, `photos.export`, `photos.ui.presentLimitedLibraryPicker` | `NSPhotoLibraryUsageDescription` |
| `camera.ui.capture`, `camera.ui.scanData`, `documents.ui.scan` | `NSCameraUsageDescription` |
| `camera.ui.capture` (video) | `NSMicrophoneUsageDescription` |
| `alarm.*` (iOS 26+) | `NSAlarmKitUsageDescription` |
| `health.permission.request`, `health.read` / `health.write` | `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` |
| `home.read`, `home.write` | `NSHomeKitUsageDescription` |

HealthKit also needs its entitlement, and `weather.read` needs the WeatherKit capability. Notifications, alarms, and HealthKit authorize at runtime through their `requestPermission` helpers.

## Development

```sh
swift test                                                   # unit and integration tests
swift run --package-path Tools/CodeModeEval codemode-eval    # 52 deterministic agent scenarios
scripts/check-typescript-declarations.sh                     # tsc --strict over every declaration
```

The eval scenarios drive the two tools the way an agent would. They grade the tool order, the generated code, whether the requested capabilities were exactly the minimal set, structured errors, and recovery after a failure. The same CLI plans, summarizes, and compares live-model runs; see [EVALS.md](EVALS.md). It lives in `Tools/CodeModeEval`, so library users don't resolve ArgumentParser.

## Acknowledgements

The Code Mode framing and its search-and-execute model come from Cloudflare's work: the [announcement](https://blog.cloudflare.com/code-mode/), the [API reference](https://developers.cloudflare.com/agents/api-reference/codemode/), and [Code Mode MCP](https://blog.cloudflare.com/code-mode-mcp/). This is an independent implementation, not affiliated with Cloudflare.

Development of `CodeMode.swift` was done exclusively with Codex, initiated by an interactively built plan, executed by the model after the plan was finalized.

License: MIT. See [LICENSE](LICENSE).
