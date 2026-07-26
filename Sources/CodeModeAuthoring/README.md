# CodeModeAuthoring

`CodeModeAuthoring` is the optional `@CodeMode` macro surface for host-authored
tools, shipped as a product of the main package (depend on the
`CodeModeAuthoring` product). The `CodeModeMacros` compiler plugin behind it is
the same one the core library uses internally for `@BuiltInCodeMode`; current
toolchains resolve swift-syntax as prebuilt libraries, so the build cost is
small (measured in `PLAN-registration-macros.md`).

Hosts that want macro-authored providers can import `CodeModeAuthoring`:

```swift
import CodeMode
import CodeModeAuthoring

@CodeMode(path: "myapp.tasks.complete", description: "Mark a task complete.")
struct TaskComplete: Sendable {
    let store: TaskStore

    struct Arguments {
        @CodeModeParam("Task identifier")
        var id: String

        @CodeModeParam("Optional completion note")
        var note: String?
    }

    @CodeModeResult("Completion payload")
    struct Result {
        var id: String
        var note: String?
        var completed: Bool
    }

    func call(arguments: Arguments) async throws -> Result {
        try await store.complete(id: arguments.id, note: arguments.note)
        return Result(id: arguments.id, note: arguments.note, completed: true)
    }
}
```

Register provider instances through `CodeModeConfiguration(codeModeProviders:)`:

```swift
let tools = CodeModeAgentTools(
    config: CodeModeConfiguration(
        codeModeProviders: [
            TaskComplete(store: taskStore),
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

The two allowlists are strictly disjoint: a built-in capability ID listed in
`allowedCapabilityKeys` is ignored, and a provider key listed in
`allowedCapabilities` will not decode. Both fields are model-authored, so treat
them as a declaration of intent — set `CodeModeConfiguration.capabilityGrant` for
the host-owned ceiling that actually enforces access.

Macro v1 maps one type to one JavaScript function. `Arguments` must be a nested struct, and no-arg tools use an empty `Arguments` struct. `call(arguments:)` must be `throws` or `async throws`, and it can return `Void` or a nested `Result` struct.

Supported `Arguments` and `Result` property shapes are JSON primitives, `JSONValue`, arrays/dictionaries of JSON-shaped values, and optional forms. Throw `CodeModeFunctionError` for structured failures that should surface as CodeMode bridge errors.
