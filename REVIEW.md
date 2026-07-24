# CodeMode.swift — review and improvement proposal

Reviewed at `9e58efd` across four dimensions: execution runtime, security layer,
public API/architecture, and bridges/tests/CI. Every finding below was verified
against the source; file:line references point at the code as of that commit.

This document is a proposal, not a change. Items already tracked in `TODO.md`
are marked **[tracked]**; everything else is new.

## Verdict

The agent-facing surface is the strongest part of this package and is ahead of
most of the ecosystem: structured `CodeModeToolError` with line/column and repair
suggestions, a lenient decoder for LLM tool-call quirks, platform-filtered
catalogs, a real preemptive JSC watchdog, a genuinely capability-free search
context, and a deterministic eval harness wired into CI. Those are the hard
parts to get right and they are right.

Three structural choices, plus a short list of concrete bugs, are what stand
between this and "the best way to do CodeMode in a Swift app":

1. **The bridge ABI is synchronous**, so the runtime has no event loop. `Promise.all`
   is silently serial and every native call blocks a thread.
2. **The model self-grants its own capabilities.** `allowedCapabilities` is a
   model-authored tool argument with no host-side ceiling anywhere in the package.
3. **The model never sees types.** No TypeScript declarations are generated,
   which is the central insight of Cloudflare's Code Mode.

## P0 — fix before tagging a release

### 1. `allowedCapabilities` is not a security boundary (high)

`CodeModeAgentTools.executeJavaScript` passes the request straight through, and
`BridgeRuntime.execute` seeds the invocation context directly from it
(`Sources/CodeMode/Runtime/BridgeRuntime.swift:187-188`):

```swift
allowedCapabilities: Set(request.allowedCapabilities),
allowedCapabilityKeys: Set(request.allowedCapabilityKeys),
```

`allowedCapabilities` is an argument in the advertised tool schema
(`Sources/CodeMode/Host/CodeModeAgentToolDescriptions.swift:33-54`), and the
repair guide instructs the model to escalate on denial: *"CAPABILITY_DENIED: add
the exact capability to allowedCapabilities or allowedCapabilityKeys and retry."*
There is no host-owned ceiling in the package. A host that pipes tool JSON
straight into `executeJavaScript` — exactly what the README Quick Start models —
has no enforcement: the script declares `["keychain.read", "network.fetch"]` and
gets them.

Least-privilege *hinting* is a real and useful feature; it should not be confused
with enforcement. Two fixes, both needed:

- Add `grantedCapabilities: Set<CapabilityID>` / `grantedCapabilityKeys` to
  `CodeModeConfiguration` and intersect at `BridgeRuntime.swift:187` before the
  context is built. Default can stay permissive for source compatibility, but the
  README and tool descriptions must state which set is authoritative.
- Document `allowedCapabilities` as a model-declared *intent*, so integrators
  don't mistake it for a sandbox.

### 2. `allowedCapabilityKeys` silently grants built-in capabilities (high)

`BridgeInvocationContext.init` unions the two sets
(`Sources/CodeMode/Runtime/BridgeInvocationContext.swift:32`):

```swift
self.allowedCapabilityKeys = allowedCapabilityKeys.union(allowedCapabilities.map(\.codeModeKey))
```

and `invokeBuiltIn` accepts either (`Sources/CodeMode/Registry/CapabilityRegistry.swift:538`):

```swift
guard context.allowedCapabilities.contains(capability) || context.allowedCapabilityKeys.contains(capability.codeModeKey) else {
```

while `registeredFunction(for: CodeModeCapabilityKey)` resolves built-ins first
(`CapabilityRegistry.swift:512-518`). So `{"allowedCapabilities": [], "allowedCapabilityKeys": ["keychain.read"]}`
reaches the built-in keychain bridge. `allowedCapabilities` is strictly validated
against `CapabilityID` at decode time (`BridgeModels.swift:177-193`);
`allowedCapabilityKeys` accepts arbitrary strings. Any host that vets only the
former is bypassed — and `Sources/CodeModeAuthoring/README.md:60` tells hosts the
two are separate.

