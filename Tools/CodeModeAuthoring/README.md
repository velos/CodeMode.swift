# CodeModeAuthoring

`CodeModeAuthoring` contains the optional `@CodeMode` macro package. It lives outside the core `CodeMode` package so runtime clients and eval tooling do not inherit a `swift-syntax` dependency.

Hosts that want macro-authored providers can import `CodeModeAuthoring`:

```swift
import CodeMode
import CodeModeAuthoring

@CodeMode(path: "myapp.tasks")
struct TaskAPI: Sendable {
    let store: TaskStore

    @CodeModeName("complete")
    @CodeModeDescription("Mark a task complete.")
    @CodeModeParam("id", "Task identifier")
    @CodeModeParam("note", "Optional completion note")
    @CodeModeResult("Completion payload")
    func completeTask(id: String, note: String?) async throws -> JSONValue {
        try await store.complete(id: id, note: note)
        return .object([
            "id": .string(id),
            "completed": .bool(true),
        ])
    }
}
```

Register provider instances through `CodeModeConfiguration(codeModeProviders:)`:

```swift
let tools = CodeModeAgentTools(
    config: CodeModeConfiguration(
        codeModeProviders: [
            TaskAPI(store: taskStore),
        ]
    )
)
```

The generated JavaScript path and capability key are the same string:

```javascript
await myapp.tasks.complete({ id: "task-123", note: "Done in app" })
```

Custom providers are gated by `allowedCapabilityKeys`, not `allowedCapabilities`:

```swift
let call = try await tools.executeJavaScript(
    JavaScriptExecutionRequest(
        code: #"return await myapp.tasks.complete({ id: "task-123" });"#,
        allowedCapabilities: [],
        allowedCapabilityKeys: ["myapp.tasks.complete"]
    )
)
```

Macro v1 uses a single JSON object argument. Supported parameter and return shapes are JSON primitives, `JSONValue`, arrays/dictionaries of JSON-shaped values, and optional forms. Throw `CodeModeFunctionError` for structured failures that should surface as CodeMode bridge errors.
