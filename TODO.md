# CodeMode.swift — Working TODO

Branch: `fixes-and-improvements` (pushed, 5 commits on top of `main`).
This file is intentionally **not committed** — scratch tracking only.

Derived from the full repo evaluation. Everything from that evaluation is
represented below, with honest status.

## Status legend
- [x] done and pushed
- [~] done but unverified (no Swift toolchain / JavaScriptCore in this Linux env)
- [/] partially done — see sub-items
- [ ] not started

---

## CRITICAL ISSUES

### 1. Timeouts don't actually interrupt running JavaScript  [/]
Root cause: synchronous bridge model settles the whole promise graph inside one
`evaluateScript` call, so the old wall-clock poll loop never ran while JS was
executing. The full "make the runtime resource-safe" milestone is bigger than
just the watchdog:
- [x] Preemptive watchdog via `JSContextGroupSetExecutionTimeLimit` (through the
  `CCodeModeJSC` shim) → real `timeoutMs`, `while(true){}` terminates.
- [x] Real cancellation — `cancel()` interrupts in-flight JS.
- [~] Tests for the above (`ExecutionWatchdogTests.swift`) — unverified.
- [ ] **JS heap / memory cap** — nothing bounds `JSContext`/`JSContextGroup`
  heap; `new Array(1e9)` can still OOM the host. NOT addressed.
- [ ] **Bound on concurrent executions** — `executionQueue` is `.concurrent`
  with spin-waiting workers (`BridgeRuntime.swift:25-29`), so N hung/slow
  scripts pin N threads. No concurrency cap. NOT addressed.
- [ ] `runOnExecutionQueue` still has no task-cancellation handler wired into the
  dispatched block (best-effort only). NOT addressed.

### 2. `fetch` has no egress policy (SSRF)  [x]
- [x] `NetworkAccessPolicy` on `CodeModeConfiguration`: default blocks
  loopback/RFC-1918/link-local/CGNAT/metadata (incl. encoded IPv4 literals and
  IPv4-in-IPv6 / NAT64 forms), `localhost`/`.local`/`.internal`, trailing-dot
  FQDNs.
- [x] Redirect targets re-validated before being followed.
- [x] Response-size cap (default 10 MB), enforced by Content-Length pre-check +
  streaming cancel.
- [x] Allow/deny host lists; `.permissive` opt-out.
- [x] Egress destinations (allowed + denied) now written to the audit logger,
  not just the execution transcript.
- [~] Tests (`NetworkAccessPolicyTests.swift`) — unverified.

### 3. Package not installable as documented  [/]
- [x] README no longer tells users to depend on `from: "0.1.0"` against a
  tagless repo; documents branch-based install for now.
- [ ] **Tag `0.1.0`** (the actual fix) once CI is green, then restore the
  versioned SPM install snippet. NOT done.

---

## OTHER REAL BUGS FOUND IN EVALUATION

- [x] **Watchdog compile blocker** (found in self-review):
  `JSContextGroupSetExecutionTimeLimit`/`...Clear...` are private-header JSC
  symbols; added `CCodeModeJSC` C shim so it builds against the public SDK.
  - [ ] Owner decision still needed: private-but-exported symbol → App Store
    review risk. Keep+document (current) vs gate vs accept.
- [x] **Spurious timeout** (self-review): poll loop discarded an already-settled
  result at/just past deadline. Fixed via shared `waitForSettlement`.
- [x] **Serialization hang** (self-review): runaway getter/`toJSON` hung the
  thread because the watchdog was uninstalled before decode. Fixed via rearm.
- [ ] **HealthKit always denied through the default broker.**
  `healthKitStatus()` unconditionally returns `.notDetermined`
  (`SystemPermissionBroker.swift:398-407`); registry treats
  requested→notDetermined as denial. Fails closed silently. NOT addressed.
- [ ] **Calendar-span validation drift.** Registry constraint table accepts only
  `["thisEvent","futureEvents"]` case-sensitively
  (`CapabilityRegistry.swift:56-58`) while `EventKitBridge` accepts
  `this_event`/`future`/etc. case-insensitively
  (`EventKitBridge.swift:471-479`) — registry rejects inputs the bridge
  supports. NOT addressed. (Quick win.)
- [ ] **`DispatchQueue.main.sync` in `requestLocationPermission`**
  (`SystemPermissionBroker.swift:430`) deadlocks if reached from the main
  thread. NOT addressed.
- [ ] **Duplicated eval model types will drift.** `LLM.swift` is excluded from
  the build; ~250 lines of report/suite types are defined twice (there and in
  compiled `LLMEvalModels.swift`) with nothing keeping them in sync. NOT
  addressed.

---

## STRUCTURAL IMPROVEMENTS (bridge/registry metadata drift)

Biggest maintenance risk: ~115 capabilities / ~2,540 lines of hand-written
registrations with four parallel sources of truth. None addressed yet.
- [ ] Move argument types/constraints to per-capability, co-located declarations;
  **fail loudly instead of degrading unknown args to `.any`**
  (`CapabilityRegistry.swift:223-398`).
- [ ] Add a test asserting registration metadata matches bridge reality
  (allowed-string sets vs what bridges accept; golden-test `resultSummary`
  against bridge JSON encoders) — would have caught the calendar-span drift.
- [ ] Standardize on one registration idiom (three coexist across
  `CapabilityRegistrations+*.swift`).
