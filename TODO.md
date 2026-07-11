# CodeMode.swift — Working TODO

Branch: `fixes-and-improvements` (pushed on top of `main`).
Scratch tracking for the follow-up work surfaced by the repo evaluation; kept on
the branch so the remaining items travel with it.

Everything from that evaluation is represented below, with honest status.

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
executing. The full "make the runtime resource-bounded" milestone is bigger than
just the watchdog:
- [x] Preemptive watchdog via `JSContextGroupSetExecutionTimeLimit` (through the
  `CCodeModeJSC` shim) → real `timeoutMs`, `while(true){}` terminates.
  - [x] **macOS verification found the Linux-authored version completely broken:**
    on current OS releases (observed macOS 26.5) JSC does *not* re-arm the time
    limit when the callback returns false — the callback fires exactly once at
    50ms and the watchdog is dead for the rest of the execution, so nothing was
    ever terminated (first full `swift test` hung indefinitely with six runaway
    JS threads). Root-caused with a minimal C reproduction; fixed by having the
    callback re-install the time limit itself before returning false
    (`codeModeWatchdogShouldTerminate` in `ExecutionWatchdog.swift`).
- [x] Real cancellation — `cancel()` interrupts in-flight JS.
- [x] Tests for the above (`ExecutionWatchdogTests.swift`) — all 8 pass on
  macOS after the re-arm fix (loop, promise-chain loop, runaway getter during
  serialization, cancellation, catch-proof termination, context recovery).
- [ ] **JS heap / memory cap** — nothing bounds `JSContext`/`JSContextGroup`
  heap; `new Array(1e9)` can still exhaust host memory. NOT addressed.
- [ ] **Bound on concurrent executions** — `executionQueue` is `.concurrent`
  with spin-waiting workers (`BridgeRuntime.swift:25-29`), so N long-running
  scripts occupy N threads. No concurrency cap. NOT addressed.
- [ ] `runOnExecutionQueue` still has no task-cancellation handler wired into the
  dispatched block (best-effort only). NOT addressed.

### 2. `fetch` has no destination restrictions or size limits  [x]
- [x] `NetworkAccessPolicy` on `CodeModeConfiguration`: by default requests are
  limited to public hosts — private / loopback / link-local / local-network
  addresses (including alternate numeric and IPv6-embedded spellings) and
  `localhost`/`.local`/`.internal`/trailing-dot names are declined.
- [x] Redirect targets re-checked against the policy before being followed.
- [x] Response-size cap (default 10 MB), enforced by Content-Length pre-check +
  streaming cancel.
- [x] Allow/deny host lists; `.permissive` opt-out for hosts that want the old
  unrestricted behavior.
- [x] Request destinations (allowed + declined) now recorded in the audit log,
  not just the execution transcript.
- [x] Tests (`NetworkAccessPolicyTests.swift`) — pass on macOS (2026-07-11).

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
- [x] **Serialization hang** (self-review): a runaway getter/`toJSON` could
  occupy the thread because the watchdog was uninstalled before decode. Fixed via
  rearm.
- [x] **HealthKit always denied through the default broker.** Investigated on
  macOS (2026-07-11): the claimed mechanism does not exist in current code — no
  built-in registration declares `.healthKit` in `requiredPermissions`, so the
  registry's requested→notDetermined→denied path never fires for health.
  `HealthBridge` treats `.notDetermined` as passable and performs real per-type
  `requestAuthorization` itself. Added a registry test pinning the invariant
  (no registration may gate on `.healthKit`, since the default broker can never
  report `.granted` for it).
- [x] **Calendar-span validation drift.** Fixed: constraint validation is now
  case-insensitive (matching the `lowercased()` idiom used by effectively every
  bridge), and the `calendarDelete` span list includes the alias spellings
  `EventKitBridge` accepts. Also removed the now-redundant lowercase
  `videoQuality` duplicates. Tests added.
- [x] **`DispatchQueue.main.sync` in `requestLocationPermission`.** Fixed:
  `main.async` + the existing 10s delegate wait. (The deadlock was background
  execution thread → `main.sync` while the host blocks main waiting on the JS
  result; the `Thread.isMainThread` branch already covered the direct case.)
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
- [ ] Unify permission ownership — `calendarRead` checks in both registry and
  bridge; `calendarWrite` checks only in the bridge.