Fix: drop the `||` clause, and reject a `capabilityKey` in `invokeCodeMode` that
parses as a built-in `CapabilityID`. The direction that must keep working
(built-in ID granting the built-in) already does.

### 3. `Int(Double)` traps on adversarial numbers — in-process app kill (high)

`Sources/CodeMode/Support/JSONValue.swift:134-139`:

```swift
var intValue: Int? {
    if case let .number(value) = self {
        return Int(value)
    }
```

`Int.init(_: Double)` traps on non-finite and out-of-range input. 48 `.int(...)`
call sites share this; the registry's type check only verifies `.number`
(`CapabilityRegistry.swift:659`), and `coerceScalarString` (`:597`) parses
declared-number strings with `Double(trimmed)`, which accepts `"inf"`/`"nan"`.
`await fetch(url, { timeoutMs: 1e300 })` kills the host process. The same trap
sits on the pre-JS path at `BridgeModels.swift:209` and `:213`, reachable from a
tool call before any script runs.

Fix: make the conversion total —
`value.isFinite && value >= -9.2e18 && value <= 9.2e18 ? Int(value) : nil` —
reject non-finite in `coerceScalarString`, and clamp `decodeTimeoutMs`. Also
clamp `timeoutMs` to the 60 000 ceiling the schema already advertises
(`CodeModeAgentToolDescriptions.swift:50` vs. unclamped `BridgeModels.swift:197`).

### 4. `fs.move` / `fs.copy` recursively delete the destination (high)

`Sources/CodeMode/Bridges/FileSystemBridge.swift:98-100` and `:117-119`:

```swift
if fileSystem.itemExists(at: toURL) {
    try fileSystem.removeItem(at: toURL)
}
```

No `overwrite` flag, no directory check, and `toURL` is only checked for
containment. `DefaultPathPolicy.resolve(path: "documents:")` yields the documents
root itself (`PathPolicy.swift:60-82`), which `isAllowed` accepts via
`path == allowed` (`:92`). So `apple.fs.move({ from: 'tmp:junk.txt', to: 'documents:' })`
recursively removes the user's Documents root. `fs.delete` already guards this
correctly (`FileSystemBridge.swift:140-143`), so the two operations disagree.
Tests only cover file-to-file moves.

Fix: refuse when `toURL` is an allowed root, require `overwrite: true` before any
`removeItem`, and require `recursive: true` when the destination is a directory —
matching `fs.delete`. Also cap `fs.read` (a 2 GB file in `documents:` is currently
read whole and base64-serialized) and stop silently turning invalid UTF-8 into
`""` (`:43`).

### 5. Network requests ride the host app's ambient credentials (medium-high)

`NetworkBridge.init(session: URLSession = .shared, …)`
(`Sources/CodeMode/Bridges/NetworkBridge.swift:9`) and the production wiring takes
the default (`DefaultCapabilityLoader.swift:81`). `URLSession.shared` uses
`HTTPCookieStorage.shared` and `URLCredentialStorage.shared`; nothing disables
cookies. Caller-supplied headers are copied verbatim including `Authorization`
(`:47-53`). A script gets authenticated session-riding against any origin the app
has cookies for, and can poison the app's cookie jar via `Set-Cookie`. The tests
use `.ephemeral` (`NetworkBridgeTests.swift:65-67`), so the shipping default is
untested.

Fix: default to `URLSession(configuration: .ephemeral)` with `httpCookieStorage`,
`urlCredentialStorage`, and `urlCache` nil, `httpShouldSetCookies = false`, and
reject caller-supplied `Cookie`/`Authorization`/`Proxy-*` headers unless the host
opts in. The sandbox's whole premise is that script traffic carries no ambient
authority.

