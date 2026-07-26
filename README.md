# CodeMode.swift

`CodeMode.swift` is a Swift package that implements [CodeMode](https://blog.cloudflare.com/code-mode/) for Apple platform APIs by exposing agents to two tools:

- `searchJavaScriptAPI`: code-driven discovery of the bundled JavaScript wrapped Apple API surface for the current host platform.
- `executeJavaScript`: constrained JavaScript execution with capability allowlisting and structured errors.

GitHub: [velos/CodeMode.swift](https://github.com/velos/CodeMode.swift)

## Highlights

- Platforms: `iOS 18+`, `macOS 15+`, `visionOS 2+`
- watchOS is audited but not a runtime target in this package because the current runtime depends on JavaScriptCore.
- Typed Swift host API through `CodeModeAgentTools`
- Streaming execution via `JavaScriptExecutionCall`
- Structured failures via `CodeModeToolError`
- Hybrid JS surface:
  - web-style globals: `fetch`, `URL`, `URLSearchParams`, `setTimeout`, `console`
  - cross-platform Apple namespaces: `apple.keychain`, `apple.location`, `apple.weather`, `apple.calendar`, `apple.reminders`, `apple.contacts`, `apple.photos`, `apple.vision`, `apple.notifications`, `apple.health`, `apple.home`, `apple.media`, `apple.fs`, `apple.cloudkit`, `apple.maps`, `apple.storekit`, `apple.speech`, `apple.appIntents`, `apple.activity`, `apple.foundationModels`, `apple.music`, `apple.wallet`
  - platform-specific namespaces when needed: `ios.alarm`
- iOS/visionOS system UI helpers through an injected presenter, including alerts, calendar editors, photo/contact/document pickers, share sheets, Quick Look previews, web authentication, and iOS-only camera/scan/mail/message compose flows
- Node-style aliases for file operations through `globalThis.fs.promises`
- Sandboxed filesystem policy with allowed roots: `tmp`, `caches`, `documents`
- Search and execution only expose helpers supported on the current host platform
- `apple.*` is the canonical cross-Apple namespace, not a promise that every helper exists on every Apple OS
- Library-only package surface

## Installation

Add `CodeMode.swift` with Swift Package Manager:

```swift
.package(url: "https://github.com/velos/CodeMode.swift", branch: "main")
```

No release has been tagged yet, so depend on `main` for now. Once `0.1.0` is tagged, prefer the versioned form:

```swift
.package(url: "https://github.com/velos/CodeMode.swift", from: "0.1.0")
```

Then add the product to your target:

```swift
.product(name: "CodeMode", package: "CodeMode")
```

## Public API

- `CodeModeAgentTools`
- `searchJavaScriptAPI(_:) async throws -> JavaScriptAPISearchResponse`
- `executeJavaScript(_:) async throws -> JavaScriptExecutionCall`
- `JavaScriptExecutionCall.events`
- `JavaScriptExecutionCall.result`
- `JavaScriptExecutionCall.cancel()`
- `CodeModeToolError`
- `CodeModeConfiguration`
- `CodeModeFileSystem`
- `LocalCodeModeFileSystem`
- `CodeModeAgentToolDescriptions`
- `CodeModeEvaluation` SwiftPM product for deterministic scenario evaluation
- `SystemUIPresenter`
- `UIKitSystemUIPresenter` on iOS/visionOS

## Quick Start

```swift
import CodeMode

let tools = CodeModeAgentTools()

let searchResponse = try await tools.searchJavaScriptAPI(
    JavaScriptAPISearchRequest(
        code: """
        async () => {
            return api.references
                .filter(ref => ref.tags.includes("reminders"))
                .map(ref => ({
                    capability: ref.capability,
                    jsNames: ref.jsNames,
                    summary: ref.summary
                }));
        }
        """
    )
)

print(searchResponse.result ?? .null)

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
    switch event {
    case .log(let entry):
        print(entry.message)
    case .diagnostic(let diagnostic):
        print(diagnostic.message)
    case .syntaxError(let error),
         .functionNotFound(let error),
         .thrownError(let error),
         .toolError(let error):
        print("\(error.code): \(error.message)")
    case .finished:
        break
    }
}

let result = try await call.result
print(result.output ?? .null)
```

## Filesystem Integration

CodeMode keeps its JavaScript filesystem API stable while allowing hosts to provide the underlying operations:

```swift
let tools = CodeModeAgentTools(
    config: CodeModeConfiguration(
        fileSystem: MyCodeModeFileSystem()
    )
)
```

`CodeModeFileSystem` receives paths after `PathPolicy` resolution, so sandbox root enforcement stays in CodeMode while the host can route reads, writes, listings, moves, copies, deletes, and stats through another backing implementation. `LocalCodeModeFileSystem` preserves the default `FileManager` behavior.

## Network Access Policy

`network.fetch` egress is governed by `CodeModeConfiguration.networkAccessPolicy`:

- The default `NetworkAccessPolicy.standard` refuses loopback, RFC 1918, link-local (including cloud metadata addresses such as `169.254.169.254`), CGNAT, and unique-local destinations, plus `localhost` and `.local`/`.localhost`/`.internal` names, and caps buffered response bodies at 10 MB.
- Redirect targets are re-validated against the policy before they are followed.
- Refusals throw structured `NETWORK_POLICY_VIOLATION` errors and are written to the audit logger along with successful fetch destinations.
- `allowedHosts` restricts fetch to an explicit list (entries match the host and its subdomains, and deliberately allowlisted private hosts such as `localhost` are honored); `blockedHosts` refuses specific hosts; `NetworkAccessPolicy.permissive` restores unrestricted behavior.
- Matching is by URL host only; DNS resolution is not performed, so a public hostname that resolves to a private address is not detected. Hosts that need stricter guarantees should set `allowedHosts`.

Script traffic also carries no ambient authority:

- `network.fetch` runs on an isolated ephemeral `URLSession` with no cookie storage, no credential storage, and no shared cache — not `URLSession.shared`, which would let a script ride whatever the host app is already logged in to and let a `Set-Cookie` poison the app's cookie jar.
- Script-supplied `Cookie`, `Authorization`, and `Proxy-*` request headers are refused. Set `allowsCredentialHeaders: true` when scripts legitimately call an authenticated API.
- A host that passes its own `session` to `NetworkBridge` takes responsibility for this; requests still disable per-request cookie handling.

```swift
let tools = CodeModeAgentTools(
    config: CodeModeConfiguration(
        networkAccessPolicy: NetworkAccessPolicy(
            allowedHosts: ["api.example.com"],
            maxResponseBytes: 2_000_000
        )
    )
)
```

## TypeScript Declarations

The registry already knows argument names, types, optionality, enum constraints,
and hints. That metadata is emitted as TypeScript so the model writes code
against real declarations instead of a coarse type map plus prose:

```swift
let tools = CodeModeAgentTools()
print(tools.typeDeclarations())      // whole platform-filtered surface
print(tools.capabilities())          // every reference, each carrying `dts`
```

Every `JavaScriptAPIReference` carries a per-capability `dts`, so code-driven
search stays the filter and TypeScript becomes the payload:

```javascript
async () => {
  return api.references
    .filter(ref => ref.tags.includes("calendar"))
    .map(ref => ref.dts)
    .join("\n\n");
}
```

Constrained arguments become string-literal unions, dotted argument paths
(`options.timeoutMs`) become nested object types, and argument hints become doc
comments. Results are typed `CodeModeValue` — built-in bridges return untyped
JSON dictionaries, so a narrower result type would be a fiction; the prose result
summary is in the doc comment until per-capability result schemas exist.

The Node-compatibility globals (`fetch`, `fs.promises.*`, `path`, `console`) are
declared in a hand-authored preamble, because their positional calling convention
is not something the catalog can express.

## Search

`searchJavaScriptAPI` accepts `JavaScriptAPISearchRequest`:

- `code`: JavaScript source that evaluates to an async function

Behavior:

- empty search input throws `CodeModeToolError(code: "INVALID_REQUEST", ...)`
- search executes your async function against a preloaded `api` object
- `api` only contains capabilities and JS names supported on the current host platform
- returned output must be JSON-serializable
- syntax errors, invalid search programs, timeouts, and runtime failures throw `CodeModeToolError`
- responses include `result: JSONValue?` plus non-fatal diagnostics

Available in search code:

```ts
interface JavaScriptAPIReference {
  capability: string;
  capabilityKey: string;
  builtInCapability: string | null;
  jsNames: string[];
  summary: string;
  tags: string[];
  example: string;
  requiredArguments: string[];
  optionalArguments: string[];
  argumentTypes: Record<string, string>;
  argumentHints: Record<string, string>;
  argumentConstraints: { allowedStringValues: Record<string, string[]> };
  resultSummary: string;
}

declare const api: {
  references: JavaScriptAPIReference[];
  byCapability: Record<string, JavaScriptAPIReference>;
  byJSName: Record<string, JavaScriptAPIReference>;
};
```

Example search programs:

```javascript
async () => {
  return api.references
    .filter(ref => ref.tags.includes("media"))
    .map(ref => ({ capability: ref.capability, jsNames: ref.jsNames }));
}
```

```javascript
async () => {
  return api.byJSName["apple.fs.read"];
}
```

## Execution

`executeJavaScript` accepts `JavaScriptExecutionRequest`:

- `code`
- `allowedCapabilities`
- `allowedCapabilityKeys`
- `timeoutMs`
- `context`

It returns a `JavaScriptExecutionCall` immediately.

### Capability allowlists are model-authored; the grant is not

`allowedCapabilities` and `allowedCapabilityKeys` travel in the advertised tool
schema, so the *model* fills them in. They are a least-privilege declaration and
a useful audit signal, but on their own they are not a sandbox: a host that pipes
tool JSON straight into `executeJavaScript` gives the script whatever the script
asked for.

`CodeModeConfiguration.capabilityGrant` is the host-owned ceiling. The effective
set is always `requested ∩ granted`:

```swift
let tools = CodeModeAgentTools(
    config: CodeModeConfiguration(
        capabilityGrant: .only(
            [.fsRead, .fsWrite, .networkFetch],
            capabilityKeys: ["myapp.tasks.complete"]
        )
    )
)
```

It defaults to `.unrestricted` for source compatibility. Anything the request
declares and the grant withholds fails with `CAPABILITY_DENIED`, is reported to
the model as not repairable by retrying, and is recorded as a
`CAPABILITY_WITHHELD_BY_HOST` diagnostic.

The two allowlists are strictly disjoint. Built-in `CapabilityID`s are granted
only by `allowedCapabilities`; `allowedCapabilityKeys` accepts arbitrary strings
and reaches custom providers only, so it cannot be used to spell a built-in past
a host that vets the typed field.

Cross-platform privileged helpers are installed under `apple.*`. Platform-specific helpers are installed only where supported, for example `ios.alarm.*` on iOS hosts that support AlarmKit.

`apple.location.requestPermission()` is currently exposed only on iOS hosts. Other Apple platforms can expose `apple.location.*` helpers when supported, but the explicit permission-request helper is intentionally hidden outside iOS for now.

System UI helpers are installed only on supported UI platforms. Shared iOS/visionOS helpers include `apple.ui.presentAlert`, `apple.ui.presentPrompt`, `apple.settings.open`, `apple.calendar.pickCalendar`, `apple.calendar.presentEvent`, `apple.calendar.presentNewEvent`, `apple.contacts.pick`, `apple.contacts.presentContact`, `apple.contacts.presentNewContact`, `apple.photos.pick`, `apple.photos.presentLimitedLibraryPicker`, `apple.documents.pick`, `apple.documents.export`, `apple.documents.save`, `apple.documents.openIn`, `apple.share.present`, `apple.quicklook.preview`, `apple.camera.scanData`, `apple.print.present`, `apple.web.present`, and `apple.auth.webAuthenticate`. iOS-only helpers include `apple.camera.capture`, `apple.documents.scan`, `apple.mail.compose`, and `apple.messages.compose`. Host apps must provide a `SystemUIPresenter`; otherwise UI-presenting helpers fail with `UI_PRESENTER_UNAVAILABLE`.

`call.events` is a non-throwing `AsyncStream` that can emit:

- `.log(ExecutionLog)`
- `.diagnostic(ToolDiagnostic)`
- `.syntaxError(CodeModeToolError)`
- `.functionNotFound(CodeModeToolError)`
- `.thrownError(CodeModeToolError)`
- `.toolError(CodeModeToolError)`
- `.finished`

`call.result` is the throwing boundary:

- on success it returns `JavaScriptExecutionResult`
- on failure it throws `CodeModeToolError`
- `call.cancel()` interrupts in-flight JavaScript

### Timers and the event loop

`setTimeout`/`clearTimeout` are real: callbacks are deferred, delays are honoured,
`clearTimeout` cancels, and an error thrown inside a callback becomes a
`TIMER_CALLBACK_ERROR` diagnostic rather than propagating to whoever called
`setTimeout`. So `await new Promise(r => setTimeout(r, 1000))` — the standard
backoff — actually waits instead of spinning. A long wait remains cancellable and
is still bounded by `timeoutMs`.

There is no I/O event loop yet: the bridge ABI is synchronous, so native calls run
one at a time and `Promise.all` over several helpers completes them sequentially.
Because a timer is the only thing that can advance a pending program, a promise
with no resolve path and no queued timer is provably unsettleable and fails
immediately with `JS_RUNTIME_ERROR` instead of running out the clock.

Bridge calls that fail while the script still returns successfully — typically a
forgotten `await`, which silently discards the rejection — produce a
`BRIDGE_FAILURES_NOT_SURFACED` warning diagnostic.

### Timeout and cancellation

`timeoutMs` and `cancel()` are enforced preemptively: a JavaScriptCore execution
time limit terminates CPU-bound scripts (for example `while (true) {}`) instead
of relying on a wall-clock check that cannot interrupt running JavaScript.

- `timeoutMs` bounds total wall-clock for the execution, including the
  synchronous portion of the script and any time already elapsed while a bridge
  call blocked on native I/O (network, a UI picker). Hosts that present
  long-running UI or issue slow requests should size `timeoutMs` accordingly;
  the default is `10000`.
- Preemption uses `JSContextGroupSetExecutionTimeLimit`, which JavaScriptCore
  exports but declares only in a private WebKit header. CodeMode reaches it
  through a thin C shim (`CCodeModeJSC`). This is JavaScriptCore's only
  mechanism for interrupting runaway scripts; hosts submitting to the App Store
  should be aware they rely on this exported-but-private symbol.

`CodeModeToolError` includes structured fields such as:

- `code`
- `message`
- `functionName`
- `capability`
- `line`
- `column`
- `suggestions`
- `diagnostics`
- `logs`
- `permissionEvents`

For hosts that vend these methods as LLM tool calls, use `CodeModeAgentToolDescriptions.searchJavaScriptAPI` and `CodeModeAgentToolDescriptions.executeJavaScript` as the canonical tool descriptions.

## Host App Permissions and Capabilities

Host apps must provide privacy usage strings for bridged APIs that request protected resources.

Required Info.plist keys by capability:

- Location read (`location.read`): `NSLocationWhenInUseUsageDescription`
- Location permission request (`location.permission.request`, iOS-only): `NSLocationWhenInUseUsageDescription`
- Contacts (`contacts.read`, `contacts.search`, `contacts.ui.presentContact`, `contacts.ui.presentNewContact`): `NSContactsUsageDescription`
- Calendar read (`calendar.read`): `NSCalendarsFullAccessUsageDescription`
- Calendar event detail UI (`calendar.ui.presentEvent`): `NSCalendarsFullAccessUsageDescription`
- Calendar write-only (`calendar.write`): `NSCalendarsWriteOnlyAccessUsageDescription`
- Calendar event editor/chooser UI (`calendar.ui.presentNewEvent`, `calendar.ui.pickCalendar`): `NSCalendarsWriteOnlyAccessUsageDescription`
- Reminders (`reminders.read`, `reminders.write`): `NSRemindersFullAccessUsageDescription`
- Photos (`photos.read`, `photos.export`, `photos.ui.presentLimitedLibraryPicker`): `NSPhotoLibraryUsageDescription`
- Camera UI (`camera.ui.capture`, `camera.ui.scanData`, `documents.ui.scan`): `NSCameraUsageDescription`
- Camera video capture (`camera.ui.capture`): `NSMicrophoneUsageDescription`
- AlarmKit (`alarm.permission.request`, `alarm.read`, `alarm.schedule`, `alarm.cancel`): `NSAlarmKitUsageDescription`
- HealthKit read (`health.permission.request`, `health.read`): `NSHealthShareUsageDescription`
- HealthKit write (`health.permission.request`, `health.write`): `NSHealthUpdateUsageDescription`
- HomeKit (`home.read`, `home.write`): `NSHomeKitUsageDescription`

Notifications:

- Local notification scheduling and management (`notifications.*`) requires runtime authorization via `apple.notifications.requestPermission()`
- No additional Info.plist privacy string is required for `UNUserNotificationCenter` authorization prompts

AlarmKit:

- `alarm.*` requires `iOS 26+` and runtime authorization via `ios.alarm.requestPermission()`

HealthKit:

- `health.*` requires the HealthKit entitlement and runtime authorization via `apple.health.requestPermission(...)`

Weather:

- `weather.read` requires enabling the WeatherKit capability on the app target
- Weather does not require a separate privacy prompt in this package because `weather.read` expects explicit coordinates

Programmatic validation helper:

```swift
import CodeMode

let required: Set<CapabilityID> = [
    .locationRead,
    .contactsSearch,
    .weatherRead,
]

let issues = HostConfigurationValidator.validate(requiredCapabilities: required)
for issue in issues {
    print("[\(issue.severity.rawValue)] \(issue.key): \(issue.message)")
}
```

## Development

- Run the deterministic CodeMode eval harness:

```sh
swift run --package-path Tools/CodeModeEval codemode-eval
swift run --package-path Tools/CodeModeEval codemode-eval list
swift run --package-path Tools/CodeModeEval codemode-eval run fs.round-trip --show-code
swift run --package-path Tools/CodeModeEval codemode-eval run --json
```

The eval harness runs 49 built-in user-style scenarios through the same
`searchJavaScriptAPI` and `executeJavaScript` APIs that host apps expose to
agents. It validates tool order, discovered catalog output, generated JavaScript
fragments, exact `allowedCapabilities`, structured errors, repair suggestions,
console logs, diagnostics, and final output. The scenarios cover filesystem
workflows, capability minimization, path policy failures, permission failures,
catalog search behavior, helper suggestions, API argument-shape confusion,
recovery after structured tool errors, execution timeouts, and catalog coverage
for the expanded Apple API families.

- Preview LLM eval suites and work with saved live reports:

```sh
swift run --package-path Tools/CodeModeEval codemode-eval plan --suite core --repeat 5 --request-delay-ms 1000
swift run --package-path Tools/CodeModeEval codemode-eval summarize Tools/CodeModeEval/.build/reports/core-baseline.json --output Tools/CodeModeEval/.build/reports/core-summary.json
swift run --package-path Tools/CodeModeEval codemode-eval report Tools/CodeModeEval/.build/reports/core-baseline.json --output Tools/CodeModeEval/.build/reports/core-baseline.md
swift run --package-path Tools/CodeModeEval codemode-eval compare Tools/CodeModeEval/.build/reports/core-baseline.json Tools/CodeModeEval/.build/reports/core-candidate.json
```

The default eval package intentionally avoids private Wavelike dependencies, so
`swift build --package-path Tools/CodeModeEval` works in public or unauthenticated
CI. Use `plan` to preview request budgets, `summarize` to strip raw transcripts
before committing baselines, `report` to generate Markdown diagnostics with
tool-attempt retry traces, then `compare` to fail on pass-rate, exact-capability,
retry, or turn-count regressions. Tolerances are configurable with
`--pass-rate-tolerance`, `--capability-rate-tolerance`, `--retry-tolerance`, and
`--turn-tolerance`. The saved JSON report envelope includes raw run results plus
aggregate pass rate, average turns, retry count, exact/minimal capability
success, per-scenario metrics, and failure categories such as `wrong_tool`,
`wrong_js`, `overbroad_capability`, `failed_recovery`, and `no_final_answer`.
See [EVALS.md](EVALS.md) for CI/nightly policy, baseline handling, and
recommended commands.
The CLI lives in `Tools/CodeModeEval` so library consumers do not resolve
ArgumentParser when they use the `CodeMode` product.

- License: MIT. See [LICENSE](LICENSE)

## Acknowledgements

The "Code Mode" framing and the tool-oriented search and execution model in this repository were influenced by Cloudflare's Code Mode work:

- [Cloudflare Code Mode API reference](https://developers.cloudflare.com/agents/api-reference/codemode/)
- [Cloudflare Code Mode announcement](https://blog.cloudflare.com/code-mode/)
- [Cloudflare Code Mode MCP](https://blog.cloudflare.com/code-mode-mcp/)

This repository is an independent implementation and is not affiliated with Cloudflare.

## Development Process

Development of `CodeMode.swift` was done exclusively with Codex, initiated by an interactively built plan, executed by the model after the plan was finalized.

## Shipped Expanded Families

These API families are represented in the catalog and local bridge layer on this
branch:

- APNs / remote-notification token and settings lifecycle under `apple.notifications.*`
- PassKit wallet APIs under `apple.wallet.*`
- Speech, MusicKit, Foundation Models, CloudKit, Maps, StoreKit, App Intents, and ActivityKit namespaces

## Deferred in v1

The package intentionally defers these to later phases:

- Production host entitlement provisioning and app-specific UX for newly bridged frameworks
- Broader executable eval coverage for every catalog-only capability family
- Behavior-preserving refactors that generate more JavaScript bindings from registration metadata
