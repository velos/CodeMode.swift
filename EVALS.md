# CodeMode Evals

This project has two eval layers:

- Deterministic evals run local scenario code through `searchJavaScriptAPI` and `executeJavaScript`.
- Saved live LLM reports capture real model tool calls for the same tasks and can be summarized, reported, and compared by the eval CLI.

## Local Checks

Run deterministic checks before PRs with the single supported eval CLI:

```sh
swift test
swift run --package-path Tools/CodeModeEval codemode-eval run
```

Preview a live run before spending provider calls:

```sh
swift run --package-path Tools/CodeModeEval codemode-eval plan --suite core --repeat 5 --request-delay-ms 1000
```

The default eval package intentionally excludes the private Wavelike-backed live runner so `swift build --package-path Tools/CodeModeEval` works in unauthenticated CI. Keep live model execution in a separate private runner or workflow when it is needed; this package keeps the deterministic runner plus `plan`, `summarize`, `report`, and `compare`.

## Baselines

Committed baselines live in `Tools/CodeModeEval/Baselines` and are summary-only reports. They intentionally keep aggregate pass rates, turn counts, retry counts, exact-capability rates, and per-scenario summaries while omitting raw model transcripts.

Compare a candidate report against a baseline:

```sh
swift run --package-path Tools/CodeModeEval codemode-eval compare \
  Tools/CodeModeEval/Baselines/core-r5-summary.json \
  Tools/CodeModeEval/.build/reports/core-r5.json \
  --retry-tolerance 0.5 \
  --turn-tolerance 0.5
```

Default comparison policy allows no pass-rate regression and no exact-capability regression. Retry and turn tolerances should stay small because increases there usually mean the model is recovering from avoidable tool or JavaScript mistakes.
When a suite adds or removes scenarios, `compare` still checks overlapping per-scenario metrics but treats overall aggregate metrics as informational until a new baseline is reviewed and committed.
The `catalog` suite covers search-only catalog scenarios. Its scheduled compare is enabled automatically once `Tools/CodeModeEval/Baselines/catalog-r5-summary.json` has been generated from a reviewed live r5 run and committed.

Create a human-readable Markdown diagnostics report:

```sh
swift run --package-path Tools/CodeModeEval codemode-eval report \
  Tools/CodeModeEval/.build/reports/core-r5.json \
  --baseline Tools/CodeModeEval/Baselines/core-r5-summary.json \
  --output Tools/CodeModeEval/.build/reports/core-r5.md
```

Reports include overall metrics, optional baseline comparison, scenario summaries sorted by weakest signal, failure categories, retry diagnostics, captured tool order, and `allowedCapabilities`. Retry diagnostics show each captured tool attempt's status, structured error code, function name, diagnostics, suggestions, and whether the next same-tool attempt repaired the failure. Add `--include-code` to include generated JavaScript for highlighted runs, `--include-assistant` to include passing final assistant messages, or `--all-runs` to include every raw run.

Create a summary-only report from a raw live report:

```sh
swift run --package-path Tools/CodeModeEval codemode-eval summarize \
  Tools/CodeModeEval/.build/reports/core-r5.json \
  --output Tools/CodeModeEval/Baselines/core-r5-summary.json
```

## CI Policy

The GitHub Actions workflow runs the deterministic evals and the iOS/visionOS
platform builds continuously — on every pull request and on pushes to `main`
(merges). There is no schedule; a daily cron over unchanged `main` added no
signal for these offline checks.

The live LLM regression gate (`llm-live` job) is **manual only**
(`workflow_dispatch`) because it spends real provider calls:

- It always previews `core`, `failures`, and `catalog` budgets (honoring the
  manual `repeat_count` / `request_delay_ms` inputs).
- If a `WAVELIKE_API_KEY` secret is configured **and** the CLI is built with the
  private overlay (the real `codemode-eval llm` command rather than the
  `LLMUnavailable` stub), it then runs the `core` and `failures` suites live and
  `compare`s each against its committed baseline, failing the job on any
  pass-rate or exact-capability regression. `catalog` is previewed but not
  compared until its baseline is generated and committed.
- Without those, the live+compare steps skip with a warning, so the manual run
  still succeeds and only reports the budget preview.

## Updating Baselines

Update baselines only when a meaningful change intentionally improves or changes model/tool behavior. Do not commit raw live reports from `.build/reports`; regenerate summary-only baselines from reviewed live results.
