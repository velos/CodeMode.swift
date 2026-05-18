# CodeModeAuthoring

`CodeModeAuthoring` contains the optional `@CodeMode` macro package. It lives outside the core `CodeMode` package so runtime clients and eval tooling do not inherit a `swift-syntax` dependency.

Hosts that want macro-authored providers can import `CodeModeAuthoring`:

```swift
import CodeModeAuthoring

@CodeMode(path: "myapp.api")
struct MyAPI: Sendable {
    @CodeModeDescription("Do the thing.")
    func doTheThing(id: String) async throws -> String {
        id
    }
}
```

Register provider instances through `CodeModeConfiguration(codeModeProviders:)`.
