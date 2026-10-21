# Plan: asynchronous native calls

Status: decided, not started. Starts after `typed-bridges` merges, on its own branch.

## Problem

JS helpers already return promises. `__invokeAsync` (RuntimeJavaScript.swift) is
`Promise.resolve().then(syncInvoke)`. Inside that `.then`, though, the native call blocks the
execution thread until the Swift handler returns. Built-in tools that wrap async Apple APIs each
hand-roll a semaphore, a `Task`, a result box and a fixed timeout. There are about 15 of these
(WeatherBridge.swift is typical), plus `CompletionWait` in EventKit and the permission broker.
Host `@CodeMode` providers go through `CodeModeAsyncBridge.run`, which applies a fixed 30 s
timeout. The consequences:

- Native waits ignore the execution's own deadline: timeouts range from 10 to 30 s, per bridge.
- `cancel()` cannot interrupt a native wait.
- `Promise.all` over several helpers runs them one after another.

## Decision

Go truly asynchronous, not "async handlers behind one synchronous wait point". Helpers already
return promises, so this changes timing, not the surface scripts see. The synchronous-wait
design is not a stepping stone. Its wait point, and its assumption that no native work survives
a JS turn, would both be thrown away; only the async handler signature carries over, and the
first phase below delivers that anyway.

The first phase ships the asynchronous machinery with a concurrency width of 1. Delivery stays
sequential, and nothing observable changes except deadlines and cancellation. Turning on overlap
is a separate, deliberate change.

Reviewed by GPT-6 Astra (read-only) and decided by Fable. The two disagreed on these points, and
here is what was settled:

- **Outstanding native calls at settlement are drained, not cancelled.** The drain is bounded by
  the remaining deadline and emits a diagnostic. Today an un-awaited
  `apple.notifications.schedule(...)` still runs. Cancelling it would turn the most common
  model mistake, a forgotten `await`, into silent data loss. Cancel only on timeout or host
  cancel.
- **One built-in seam.** Built-in tools all go through `CapabilityRegistration.init(tool:)`, so
  a single blocking-work adapter there covers every unmigrated tool. Only the public
  `CapabilityHandler` needs both a sync and an async initializer.
- **Permission prompts are serialized per execution and per permission** with a lock in
  `BridgeInvocationContext`. There are no shared in-flight futures; the broker's own request
  already blocks.

## Phases

**1. Runtime-owned native waits (sequential delivery).**

What becomes true: every native operation is bounded by
`min(execution deadline, per-operation cap)`. `cancel()` interrupts a native wait immediately.
Late completions are dropped. `Promise.all` ordering is unchanged.

- `BridgeInvocationContext` carries an immutable deadline taken from the injected clock, the
  remaining budget, and task registration so that cancel reaches registered work.
- `CapabilityHandler` gets an async form. Sync handlers and unmigrated tool bodies run on a
  bounded GCD queue, bridged by a continuation. They never block inside a `Task` on the
  cooperative pool, which can deadlock it.
- `BuiltInCodeModeTool.call` becomes `async throws`. The protocol is internal, so this is not a
  host-facing break. The `@CodeMode` macro awaits `call` directly, and `CodeModeAsyncBridge.run`
  is deprecated.
- In JS, `__bridgeStart(id, …)` returns immediately and keeps a pending map; delivery resolves
  promises by id.
- In the runtime, an execution mailbox (a locked queue plus the condition `cancel()` already
  broadcasts). `waitForSettlement` drains completions on the execution thread before checking
  timers. It waits until the next completion, timer, deadline or cancel. It reports
  "can never settle" only when no timer and no native call are pending.
- Admission width comes from `ExecutionLimits`, default 1.
- Rewrite the ExecutionWatchdog header comment and the `waitForSettlement` doc, which both state
  that no native work is outstanding.
- Tests use `VirtualClock`: a deadline bounds a slow handler, cancel during a native wait, a late
  completion is dropped, an un-awaited call still completes, `Promise.all` ordering is unchanged.

**2. Overlap.**

- Default width 4 per execution, plus a runtime-wide cap.
- A per-permission lock.
- An exclusive, runtime-wide lane for capabilities that present UI or prompt for permission.
- Size the blocking-work queue to executions × width.
- Update the docs that tell models native calls are sequential: README, `CodeModeAgentGuidance`,
  `CodeModeAgentToolDescriptions`, and their tests.

**3+. One PR per bridge family.**

- Rewrite Weather, Health, Media, Network (async `URLSession`), Notifications, Alarm, Home and
  Photos as native async bodies that honour task cancellation. Delete each family's semaphores
  as it goes.
- Pair each family's rewrite with its typed-arguments migration, since the bodies are being
  rewritten anyway.
- Then add async variants of `PermissionBroker` and `SystemUIPresenter`, with adapters from the
  sync ones.
- Last, the service-client protocols in AppleServiceAdapters.swift.
