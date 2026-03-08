# CodeMode

`CodeMode` is a Swift package that implements [CodeMode](https://blog.cloudflare.com/code-mode/) for iOS native APIs by exposing agents to two tools:

- `searchJavaScriptAPI`: fuzzy discovery of the bundled JavaScript wrapped iOS API surface.
- `executeJavaScript`: constrained JavaScript execution with capability allowlisting and structured errors.

## Highlights

- Platforms: `iOS 18+`, `macOS 15+`
- Typed Swift host API through `CodeModeAgentTools`
- Streaming execution via `JavaScriptExecutionCall`
- Structured failures via `CodeModeToolError`
- Hybrid JS surface:
  - web-style globals: `fetch`, `URL`, `URLSearchParams`, `setTimeout`, `console`
  - privileged namespaces: `ios.keychain`, `ios.location`, `ios.weather`, `ios.calendar`, `ios.reminders`, `ios.contacts`, `ios.photos`, `ios.vision`, `ios.notifications`, `ios.alarm`, `ios.health`, `ios.home`, `ios.media`, `ios.fs`
- Node-style aliases for file operations through `globalThis.fs.promises`
- Sandboxed filesystem policy with allowed roots: `tmp`, `caches`, `documents`
- Library-only package surface

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
    JavaScriptAPISearchRequest(query: "create reminder", limit: 5)
)

print(searchResponse.matches.map(\.capability))

let call = try await tools.executeJavaScript(
    JavaScriptExecutionRequest(
        code: """
        await ios.fs.write({ path: "tmp:note.txt", data: "hello" });
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

- `query`: fuzzy text search
- `capability`: exact capability lookup
- `tags`: optional tag filtering
- `limit`: maximum match count

Behavior:

- empty search input throws `CodeModeToolError(code: "INVALID_REQUEST", ...)` unless `capability` is provided
- no matches is a normal success
- responses include typed `JavaScriptAPIReference` matches plus non-fatal diagnostics

## Execution

`executeJavaScript` accepts `JavaScriptExecutionRequest`:

- `code`
- `allowedCapabilities`
- `timeoutMs`
- `context`

It returns a `JavaScriptExecutionCall` immediately.

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

- Location (`location.read`, `location.permission.request`): `NSLocationWhenInUseUsageDescription`
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

- Local notification scheduling and management (`notifications.*`) requires runtime authorization via `ios.notifications.requestPermission()`
- No additional Info.plist privacy string is required for `UNUserNotificationCenter` authorization prompts

AlarmKit:

- `alarm.*` requires `iOS 26+` and runtime authorization via `ios.alarm.requestPermission()`

HealthKit:

- `health.*` requires the HealthKit entitlement and runtime authorization via `ios.health.requestPermission(...)`

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

Development of `CodeMode` was done exclusively with Codex, initiated by an interactively built plan, executed by the model after the plan was finalized.

## Deferred in v1

The package intentionally defers these to later phases:

- Push notifications / APNs token lifecycle
- PassKit wallet APIs
- Other frameworks such as Speech, MusicKit, Foundation Models
