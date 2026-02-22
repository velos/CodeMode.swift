# CodeMode

`CodeMode` is a Swift package that exposes two MCP-style operations over JavaScriptCore:

- `search`: fuzzy discovery of bridged APIs and examples.
- `execute`: run constrained JavaScript with explicit capability allowlisting.

## Highlights

- iOS-first target (`iOS 18+`) with `JavaScriptCore` runtime.
- Hybrid JS surface:
  - web-style globals: `fetch`, `URL`, `URLSearchParams`, `setTimeout`, `console`
  - privileged namespaces: `ios.keychain`, `ios.location`, `ios.weather`, `ios.calendar`, `ios.reminders`, `ios.contacts`, `ios.media`, `ios.fs`
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

## Host App Permissions and Capabilities

Yes, host apps must provide privacy usage strings for bridged APIs that request protected resources.

Required Info.plist keys by capability:

- Location (`location.read`, `location.permission.request`): `NSLocationWhenInUseUsageDescription`
- Contacts (`contacts.read`, `contacts.search`): `NSContactsUsageDescription`
- Calendar read (`calendar.read`): `NSCalendarsFullAccessUsageDescription`
- Calendar write-only (`calendar.write`): `NSCalendarsWriteOnlyAccessUsageDescription`
- Reminders (`reminders.read`, `reminders.write`): `NSRemindersFullAccessUsageDescription`

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

- Push notifications / APNs token lifecycle
- PassKit wallet APIs
- Photos + Vision pipeline
- Other frameworks such as Speech, MusicKit, HomeKit, Foundation Models
