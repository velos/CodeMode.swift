# CodeMode Evals

This project has two eval layers:

- Deterministic evals run local scenario code through `searchJavaScriptAPI` and `executeJavaScript`.
- Live LLM evals ask the configured Wavelike model to solve the same tasks, capture real tool calls, and grade the transcript.

## Local Checks

Run deterministic checks before PRs with the single supported eval CLI:

```sh
swift test
swift run --package-path Tools/CodeModeEval codemode-eval run
```

Run a small live smoke pass while iterating on prompts or tool descriptions:

```sh
swift run --package-path Tools/CodeModeEval codemode-eval llm --suite smoke --request-delay-ms 1000
```

Live runs print per-scenario progress to stderr so JSON stdout stays parseable. In an interactive terminal this is an in-place progress bar with colored pass/fail states; in CI it falls back to one line per scenario. Use `--quiet` to suppress progress output.

Preview a live run before spending provider calls:

```sh
swift run --package-path Tools/CodeModeEval codemode-eval plan --suite core --repeat 5 --request-delay-ms 1000
```

Run the repeat baseline suites when model behavior needs a real stability signal:

```sh
swift run --package-path Tools/CodeModeEval codemode-eval llm --suite core --repeat 5 --request-delay-ms 1000 --output Tools/CodeModeEval/.build/reports/core-r5.json
swift run --package-path Tools/CodeModeEval codemode-eval llm --suite failures --repeat 5 --request-delay-ms 1000 --output Tools/CodeModeEval/.build/reports/failures-r5.json
```

Live evals read `WAVELIKE_MODEL_ID`, `WAVELIKE_APP_ID`, `WAVELIKE_API_KEY`, and optional `WAVELIKE_ENV` from the environment or `.env`.

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

The GitHub Actions workflow runs deterministic evals on PRs and pushes. Live LLM evals run only on schedule or manual dispatch because they require secrets and provider calls.

Scheduled/manual live evals:

- Run `core` and `failures` with repeat count 5 by default.
- Save raw JSON, summary JSON, and Markdown diagnostics reports as workflow artifacts.
- Compare repeat-5 reports against committed summary baselines.
- Use request pacing and transient model retry/backoff to tolerate provider rate limits.

## Updating Baselines

Update baselines only when a meaningful change intentionally improves or changes model/tool behavior. Do not commit raw live reports from `.build/reports`; regenerate summary-only baselines from reviewed live results.
