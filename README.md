# CodeMode

`CodeMode` is a Swift package that exposes two MCP-style operations over JavaScriptCore:

- `search`: fuzzy discovery of bridged APIs and examples.
- `execute`: run constrained JavaScript with explicit capability allowlisting.

## Highlights

- iOS-first target (`iOS 18+`) with `JavaScriptCore` runtime.
- Hybrid JS surface:
  - web-style globals: `fetch`, `URL`, `URLSearchParams`, `setTimeout`, `console`
  - privileged namespaces: `ios.keychain`, `ios.location`, `ios.weather`, `ios.calendar`, `ios.reminders`, `ios.contacts`, `ios.photos`, `ios.vision`, `ios.notifications`, `ios.home`, `ios.media`, `ios.fs`
- Node compatibility subset: `globalThis.fs.promises` aliases for common file operations.
- Sandboxed filesystem policy with allowed roots (`tmp`, `caches`, `documents`).

## Quick Start

```swift
import CodeMode

let host = CodeModeBridgeHost()

let search = try await host.search(
    SearchRequest(mode: .discover, query: "create reminder", limit: 5)
)

let detail = try await host.search(
    SearchRequest(mode: .describe, capability: .remindersWrite)
)

let response = try await host.execute(
    ExecuteRequest(
        code: """
        await ios.fs.write({ path: 'tmp:note.txt', data: 'hello' });
        return await fs.promises.readFile('tmp:note.txt', 'utf8');
        """,
        allowedCapabilities: [.fsWrite, .fsRead]
    )
)

print(response.resultJSON ?? "null")
```

`search` modes:

- `discover`: fuzzy capability search using `query`, optional `tags`, and `limit`.
- `describe`: schema/detail lookup for one capability using `capability` (required/optional args + expected types).

`execute` now performs schema-first argument validation (required args, type checks, unknown-argument rejection) before bridge execution. Argument errors include a usage hint with expected argument types and an example call to help small models recover without another tool call.

## Eval CLI

The package includes an eval CLI (`codemode-eval`) for prompt-to-tool/script evaluation using mocked bridges and objective checks.

`codemode-eval` now runs a bounded multi-step planner for execute scenarios (up to 4 turns): it can call `search`, then `execute`, and perform one automatic repair retry after static validation/runtime errors.

Run with scripted baseline:

```bash
swift run codemode-eval --model scripted
```

Run with Wavelike proxy model provider:

```bash
export WAVELIKE_APP_ID=your-app-id
export WAVELIKE_MODEL_ID=gpt-4.1-mini
# optional:
# export WAVELIKE_ENV=stage   # local|stage|production
# export WAVELIKE_API_KEY=...
# or export WAVELIKE_USER_ID=... && export WAVELIKE_USER_KEY=...

swift run codemode-eval --model wavelike
```

Run with local Apple Foundation Model via Wavelike engine:

```bash
# optional; defaults to com.apple.SystemLanguageModel.default
# export WAVELIKE_MODEL_ID=com.apple.SystemLanguageModel.default
# optional; defaults to codemode-eval-local
# export WAVELIKE_APP_ID=codemode-eval-local

swift run codemode-eval --model apple
```

Filter scenarios or inspect generated calls:

```bash
swift run codemode-eval --model scripted --scenario morning-brief,fetch-json-and-save --show-generated
```

Trace model-level diagnostics (prompt, raw-output preview, and detailed error chain):

```bash
swift run codemode-eval --model apple --trace-model
```

Pluggable external model adapter:

```bash
swift run codemode-eval --model command --model-command /path/to/adapter
```

The command adapter reads JSON from stdin (`prompt`, `capabilities`) and must return JSON:
- `{"tool":"search","search":{"mode":"discover","query":"...","limit":10}}`
- `{"tool":"search","search":{"mode":"describe","capability":"calendar.write"}}`
- `{"tool":"execute","code":"...javascript..."}`

`guidance` may also be included in stdin for multi-step planning context (prior search output or error feedback).

## Host App Permissions and Capabilities

Yes, host apps must provide privacy usage strings for bridged APIs that request protected resources.

Required Info.plist keys by capability:

- Location (`location.read`, `location.permission.request`): `NSLocationWhenInUseUsageDescription`
- Contacts (`contacts.read`, `contacts.search`): `NSContactsUsageDescription`
- Calendar read (`calendar.read`): `NSCalendarsFullAccessUsageDescription`
- Calendar write-only (`calendar.write`): `NSCalendarsWriteOnlyAccessUsageDescription`
- Reminders (`reminders.read`, `reminders.write`): `NSRemindersFullAccessUsageDescription`
- Photos (`photos.read`, `photos.export`): `NSPhotoLibraryUsageDescription`
- HomeKit (`home.read`, `home.write`): `NSHomeKitUsageDescription`

Notifications:

- Local notification scheduling/management (`notifications.*`) requires runtime authorization via `ios.notifications.requestPermission()`.
- No additional Info.plist privacy string is required for `UNUserNotificationCenter` authorization prompts.

Weather:

- `weather.read` requires enabling the **WeatherKit** capability on the App ID/target.
- Weather itself does not require a separate privacy prompt in this package because `weather.read` expects explicit coordinates.

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
    print("[\\(issue.severity.rawValue)] \\(issue.key): \\(issue.message)")
}
```

## Deferred in v1

The package intentionally defers these to later phases:

- Push notifications / APNs token lifecycle (local notifications are included in v1)
- PassKit wallet APIs
- Other frameworks such as Speech, MusicKit, Foundation Models
