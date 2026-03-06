# CodeMode

`CodeMode` is a Swift package that exposes two agent-oriented operations over JavaScriptCore:

- `searchJavaScriptAPI`: fuzzy discovery of the bundled JS APIs and examples.
- `executeJavaScript`: run constrained JavaScript with explicit capability allowlisting.

## Highlights

- iOS-first target (`iOS 18+`) with `JavaScriptCore` runtime.
- Hybrid JS surface:
  - web-style globals: `fetch`, `URL`, `URLSearchParams`, `setTimeout`, `console`
  - privileged namespaces: `ios.keychain`, `ios.location`, `ios.weather`, `ios.calendar`, `ios.reminders`, `ios.contacts`, `ios.photos`, `ios.vision`, `ios.notifications`, `ios.alarm`, `ios.health`, `ios.home`, `ios.media`, `ios.fs`
- Node compatibility subset: `globalThis.fs.promises` aliases for common file operations.
- Sandboxed filesystem policy with allowed roots (`tmp`, `caches`, `documents`).

## Quick Start

```swift
import CodeMode

let tools = CodeModeAgentTools()

let search = try await tools.searchJavaScriptAPI(
    JavaScriptAPISearchRequest(query: "create reminder", limit: 5)
)

let detail = try await tools.searchJavaScriptAPI(
    JavaScriptAPISearchRequest(capability: .remindersWrite)
)

let call = try await tools.executeJavaScript(
    JavaScriptExecutionRequest(
        code: """
            await ios.fs.write({ path: 'tmp:note.txt', data: 'hello' });
            return await fs.promises.readFile('tmp:note.txt', 'utf8');
            """,
        allowedCapabilities: [.fsWrite, .fsRead]
    )
)

for await event in call.events {
    if case .log(let entry) = event {
        print(entry.message)
    }
}

let result = try await call.result
print(result.output ?? .null)
```

`searchJavaScriptAPI` supports:

- fuzzy text lookup using `query`, optional `tags`, and `limit`
- exact capability lookup using `capability`

`executeJavaScript` returns a streaming call handle. The event stream emits logs, non-fatal diagnostics, and a terminal event for syntax errors, missing JS helpers, JS throws, or tool failures. `call.result` returns the final structured output or throws a `CodeModeToolError` with machine-readable fields that hosts can format however they want.

The root package is library-only. Eval tooling lives in a separate package at `Tools/CodeModeEvalCLI`.

## Host App Permissions and Capabilities

Yes, host apps must provide privacy usage strings for bridged APIs that request protected resources.

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

- Local notification scheduling/management (`notifications.*`) requires runtime authorization via `ios.notifications.requestPermission()`.
- No additional Info.plist privacy string is required for `UNUserNotificationCenter` authorization prompts.

AlarmKit:

- `alarm.*` requires iOS 26+ and runtime authorization via `ios.alarm.requestPermission()`.

HealthKit:

- `health.*` requires HealthKit capability/entitlement and runtime authorization (use `ios.health.requestPermission(...)`).

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
