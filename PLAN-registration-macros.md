# Plan: macro-generated capability registrations

Goal: reduce the ~115-capability / ~2,850-line hand-written registration surface
and eliminate the parallel-sources-of-truth drift (registration metadata vs
bridge parsing vs central constraint table vs argument-type inference), by
converging on one typed idiom that a macro can generate the boilerplate for.

Written 2026-07-11 after auditing `Tools/CodeModeAuthoring` and the built-in
registration idioms. Verdict up front: **there is a real path forward, in three
phases, and the first phase pays for itself even if the macro phase is later
rejected.**

**Status:** owner approved swift-syntax in the core graph (2026-07-11).
Phase 1 landed the same day: `BuiltInCodeModeTool` + `CodeModeStringEnum`
shipped, EventKit/Keychain/Location/Weather converged on the idiom, the four
EventKit-domain rows are gone from the central constraint table, and the
coherence test guards the remainder. Two Phase-1 notes for Phase 2:
(1) transitional tools carry a `raw: [String: JSONValue]` passthrough because
bridges still consume raw dictionaries — the macro design should keep
generating that until a domain's bridge goes fully typed (Phase 3);
(2) a fifth metadata surface surfaced during migration — the hand-written JS
function table in `RuntimeJavaScript.swift` — worth folding into Phase 3 as
"generate the JS shim table from registrations".

---

## 1. What exists today

### The macro package (`Tools/CodeModeAuthoring`) — built, tested, unwired
- Separate SPM package so core clients don't inherit swift-syntax (README is
  explicit about this).
- `@CodeMode(path:description:)` — attached extension macro on a struct/class/
  actor with a nested `Arguments` struct (`@CodeModeParam` per field) and
  optional nested `Result` (`@CodeModeResult`). Generates a `CodeModeProvider`
  conformance: `codeModePath` + `codeModeRegistrations()` with
  required/optional arguments, `argumentTypes`, `argumentHints`,
  `resultSummary`, and a handler that decodes raw `[String: JSONValue]` into
  the typed `Arguments` and calls `call(arguments:)` (async supported via
  `CodeModeAsyncBridge.run`).
- 607-line implementation, 14 tests, **all passing on Swift 6.3.2 / Xcode 26.5**
  (verified today).
- Scope: host-authored custom tools only (capability *keys*), not built-ins.

### Three coexisting built-in idioms (the boilerplate)
1. **Flat convenience init** (`BuiltInCapabilityRegistration.swift`) — the bulk:
   115 `CapabilityRegistration(...)` callsites across nine
   `CapabilityRegistrations+*.swift` files (~2,850 lines). All metadata is
   hand-typed strings; the handler closes over a bridge and re-parses raw JSON.
2. **`BuiltInCodeModeTool` protocol** (`SimpleBuiltInCodeModeProviders.swift`,
   private) — typed `Arguments` struct + `decode()` + `call(arguments:context:)`
   with static metadata. Used for keychain/location/weather. This is a
   *hand-rolled version of exactly what the macro generates* — proof the shape
   works for built-ins.
3. **Raw `CodeModeRegistration`** inline — used where a capability has multiple
   JS names (e.g. `locationRead` ⇒ `getPermissionStatus` + `getCurrentPosition`).

### The drift surfaces this is meant to kill
| Source of truth | Where | Drift already bitten? |
|---|---|---|
| Registration metadata (args/types/hints) | `CapabilityRegistrations+*.swift` | — |
| Bridge argument parsing | each bridge (`arguments.string(...)`, `lowercased()`) | yes — calendar-span (fixed 2026-07-11) |
| Constraint defaults table | `CapabilityArgumentConstraints.defaults(for:)` central switch | same incident |
| Argument-type inference | `CapabilityDescriptor.inferArgumentTypes` known-name table | silent `.any` degradation |
| Platform support sets | `CapabilityPlatformSupport` | orthogonal, keep |
| Permission checks | split registry (`requiredPermissions`) vs bridge (`ensurePermission`) | healthKit confusion |

### Gap analysis: macro v1 vs what built-ins need
- Handler signature discards `BridgeInvocationContext` — 73 of 115 built-in
  handlers use `context` (permissions, audit, cancellation, presenters).
- No `requiredPermissions` (30 built-in declarations), no
  `argumentConstraints`, no multi-jsName aliases, no `CapabilityID` (only
  string keys), title/tags/example are *derived* while built-ins have curated
  ones, handlers are async-wrapped while built-ins are sync.

### The swift-syntax cost, measured today
- This toolchain defaults to `--enable-experimental-prebuilts` for macros.
- Clean build of the macro package **from scratch** (fresh `.build`, includes
  swift-syntax 601.0.1): **24s wall** on this machine (~126s CPU, parallel).
  Incremental: ~0. CI runners: expect ~1–2 min on a cold cache, amortized by
  the SwiftPM cache we already added to CI.
- Conclusion: the original reason for exiling the macro package (swift-syntax
  tax on every client) is far weaker than when that decision was made. It is
  now a *policy* decision, not a showstopper.

---

## 2. The plan

### Phase 1 — converge on the typed-tool protocol (no macro, shippable alone)
Make idiom #2 the one idiom, extended to cover everything idiom #1 expresses:

1. Promote `BuiltInCodeModeTool` out of `SimpleBuiltInCodeModeProviders.swift`
   into its own file as the internal standard, renamed (working name:
   `CodeModeToolDefinition`). Add the missing axes:
   - `static var codeModeAliases: [String]` (multi-jsName),
   - `static var requiredPermissions: [PermissionKind]`,
   - curated `title`/`tags`/`example` (already present),
   - `call(arguments:context:)` keeps the `BridgeInvocationContext`.
