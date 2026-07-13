# Phase 3 handoff: migrate remaining registrations to `@BuiltInCodeMode`

Self-contained work spec for converting the remaining hand-written capability
registrations to the macro-authored tool idiom. Context: Phases 1–2 of
`PLAN-registration-macros.md` are done; EventKit is the finished reference.
This is mechanical work — the invariants below matter more than speed.

## The one invariant

**The advertised capability surface must not change except where this spec
says it may.** `Tests/CodeModeTests/CapabilityMetadataGoldenTests.swift` pins
every registration's full metadata (jsNames, title, summary, tags, example,
permissions, argument lists/types/hints, constraints, resultSummary) against
`Tests/CodeModeTests/capability-metadata-golden.json`.

Workflow per domain:
1. Convert the domain (recipe below). Run `swift test`. The golden test fails.
2. Regenerate: `CODEMODE_REGENERATE_GOLDEN=1 swift test --filter capabilityMetadata`
3. `git diff Tests/CodeModeTests/capability-metadata-golden.json` — **this diff
   is the review artifact.** Every hunk must be one of the allowed diffs below;
   anything else is a bug in your conversion. Fix the conversion, not the spec.
4. Full `swift test` green → one commit for the domain, golden diff included,
   and the commit message lists which allowed-diff categories appear.

Allowed golden diffs:
- `argumentHints` gaining entries for arguments that previously had no hint
  (the tool idiom requires a hint per argument — write one consistent with the
  bridge's actual behavior, and call it out in the commit message).
- `allowedStringValues` gaining alias spellings **only when the bridge already
  accepts them** (cite the bridge line in the commit message).
- Nothing else. Not a reworded title, not a reordered jsNames array, not a
  type change, not a constraint that moved keys.

## Reference implementation (read these first)

- `Sources/CodeMode/Bridges/EventKitCodeModeTools.swift` — 9 macro-authored
  tools + 5 `CodeModeStringEnum`s. The pattern to replicate.
- `Sources/CodeMode/Bridges/CapabilityRegistrations+EventKit.swift` — what a
  registration file looks like after conversion (a thin list).
- `Sources/CodeMode/Bridges/BuiltInCodeModeTool.swift`,
  `Sources/CodeMode/Bridges/BuiltInCodeModeMacros.swift`,
  `Sources/CodeMode/API/CodeModeStringEnum.swift` — the infrastructure.
- Commits `6f5e7e8` (Phase 1) and `c45fb10` (Phase 2) show the full shape of a
  domain conversion including bridge rewiring and tests.

## Recipe per registration

1. Create `Sources/CodeMode/Bridges/<Domain>CodeModeTools.swift`. One
   `@BuiltInCodeMode` struct per `CapabilityRegistration` in the old file.
2. Copy **verbatim**: title, summary, tags, example, requiredPermissions,
   resultSummary. Do not improve the prose.
3. `path` = the registration's first jsName; `aliases:` = the rest, in order.
4. `Arguments` struct: one `@ToolParam("<exact existing hint>")` property per
   declared argument, in the old required-then-optional order. Required args
   are non-optional Swift types; optional args are optionals.
5. **Property types must reproduce the old effective type.** If the old
   descriptor declared `argumentTypes`, match it. If it didn't, the effective
   type came from `CapabilityDescriptor.inferArgumentTypes`
   (`CapabilityRegistry.swift`) — look each name up in that table:
   `.string`→`String`, `.number`→`Int` or `Double` (pick what the bridge
   reads), `.bool`→`Bool`, `.array`→`[String]`/`[JSONValue]` (match bridge),
   `.object`→`[String: JSONValue]`, and **names absent from the table were
   `.any` — declare those as `JSONValue`**, never a tighter type. The golden
   test catches mistakes here; trust it.
6. Constrained string arguments — any argument with a row in
   `CapabilityArgumentConstraints.defaults(for:)` (`CapabilityRegistry.swift`):
   - Define a `CodeModeStringEnum` whose **raw values are exactly the current
     advertised list** (case names = raw values). Add `codeModeAliases` only
     for spellings the bridge demonstrably accepts.
   - Use it as the property type; the macro derives the constraint from it.
   - Rewire the bridge's own parsing of that value to
     `EnumType.codeModeValue(matching:)` (see `EventKitBridge.eventSpan`,
     `SystemUIBridge.validateCalendarPickerArguments` for the pattern), so the
     enum is the single source of truth.
   - Delete the row from the `defaults(for:)` table in the same commit.
   - Exception: **dotted-path constraints** (`networkFetch`'s
     `options.responseEncoding`) stay in the central table — the tool argument
     model is flat. Leave them and note it.
7. End every `Arguments` struct with `var raw: [String: JSONValue]` and call
   the same bridge method the old handler called, passing `arguments.raw` and
   the same `context`. Do not change bridge method signatures beyond the
   constrained-value parsing rewiring in step 6.
8. Replace the old file's body with the thin builder-extension list (keep the
   function name the builder calls, e.g. `systemUIRegistrations()` — see
   `DefaultCapabilityLoader.loadAll()` for the roster).