- [ ] Unify permission ownership — `calendarRead` gates in both registry and
  bridge; `calendarWrite` gates only in the bridge.
- [ ] Decide the fate of `Tools/CodeModeAuthoring` (macro package fully built,
  tested, but unwired; `SimpleBuiltInCodeModeProviders.swift` hand-rolls the
  same pattern). Either extend it to back the built-ins (permissions,
  constraints, multi-name aliases, curated tags/examples) or scope it clearly as
  a host-authoring aid. Lower-risk near-term win: validation/codegen from
  existing descriptor metadata rather than a 115-callsite macro migration.

---

## TESTING, CI, AND EVALS

- [ ] **Security layer has zero dedicated tests.** Add direct unit tests for
  `PathPolicy` (traversal/symlink-escape), `SystemPermissionBroker`
  (permission-denial), `ArtifactStore`, `AuditLogger`. (Quick win, protects the
  trust boundary.)
- [ ] **CI never compiles iOS/visionOS code.** Single workflow runs `swift test`
  on macOS only; all five `UIKitSystemUIPresenter*.swift` never build in CI. Add
  an `xcodebuild -destination` matrix. Also missing: lint/format config + check,
  build/dependency caching, Xcode/toolchain pinning, artifact upload of eval
  reports.
  - [ ] Add the macOS `swift test` CI job specifically — it's what would have
    caught the watchdog compile blocker automatically.
- [ ] **Eval coverage gaps.** `health.*`, `vision.*`, `photos.read/export`,
  `reminders.write` have zero scenarios among the 49, though the LLM prompt
  advertises photos/health/home/alarms. Add catalog + execution/validation
  scenarios for each.
- [ ] **Regression gate is inert in automation.** `compare` is never invoked in
  CI; the `catalog` baseline EVALS.md references doesn't exist. Generate/commit
  it and wire `compare` into a (gated) CI job.
- [ ] **No cost/token tracking in LLM eval reports** — "budget" is a request
  count only; capture input/output tokens (+ derived cost) per run so model
  comparisons can weigh accuracy against price.

---

## PLACES TO GO NEXT (bigger bets)

- [ ] **Async bridge model.** Resolve JS promises from Swift callbacks instead of
  synchronous native returns, so long native ops (30s network, 15s permission
  prompts) don't block inside `evaluateScript`. Prerequisite for fully real
  mid-script cancellation; pairs with the watchdog as the "production-grade
  runtime" milestone.
- [ ] **Structured audit pipeline.** Today's events are capability + free-text
  "success" with a pull-based drain. Move to a push-based sink with argument
  digests, decisions, path/egress targets, and a per-execution correlation ID.
  (Partial down payment already made: fetch egress destinations now audited.)
- [ ] **`Examples/` host app.** Minimal SwiftUI demo wiring `CodeModeAgentTools`
  + a real `UIKitSystemUIPresenter` + an LLM loop — concrete integration story
  and a manual test bed for the UIKit presenters automation can't reach.
- [ ] **DocC + doc comments.** Zero `///` comments in `Sources/` today. Start
  with the public surface: `CodeModeAgentTools`, `CodeModeConfiguration`,
  `SystemUIPresenter`, `CodeModeToolError`, `CapabilityID`.
- [ ] **API polish for integrators.** Group the 19-parameter
  `CodeModeConfiguration` init's service clients; clarify/merge
  `allowedCapabilities` vs `allowedCapabilityKeys`; emit the valid `CapabilityID`
  list as an enum in the `executeJavaScript` JSON schema so agents get
  machine-checkable capability names.

---

## MISC DEFERRED / NOTED (not bugs)
- [ ] Apply egress policy to `apple.web.present` / `apple.auth.webAuthenticate`
  (visible browser flows, not silent egress; README scopes the policy claim to
  `network.fetch` for now).
- [ ] Data-driven CIDR blocklist in `NetworkAccessPolicy` (hardcoded ranges today).
- [ ] Reconcile network audit entries with the runtime's generic success/failure
  audit (two entries per fetch — kept intentionally for destination detail).
- [ ] Migrate bespoke `NSLock` state (`ExecutionWatchdog`, `FetchTaskHandler`) to
  `LockedBox`/`SynchronizedBox` where compound atomicity isn't needed. Cosmetic.

---

## MUST-DO BEFORE MERGE
- [ ] **Verify on macOS** (nothing was compiled or run in this Linux env):
  - [ ] `CCodeModeJSC` shim links against JavaScriptCore and the private symbol
    resolves at load time on iOS/macOS/visionOS.
  - [ ] `swift test` passes (all new + existing tests).
  - [ ] Watchdog actually terminates `while(true){}` on device/simulator.

## SUGGESTED ORDER OF ATTACK
1. Quick wins: tag `0.1.0`, fix calendar-span drift, add Security-layer tests,
   add lint + iOS build job to CI.
2. Runtime hardening milestone: (watchdog ✔) + JS heap cap + concurrency bound
   → "resource- and egress-safe sandbox."
3. Metadata-consolidation refactor + macro decision, protected by new drift tests.

## OPEN QUESTIONS FOR THE USER
- [ ] Open a PR for `fixes-and-improvements`?
- [ ] Add the macOS CI job next?
- [ ] Decision on the private-but-exported JSC symbol (App Store risk)?