### 6. Unbounded memory — the most realistic crash vector (high) **[partly tracked]**

Nothing caps output, logs, or event buffering:

- `BridgeRuntime.swift:677-706` stringifies the whole result, converts to a Swift
  `String`, and re-decodes into `JSONValue`.
- `ExecutionSupport.swift:31-36` appends every `console.log` with no cap, and the
  whole log array is copied again into every `CodeModeToolError` (`:731-750`).
- The events `AsyncStream` uses default unbounded buffering, so a chatty script
  buffers a million events if the host isn't draining.
- `fs.write` has no size or quota check (`FileSystemBridge.swift:83`).

A single script jetsams an iOS host. Fix: cap serialized result bytes and
truncate with a diagnostic, cap transcript log count/bytes, and construct the
stream with `AsyncStream(bufferingPolicy: .bufferingNewest(n))`. For an LLM
consumer a truncated-with-notice result is strictly better than an OOM.

### 7. `CLLocationManager` is created on a run-loop-less thread (high)

`Sources/CodeMode/Security/SystemPermissionBroker.swift:420-443` constructs the
manager and assigns the delegate on the bridge execution thread, then dispatches
only `requestWhenInUseAuthorization()` to main. `CLLocationManager` delivers
delegate callbacks on the run loop of the thread that created it, and
`BridgeRuntime`'s GCD workers have none — so
`locationManagerDidChangeAuthorization` never arrives, `delegate.wait(timeout: 10)`
always times out, and the subsequent `locationStatus()` re-read races the TCC
write. Every first-time location grant costs a dead 10 s and can report
`notDetermined` after the user tapped Allow.

The `main.sync` deadlock noted in `TODO.md` was fixed; this is the remaining half.
Fix: create the manager, assign the delegate, and request authorization all inside
the `DispatchQueue.main.async` block (or adopt the async CoreLocation APIs).

### 8. `EventKitBridge.readReminders` has a data race and swallows timeouts (high)

`Sources/CodeMode/Bridges/EventKitBridge.swift:99-133` writes `var result` from
the EventKit completion queue, reads it after
`_ = semaphore.wait(timeout: .now() + 15)` with the timeout result discarded, and
returns `.array([])` on timeout — indistinguishable from "no reminders", while the
late callback writes concurrently with the caller's read. Every other bridge uses
`LockedBox` + a thrown `BridgeError.timeout`; this one predates the pattern.

Fix: migrate it to the shared pattern and throw on timeout. Worth extracting one
`waitForCompletion` helper and migrating the broker's `request*` methods to it too.

## P1 — the architecture changes that decide the question

### 9. Make the bridge ABI async and give the runtime a real event loop

This is the single highest-leverage change in the document; several P0 items are
downstream of it.

Today `CapabilityHandler` is `@Sendable (args, context) throws -> JSONValue`
(`CapabilityRegistry.swift:3`), the JS bridge is a synchronous
`@convention(block) (String, String) -> String` (`BridgeRuntime.swift:232`), and
`__invokeAsync` is just `Promise.resolve().then(sync call)`
(`RuntimeJavaScript.swift:159-161`). Consequences, all verified:

- **`Promise.all([fetch(a), fetch(b), fetch(c)])` runs strictly sequentially.**
  The promise API advertises concurrency the runtime cannot deliver — and fan-out
  is the main reason to hand an agent code instead of tool calls.
- **`setTimeout` is a lie** (`RuntimeJavaScript.swift:203-209`): it invokes the
  callback synchronously and ignores the delay, so `clearTimeout` can never
  cancel, thrown errors propagate to setTimeout's *caller*, and
  `await new Promise(r => setTimeout(r, 2000))` backoff becomes a hot loop that
  hammers remote APIs through `fetch`.