## Domain order and notes

Work sequentially, one commit per domain, full suite green each time:

1. **SystemUI** (`CapabilityRegistrations+SystemUI.swift`, 12 registrations) —
   heaviest constraint user: `photosUIPick`/`contactsUIPick`/`cameraUICapture`/
   `cameraUIScanData` rows in the defaults table, and `SystemUIBridge` has
   matching `lowercased()` validations to rewire (mediaType, cameraDevice,
   flashMode, videoQuality, scan mode, preferredStyle…). Only enum-ify values
   that have a defaults-table row today; leave other `lowercased()` checks
   alone.
2. **Core** (`+Core.swift`, 11) — includes `networkFetch` (dotted-path
   constraint stays in the table) and the filesystem/keychain area. Keychain is
   already converted; don't touch `SimpleBuiltInCodeModeProviders.swift`.
3. **PeoplePhotosDocuments** (`+PeoplePhotosDocuments.swift`, 13) —
   `photosRead` mediaType row; `PhotosBridge` lowercases mediaType, rewire it.
4. **SystemServices** (`+SystemServices.swift`, 19) — health/home/alarm/
   notifications. Do **not** add `.healthKit` to any `requiredPermissions`
   (see `noBuiltInRegistrationGatesOnHealthKitPermission` test). Preserve the
   existing permission declarations exactly.
5. **CloudPushSpeech** (`+CloudPushSpeech.swift`, 15) — the four CloudKit
   capabilities share the `database` row; one enum, four tools.
6. **IntentsModelsActivityMaps** (`+IntentsModelsActivityMaps.swift`, 18) —
   `activityEnd` dismissalPolicy and `mapsRouteEstimate`/`mapsOpen`
   transportType rows. transportType is consumed in
   `SystemAppleServiceClients.swift` (`SystemMapsMapping`) — rewire there.
7. **Commerce** (`+Commerce.swift`, 18) — mostly pass-through to host-supplied
   clients (music/passKit/storeKit). Convert metadata + `musicPlaybackControl`
   action enum (replicate the existing list; host clients stay authoritative
   for semantics). Do not invent constraints for values the table doesn't
   constrain today.

## Hard rules

- Do not touch `Sources/CodeMode/Runtime/RuntimeJavaScript.swift` (the JS
  function table is a separate Phase-3 item, not this task).
- Do not reword any advertised string. Copy-paste, don't retype.
- Do not change permission ownership (some capabilities deliberately declare
  `requiredPermissions: []` and check in the bridge — e.g. calendarWrite).
- Do not migrate `LocationWeather` or `EventKit` (done) and do not modify
  `Tools/CodeModeEval` or CI.
- If a registration doesn't fit the recipe (unexpected handler shape, shared
  state, anything surprising), **stop and leave that registration on the old
  idiom in its file** with a `// PHASE3-SKIP: <reason>` comment rather than
  improvising. Mixed files are fine; wrong conversions are not.
- When all domains are done: delete any now-empty rows from `defaults(for:)`,
  and update `TODO.md`'s structural-improvements section + the status block in
  `PLAN-registration-macros.md`.

## Definition of done (per domain)

- `swift test` fully green (230+ tests).
- Golden diff contains only allowed categories, enumerated in the commit
  message.
- The old registration file is a thin list; its metadata lives on tools.
- Constraint rows for the domain are deleted from the central table (except
  dotted paths) and the owning bridge parses through the shared enum.