2. **Enum-typed constrained arguments** — the drift killer. Add a
   `CodeModeEnumDecodable` refinement (String raw value + `CaseIterable` +
   optional alias table). An argument declared as such an enum automatically
   yields:
   - `allowedStringValues` for the descriptor (including aliases),
   - case-insensitive decode with aliases (same semantics the bridges
     hand-roll with `lowercased()`),
   - a single place where "what the bridge accepts" and "what the registry
     advertises" are *the same declaration*. Calendar span becomes
     `enum Span: String, CodeModeEnumDecodable { case thisEvent, futureEvents }`
     with aliases `["this_event": .thisEvent, ...]`.
3. Migrate **one domain by hand** to validate the shape: EventKit (9
   registrations, includes the span history and permission checks). Delete its
   rows from `CapabilityArgumentConstraints.defaults(for:)` — the constraint
   comes from the tool now.
4. Add the drift test from TODO: for every registration, assert the descriptor
   metadata matches what the tool's decode actually accepts (for enum params
   this is true by construction; the test guards the unmigrated remainder).

Exit criteria: one idiom documented, EventKit migrated, suite green, constraint
table shrinking. **Value even if Phase 2 never happens:** every migrated domain
is drift-proof; the boilerplate merely remains verbose.

### Phase 2 — bring the macro into the main package (the boilerplate killer)
1. Move the `CodeModeMacros` macro target from `Tools/CodeModeAuthoring` into
   the root `Package.swift`. The `CodeMode` target itself now uses it — this is
   the point where every client inherits swift-syntax (measured cost above;
   gate: owner sign-off).
2. Add an internal `@BuiltInCodeMode` attached macro targeting the Phase-1
   protocol. Macro generates the mechanical parts only:
   - `decode(arguments:)` from the `Arguments` struct fields (incl. enum
     params → constraints),
   - `requiredArguments` / `optionalArguments` / `argumentTypes` /
     `argumentHints` / `argumentConstraints` statics.
   Hand-written (macro arguments or plain statics): `CapabilityID`, aliases,
   permissions, curated title/summary/tags/example, `call(arguments:context:)`.
3. Because macro-authored and hand-written tools implement the same protocol,
   migration is per-domain and incremental — no big bang, and a domain can be
   reverted to hand-written without touching the registry.
4. `Tools/CodeModeAuthoring` keeps its public `@CodeMode` surface for hosts but
   becomes a thin package re-exporting the same macro implementation (or a
   second product of the main package — decide at implementation time; SPM only
   builds targets a chosen product needs, but once `CodeMode` uses macros the
   distinction stops mattering for build cost).
5. Extend the host-facing `@CodeMode` with the same enum-constraint support so
   hosts get constraint metadata too (currently impossible for them).
6. CI gotcha to handle: `xcodebuild` validates macro plugins; the iOS/visionOS
   `platform-build` job will need `-skipMacroValidation` (or trust plumbing).

### Phase 3 — migrate the domains, delete the tables
Suggested order (drift risk × constraint-table usage first):
1. SystemUI (12 registrations, heaviest constraint user: pickers/camera/scan),
2. Core + Keychain + PeoplePhotosDocuments,
3. SystemServices (health/home/alarm — permission-sensitive, good test of the
   `.healthKit` invariant),
4. CloudPushSpeech, IntentsModelsActivityMaps,
5. Commerce (music/passKit/storeKit) **last or never**: these bridges pass raw
   arguments through to host-supplied clients, so a typed `Arguments` struct
   adds little — keeping them on the hand-written protocol is a legitimate end
   state.

End state: delete `CapabilityArgumentConstraints.defaults(for:)` and
`CapabilityDescriptor.inferArgumentTypes` entirely; registry validation fails
loudly on unknown arguments (existing TODO item); `CapabilityPlatformSupport`
stays (orthogonal — could become a macro argument later, not required).

---

## 3. What NOT to do
- **Don't generate registrations from bridge methods.** Bridges take
  `[String: JSONValue]` — there is no type information to harvest. The typed
  `Arguments` struct has to exist first, and once it exists the protocol+macro
  design above is strictly simpler than source-scraping.
- **Don't do a 115-callsite big-bang migration.** The two-idiom coexistence
  window is priced in; the drift test covers the unmigrated remainder.
- **Don't macro-generate curated prose** (titles, summaries, examples). The
  derived versions in macro v1 (`title = last path component`) are fine for
  host tools but would degrade the LLM-facing catalog for built-ins.

## 4. Open decisions (owner)
1. Accept swift-syntax in the core package graph? (Measured: 24s clean local,
   ~0 incremental, prebuilts default-on. If "no", stop after Phase 1 — still
   worth it.)
2. Should the Phase-1 protocol be public (hosts could adopt it without macros)
   or internal-only until it stabilizes? Recommendation: internal until Phase 3
   is done.
3. Keep `Tools/CodeModeAuthoring` as a separate package (re-export) or fold it
   in as a product? Recommendation: fold in during Phase 2; one macro
   implementation, two attribute surfaces.

## 5. Effort estimate
- Phase 1: 1–2 focused sessions (protocol + enum decode + EventKit + drift test).
- Phase 2: 1–2 sessions (mostly extending the existing 607-line macro impl,
  package plumbing, CI macro-validation flag).
- Phase 3: mechanical, ~1 session per 2–3 domains; parallelizable; each domain
  lands independently green.