- **Timeout and cancel cannot interrupt a native call.** The watchdog only traps
  while JS runs; `invokeBlock` checks cancellation at entry/exit only
  (`BridgeRuntime.swift:234, 242`). `MediaBridge.transcode` waits up to 300 s
  (`MediaBridge.swift:120`), so `timeoutMs: 5000` can overrun by five minutes,
  and side effects land after `cancel()`.
- **Async host tools block threads.** The authoring macro routes through
  `CodeModeAsyncBridge.run`, which parks a `DispatchSemaphore` for up to 30 s
  (`CodeModeProvider.swift:367-391`) — longer than the 10 s default execution
  timeout — and a cancellation-ignoring operation keeps running detached with its
  result silently dropped.
- **Unbounded thread growth.** `executionQueue` is `.concurrent` with no width
  limit (`BridgeRuntime.swift:25-29`) and each execution blocks its thread for the
  whole run. Thirty parallel executions means thirty blocked GCD threads and
  thirty live JSC VMs. **[tracked]**

Proposal: resolve JS promises from Swift via retained resolve/reject `JSValue`s on
a per-execution serial executor, pumping microtasks between native completions.
Change `CapabilityHandler` to an async signature (or add one and deprecate the
sync form). Then add a bounded execution slot count, and optionally pool
`JSVirtualMachine`s — noting the constraint the current watchdog depends on: the
JSC time limit is per context *group*, so a pooled VM must never host two
concurrent executions.

Two cheap wins available immediately, before the full rework:

- `waitForSettlement` (`BridgeRuntime.swift:507-543`) polls a state that under the
  synchronous model is already final when `evaluateScript` returns. A still-pending
  promise is provably unsettleable — report
  `JS_RUNTIME_ERROR: promise can never settle (no event loop)` immediately instead
  of sleeping a thread to the deadline.
- Nothing installs an unhandled-rejection hook, so a forgotten `await` — the
  single most common LLM JS mistake — silently discards a `CAPABILITY_DENIED`
  and the agent is told "done". At minimum emit a diagnostic.

### 10. Generate TypeScript declarations from the registry

`grep` finds no `.d.ts` generation anywhere. The model gets metadata records
(`JavaScriptAPIReference`, `BridgeModels.swift:78-122`) with a flat
`argumentTypes` map of six coarse cases and a prose `resultSummary` — result
shapes are never typed at all (default: `"JSON value"`). Cloudflare's core insight
is that models write dramatically better code against real types.

The registry already holds names, required/optional args, types, enum constraints,
and hints. Proposal: add a typed result schema to `BuiltInCodeModeTool` (the
`@CodeMode` macro already parses a `Result` struct), then emit a per-capability
`dts` string on each reference plus a whole-surface
`CodeModeAgentTools.typeDeclarations()` that hosts drop into the system prompt.
Keep code-driven search as the *filter* — it's a genuine differentiator — but make
its payload TypeScript.

### 11. Generate the JS bindings from the catalog; kill the hand-written bootstrap

`RuntimeJavaScript.swift:260-393` is ~250 lines of hand-written JS duplicating
registration metadata, and `builtInBootstrap` installs catalog `jsNames` only *if
missing* (`:189-194`) — so the hand-written wrappers win and can drift. Drift
already exists: the tool description says "apple.* helpers take one object
argument" (`CodeModeAgentToolDescriptions.swift:119`) while
`apple.keychain.get(key)` is positional (`RuntimeJavaScript.swift:262`), and
wrappers inject hidden arguments the catalog doesn't express (`createEvent` adds
`operation: 'create'`, `:275`). This is the fifth parallel metadata surface noted
in `TODO.md`. The catalog is the model's ground truth; catalog-vs-binding
divergence produces confusion the model cannot debug. **[tracked]**

### 12. Stop imposing swift-syntax on every consumer

