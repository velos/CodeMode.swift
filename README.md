# CodeMode.swift

`CodeMode.swift` is a Swift package that implements [CodeMode](https://blog.cloudflare.com/code-mode/) for Apple platform APIs by exposing agents to two tools:

- `searchJavaScriptAPI`: code-driven discovery of the bundled JavaScript wrapped Apple API surface for the current host platform.
- `executeJavaScript`: constrained JavaScript execution with capability allowlisting and structured errors.

GitHub: [velos/CodeMode.swift](https://github.com/velos/CodeMode.swift)

## Highlights

- Platforms: `iOS 18+`, `macOS 15+`, `visionOS 2+`, `watchOS 11+`
- Typed Swift host API through `CodeModeAgentTools`
- Streaming execution via `JavaScriptExecutionCall`
- Structured failures via `CodeModeToolError`
- Hybrid JS surface:
  - web-style globals: `fetch`, `URL`, `URLSearchParams`, `setTimeout`, `console`
  - cross-platform Apple namespaces: `apple.keychain`, `apple.location`, `apple.weather`, `apple.calendar`, `apple.reminders`, `apple.contacts`, `apple.photos`, `apple.vision`, `apple.notifications`, `apple.health`, `apple.home`, `apple.media`, `apple.fs`
  - platform-specific namespaces when needed: `ios.alarm`
- Node-style aliases for file operations through `globalThis.fs.promises`
- Sandboxed filesystem policy with allowed roots: `tmp`, `caches`, `documents`
- Search and execution only expose helpers supported on the current host platform
- `apple.*` is the canonical cross-Apple namespace, not a promise that every helper exists on every Apple OS
- Library-only package surface

## Installation

Once `0.1.0` is tagged, add `CodeMode.swift` with Swift Package Manager:

```swift
.package(name: "CodeMode", url: "https://github.com/velos/CodeMode.swift", from: "0.1.0")
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
- `CodeModeAgentToolDescriptions`

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
  jsNames: string[];
  summary: string;
  tags: string[];
  example: string;
  requiredArguments: string[];
  optionalArguments: string[];
  argumentTypes: Record<string, string>;
  argumentHints: Record<string, string>;
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
- `timeoutMs`
- `context`

It returns a `JavaScriptExecutionCall` immediately.

Cross-platform privileged helpers are installed under `apple.*`. Platform-specific helpers are installed only where supported, for example `ios.alarm.*` on iOS hosts that support AlarmKit.

`apple.location.requestPermission()` is currently exposed only on iOS hosts. Other Apple platforms can expose `apple.location.*` helpers when supported, but the explicit permission-request helper is intentionally hidden outside iOS for now.

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
- `call.cancel()` performs best-effort cancellation

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
- Contacts (`contacts.read`, `contacts.search`): `NSContactsUsageDescription`
- Calendar read (`calendar.read`): `NSCalendarsFullAccessUsageDescription`
- Calendar write-only (`calendar.write`): `NSCalendarsWriteOnlyAccessUsageDescription`
- Reminders (`reminders.read`, `reminders.write`): `NSRemindersFullAccessUsageDescription`
- Photos (`photos.read`, `photos.export`): `NSPhotoLibraryUsageDescription`
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

- License: MIT. See [LICENSE](LICENSE)

## Acknowledgements

The "Code Mode" framing and the tool-oriented search and execution model in this repository were influenced by Cloudflare's Code Mode work:

- [Cloudflare Code Mode API reference](https://developers.cloudflare.com/agents/api-reference/codemode/)
- [Cloudflare Code Mode announcement](https://blog.cloudflare.com/code-mode/)
- [Cloudflare Code Mode MCP](https://blog.cloudflare.com/code-mode-mcp/)

This repository is an independent implementation and is not affiliated with Cloudflare.

## Development Process

Development of `CodeMode.swift` was done exclusively with Codex, initiated by an interactively built plan, executed by the model after the plan was finalized.

## Deferred in v1

The package intentionally defers these to later phases:

- Push notifications / APNs token lifecycle
- PassKit wallet APIs
- Other frameworks such as Speech, MusicKit, Foundation Models
