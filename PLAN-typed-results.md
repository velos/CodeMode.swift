# Plan: typed results for built-in tools

Status: decided. Implemented on `typed-bridges` for the EventKit family first, then with each
family's typed-arguments migration.

## Problem

Every helper is declared `(…): Promise<CodeModeValue>`. The only description of what comes back
is `codeModeResultSummary`, a hand-written sentence (120 of them, 111 distinct) that nothing
checks against the JSON the bridge actually builds. Models guess field names from prose, a
host's `tsc` cannot catch a wrong one, and the summary drifts from the code the first time
someone renames a key.

## Shapes in use today

From the 120 summaries and the bridges behind them:

- an object with fixed fields, some present only "when available" (the common case);
- an array of such objects (every list helper);
- a string-keyed map of values (Vision's per-feature sections, form values keyed by field id);
- a nullable object (`keychain.get` returns null for a missing key);
- a handful of genuine unions (`location.read`: a status string or a coordinates object).

Unions stay `CodeModeValue` with prose. Everything else gets a schema.

## Design

**Schema is derived from Swift types at runtime, not parsed by the macro.** The macro is
syntactic and cannot see a struct declared elsewhere, but results are shared across tools
(`CalendarEvent` is returned by list, create and update) and nested (an array of events). So:

```swift
indirect enum CodeModeResultSchema: Sendable, Codable, Equatable {
    case string, number, bool, any
    case nullable(CodeModeResultSchema)
    case array(CodeModeResultSchema)
    case dictionary(CodeModeResultSchema)
    case object([Field])
    struct Field: Sendable, Codable, Equatable { var name: String; var schema: CodeModeResultSchema; var hint: String? }
}

protocol CodeModeResultDescribable: CodeModeJSONEncodable {
    static var codeModeResultSchema: CodeModeResultSchema { get }
}
```

Conformances: `String`, `Int`, `Double`, `Float`, `Bool`, `Date` (an ISO 8601 string), `JSONValue`
(`.any`), `Optional` (`.nullable`), `Array`, `Dictionary<String, _>`. Composition is by the type
system, so `[CalendarEvent]?` describes itself.

**`@ToolResult` marks a result struct.** It generates `codeModeJSONValue` (an object of the
encoded stored properties, in declaration order) and `codeModeResultSchema` (an `.object` of
fields). An optional `@ToolField("hint")` on a property becomes the field's doc comment. Field
types must themselves be `CodeModeResultDescribable`; the compiler enforces it. One struct can
serve several tools.

**The tool protocol gains a typed result.**

```swift
protocol BuiltInCodeModeTool {
    associatedtype Result: CodeModeResultDescribable
    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> Result
}
```

The registration handler encodes `result.codeModeJSONValue`. The descriptor carries
`Result.codeModeResultSchema` and a summary derived from it. `codeModeResultSummary` becomes a
protocol extension default rendered from the schema; a tool still returning `JSONValue`
(schema `.any`) overrides it with its existing prose. That is the migration seam: unmigrated
tools compile unchanged, apart from the derived default they already override.

**The catalog and the public surface.** `CapabilityDescriptor` and `JavaScriptAPIReference` gain
`resultSchema: CodeModeResultSchema?`, decoded with a default so earlier encodings still load.
`TypeScriptDeclarations` renders it as the promise's type argument: an object literal type with
`?` for nullable fields, `Array<…>`, `{ [key: string]: … }`, `| null`. The derived summary is a
one-line rendering of the same type, for search results.

**Behaviour preservation.** The JSON a script receives does not change: same keys, same values,
same `""` where the bridge coalesces a missing string today. Whether those should become `null`
(and therefore `string | null` in the declaration) is a separate, model-facing decision; it is
deferred, and the schema makes it a one-line change per field when taken.

## What this is not

- Not a change to the host-facing `@CodeMode` macro, which already has a `Result` struct. Aligning
  the two macros on one implementation is desirable and later.
- Not result validation at runtime. The encoder is generated from the same struct the schema
  comes from, so they cannot disagree.