`Package.swift:53` makes the core `CodeMode` target depend on the
`CodeModeMacros` compiler plugin, because built-ins use the internal
`@BuiltInCodeMode` macro. Every consumer of the plain `CodeMode` product inherits
a macro plugin and its co-resolution constraints — the comment at
`Package.swift:27-32` documents a real conflict with `mlx-swift-lm`, i.e. exactly
the LLM-adjacent packages this library's consumers use. Consumers never expand the
macro; it is authoring-time infrastructure.

Fix: check in the expanded registrations (or add a generated-source build step) so
`CodeMode` drops the dependency, and keep the plugin behind the opt-in
`CodeModeAuthoring` product. Cheapest large adoption win available.

### 13. Make host extensibility first-class, and open an MCP seam

Hosts registering their own domain APIs is the value proposition, and it works
today — but as one-function-per-type: `@CodeMode` maps one struct to one JS
function (`Sources/CodeModeAuthoring/README.md:72`), so 25 domain APIs means 25
provider structs. The generated registration is also weaker than built-ins:
`example` is always the vacuous `"await \(path)({})"`, `tags` is just the parent
path (`CodeModeMacro.swift:119-121`), and there is no `CodeModeStringEnum`
constraint support, no `requiredPermissions`, no typed result.

Proposal: `@CodeModeProvider(namespace:)` on a type with `@CodeModeTool` on
methods, with parity on constraints, examples, permissions, and typed results.
Unify the allowlists while you're there (see P0 #2) so the model doesn't have to
reason about two fields.

That plus async handlers is also what unlocks **MCP**: an adapter that lists an
MCP server's tools and materializes them as `CodeModeRegistration`s under
`mcp.<server>.<tool>` is Cloudflare's Code Mode MCP on-device, and would make this
package compelling well beyond Apple APIs. Blocker to remove first: the registry
and catalog are snapshotted in `CodeModeAgentTools.init`
(`CodeModeAgentTools.swift:33-41`, `BridgeCatalog.swift:15-37`), so
`CapabilityRegistry`'s public post-init `register(...)` methods (`:445-471`) are
unreachable in the supported flow and would desync search from execution if
reached. Rebuild the catalog snapshot when providers change.

## P2 — correctness and polish

- **Watchdog re-arm grants a second full timeout.** `BridgeRuntime.swift:481`:
  `watchdog.rearm(timeoutMs: max(timeoutMs, 1_000))` — the comment says "bounded
  budget", but `max` means a 120 s execution gets another 120 s for
  `JSON.stringify`. `min` appears intended.
- **Watchdog termination during serialization is misreported.** After the re-arm,
  `watchdog.termination` is never consulted (`:668-707`), so a runaway getter
  surfaces as `INVALID_RESULT: "must be JSON-serializable"` — steering the model
  to the wrong fix.
- **ISO8601 fractional seconds are rejected, then silently replaced with "now".**
  `EventKitBridge.swift:18-19` uses a plain `ISO8601DateFormatter`, so
  `2026-07-24T10:00:00.000Z` (a spelling LLMs emit constantly) fails to parse,
  and `isoDate(...) ?? Date()` (`:193-196`) substitutes now/+14d with no
  diagnostic — the script gets a plausible but wrong window. Health and Alarm
  already try both formats. Centralize one parser and *reject* unparseable dates.
- **HealthKit "granted" is fabricated.** `HealthBridge.swift:14-40` maps
  `requestAuthorization`'s `success` (which only means the sheet flow completed)
  to `"granted": true`, and treats `getRequestStatusForAuthorization == .unnecessary`
  as `.granted` (`:323-356`) though HealthKit deliberately hides read denial.
  Reads then return `[]` while the transcript claims permission. Note the broker's
  `healthKitStatus` always returns `.notDetermined`
  (`SystemPermissionBroker.swift:398-407`) — it fails *closed*, so do not "fix"
  it into an always-granted stub.