- [/] Decide the fate of `Tools/CodeModeAuthoring` — investigated 2026-07-11;
  concrete three-phase plan written up in `PLAN-registration-macros.md`
  (typed-tool protocol first, then promote the macro into the core package —
  swift-syntax cost measured at 24s clean/~0 incremental with prebuilts
  default-on — then per-domain migration). Awaiting owner decision on
  swift-syntax in the core graph; Phase 1 is worthwhile standalone.

---

## TESTING, CI, AND EVALS

- [/] **Core policy layer has zero dedicated tests.**
  - [x] `PathPolicy` (`PathPolicyTests.swift`): empty/whitespace, scoped roots,
    appGroup configured/unconfigured, absolute in/out, `..` escapes vs internal
    `..`, nonexistent nested paths, symlink escape vs symlink between roots.
  - [x] `ArtifactStore` + `AuditLogger` (`CorePolicySupportTests.swift`).
  - [ ] `SystemPermissionBroker` — not unit-testable as written: every path
    terminates in a real OS framework call (CLLocationManager, EKEventStore,
    CNContactStore…), so tests would prompt/flake. Needs seams (injectable
    status providers) first; fold into the metadata/permission refactor.
- [/] **CI never compiles iOS/visionOS code.**
  - [x] Added a `platform-build` matrix job (`xcodebuild build` for iOS +
    visionOS) so the UIKit presenters and the `CCodeModeJSC` shim compile
    against those SDKs on every PR/push.
  - [x] Added SwiftPM build caching and `xcodebuild -version` toolchain logging
    to the deterministic job.
  - [x] macOS `swift test` job already existed and links the new C shim +
    watchdog on macOS — this is what verifies the private-symbol link.
  - [ ] Still missing: lint/format config + check, explicit Xcode/SDK pinning
    (currently uses runner default), artifact upload of eval reports.
  - Note: the iOS/visionOS build verifies *compilation*; the private JSC symbol's
    dynamic-link resolution is exercised by the macOS `swift test` link. Full
    iOS link verification would need a test bundle / host app.
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
  digests, outcomes, path/destination targets, and a per-execution correlation
  ID. (Partial down payment already made: fetch destinations now recorded.)
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
- [ ] Apply the network destination policy to `apple.web.present` /
  `apple.auth.webAuthenticate` (these open a visible browser view; the policy
  currently covers `network.fetch`).
- [ ] Data-driven address-range list in `NetworkAccessPolicy` (ranges are
  hardcoded today).
- [ ] Reconcile network audit entries with the runtime's generic success/failure
  audit (two entries per fetch — kept intentionally for destination detail).
- [ ] Migrate bespoke `NSLock` state (`ExecutionWatchdog`, `FetchTaskHandler`) to
  `LockedBox`/`SynchronizedBox` where compound atomicity isn't needed. Cosmetic.

---

## MUST-DO BEFORE MERGE
- [/] **Verify on macOS** — done 2026-07-11 (macOS 26.5, Swift 6.3.2 / Xcode 26.5):
  - [x] `CCodeModeJSC` shim links and the private symbols resolve at load time
    on macOS. (iOS/visionOS remain compile-verified only, via CI.)
  - [x] `swift test` passes — 206 tests, 0 failures, ~5s. Note: the *first*
    verification run hung indefinitely and exposed the watchdog re-arm bug
    (see CRITICAL ISSUES §1); after the fix the suite is green.
  - [ ] Watchdog terminates `while(true){}` on an iOS device/simulator —
    verified on macOS only; JSC ships per-OS, so worth one manual check on a
    simulator before tagging.

## SUGGESTED ORDER OF ATTACK
1. Quick wins: tag `0.1.0`, fix calendar-span drift, add core-policy-layer tests,
   add lint + iOS build job to CI.
2. Runtime hardening milestone: (watchdog ✔) + JS heap cap + concurrency bound
   → "resource- and network-bounded runtime."
3. Metadata-consolidation refactor + macro decision, protected by new drift tests.

## OPEN QUESTIONS FOR THE USER
- [ ] Decision on the private-but-exported JSC symbol (App Store risk)?
- [ ] After CI is green: tag `0.1.0` and restore the versioned install snippet?