- **Permission prompts escalate mid-script with a 10 s human deadline.**
  `BridgeInvocationContext.swift:76-98` auto-escalates `notDetermined` into a
  blocking TCC dialog during unattended execution, and the broker's `request*`
  methods wait 10 s and ignore the timeout — a user who takes 11 s gets
  `PERMISSION_DENIED` while the dialog is still on screen. There is no
  "prompt pending" status.
- **HomeKit status checks trigger prompts.** Constructing `HMHomeManager` alone
  triggers the TCC prompt, and `homeKitStatus()` constructs one inside
  `status(for:)` (`SystemPermissionBroker.swift:323-339`);
  `requestHomeKitPermission` calls it twice (`:563-564`).
- **`bare` single-label hosts bypass the private-network block.**
  `NetworkAccessPolicy.swift:99-107` blocks `localhost`, `*.local`, `*.internal`
  and IP literals, but `router`, `intranet`, `wpad`, `nas` fall through to
  `return false` (`:122`) and resolve to RFC1918 via DHCP search domains. The doc
  comment at `:8-9` ("hosts on the local network") oversells what `:25-27`
  accurately enumerates.
- **`auth.ui.webAuthenticate` runs in the shared browser session.**
  `UIKitSystemUIPresenter+CommunicationWeb.swift:422-431` never sets
  `prefersEphemeralWebBrowserSession`, and `SystemUIBridge.swift:148-154`
  validates only that the URL is HTTP(S) — no host allowlist, and
  `NetworkAccessPolicy` is not consulted for it or for `web.ui.present`. A script
  can start an OAuth flow under the user's live Safari session and receive the
  callback URL. **[tracked as deferred]**
- **Implicit-unwrap crashes in EventKit serialization.**
  `EventKitBridge.swift:490, 501`: `event.calendar.calendarIdentifier`
  (`EKCalendar!`, nil for orphaned events) and `.string(reminder.title)`
  (`String!`) crash the execution thread; every neighboring field is
  nil-coalesced.
- **Force-unwrapped `URL(string:)!`** at
  `UIKitSystemUIPresenter+CommunicationWeb.swift:368, 405` — safe via the bridge
  (which parses first) but `UIKitSystemUIPresenter` is public API.
- **Dangling symlinks pass containment.** `PathPolicy.swift:101-105` walks up
  while `fileExists` is false, and `fileExists` follows symlinks — so a symlink to
  a nonexistent out-of-root target is treated as a missing component and admitted.
  Low blast radius today (atomic writes replace rather than follow, JS cannot
  create symlinks), but it matters if a host swaps in a non-atomic
  `CodeModeFileSystem`.
- **Dead/misleading concurrency code.** `Task.isCancelled` is checked from plain
  GCD threads where it is always false (`BridgeInvocationContext.swift:105`,
  `BridgeRuntime.swift:517`); `JavaScriptExecutionCall` has no deinit
  cancellation, so a dropped call runs to completion in the background
  (`BridgeModels.swift:298-352`), and `waitForResultOutcome` spawns a
  `Task.detached` per `result` access. Deadlines use `Date()` rather than
  `ContinuousClock`, so an NTP jump moves the watchdog deadline.
- **Error-severity diagnostics never reach the event stream.**
  `ExecutionSupport.swift:43-45`: `if diagnostic.severity != .error { emitEvent(...) }`.
- **Un-validated `path` forwarded to host clients.**
  `BigTicketAppleBridges.swift:113-117, 350-354` add `resolvedPath` but leave the
  raw attacker-controlled `path` in the dictionary, with no in-code contract about
  which to use — every host adapter is one `arguments.string("path")` away from a
  path-policy bypass.
- **`fs.read`'s `encoding` advertises no constraint.** It accepts only
  `utf8|utf-8|base64` (`FileSystemBridge.swift:41-54`) but golden
  `allowedStringValues` is `{}` — the constraint lives only in prose, unlike
  `CodeModeStringEnum`-typed arguments.
- **`inferArgumentTypes` is a ~170-entry global name→type table**
  (`CapabilityRegistry.swift:178-353`) shared across all capabilities, so a name
  collision ("type", "action", "limit") silently mistypes an unrelated tool's
  argument. **[tracked]**
- **`CodeModeConfiguration` is a 20-slot mega-init** with 13 `any *Client`
  existentials (`BridgeModels.swift:3-68`), mirrored again in
  `DefaultCapabilityLoader`. Every new Apple family widens it; a `services:`
  sub-struct would stop the source-compat churn. **[tracked]**
- **`executeJavaScript` is `async throws` over a synchronous non-throwing body**
  (`CodeModeAgentTools.swift:48-50`) — defensible as future-proofing, but
  undocumented. There is also no way to enumerate capabilities from Swift
  (`allReferences()` exists but isn't exposed), which hosts need for consent UI.

## Tests, CI, and evals

Coverage is strong where it can be: 29 runtime tests (timeout, cancellation,
error classification, streaming, fresh-context-after-timeout), unusually thorough
network policy tests (encoded IP literals, NAT64, IPv4-mapped, trailing-dot,
`example.com.evil.net`), path policy escapes, a 121-capability golden metadata
baseline, and macro expansion tests.

The structural gap: **system-framework bridges have no seam.** FileSystem injects
`CodeModeFileSystem` and the big-ticket bridges inject client protocols, but
EventKit/Health/Photos/Home/Contacts hard-instantiate `EKEventStore()`,
`HKHealthStore()`, `PHAsset`. Their tests therefore cover only permission denial
and argument validation — create/update/filter/serialization logic, including
findings 8 and the EventKit crashes above, executes nowhere: not in unit tests,
not in CI, not in evals. Adding store protocols mirroring the existing
`CodeModeFileSystem` pattern is the highest-value test work available.

Also missing: any concurrent-execution test of `executeJavaScript` (despite the
concurrent queue being a core design point — such a test would surface the
native-call overrun in #9), and coverage of `FetchTaskHandler`'s redirect
re-validation and size-cap cancellation paths.

CI is honest about its limits: `swift test` runs on `macos-latest` only, with
iOS/visionOS build-only jobs, so UIKit presenters, AlarmKit, and every TCC-gated
happy path are compiled but never executed anywhere. `macos-latest` isn't pinned,
so the macOS 15 floor can drift silently. The LLM job is correctly gated behind a
missing secret, which does mean the "live regression gate" has never run in this
repo and the `catalog` suite has no committed baseline. **[tracked]**

One eval-harness bug: `EvalRunner.swift:61-81` overwrites
`executionOutput/Logs/Diagnostics/observedError` per step in multi-step scenarios
and doesn't stop on an intermediate error, so validation (`:285-319`) sees only
the last step — a scenario can pass while step 1 failed in a way step 2 masks.
Separately, the deterministic suite's tool-order check is tautological offline
(the runner constructs the calls from the scenario), so it only has teeth against
LLM transcripts.

## Suggested sequencing

1. **Ship P0 first** — items 1-8 are small, independent diffs. Add the regression
   tests that are missing for each (`fs.move` to a root, `1e300` timeouts,
   `allowedCapabilityKeys` aliasing), then tag `0.1.0`.
2. **Drop the consumer swift-syntax dependency (#12)** — mechanical, and it
   unblocks adoption while the bigger work proceeds.
3. **Async bridge + event loop (#9)** as one milestone, with bounded execution
   slots and honest `setTimeout`. This is the change that decides whether the
   answer to "is this the best way" is yes.
4. **Generate `.d.ts` (#10) and generate the JS bindings (#11)** together — they
   share the same metadata plumbing and eliminate the drift class entirely.
5. **Provider ergonomics + MCP adapter (#13)** once handlers are async and the
   catalog is no longer frozen at init.
6. **Bridge store seams**, then a simulator test job, so the untested bridge logic
   stops being untestable.
