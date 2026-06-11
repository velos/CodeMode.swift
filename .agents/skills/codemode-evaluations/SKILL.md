---
name: codemode-evaluations
description: Use when adding, updating, or reviewing CodeMode.swift evaluation scenarios, deterministic eval tests, or Wavelike-backed LLM eval coverage in this repository.
metadata:
  short-description: Add CodeMode eval scenarios
---

# CodeMode Evaluations

Use this skill when the user asks to add evaluation coverage for CodeMode.swift tools, bridge behavior, catalog search, tool-call order, capability minimization, validation errors, permission behavior, or LLM agent performance.

## Source of Truth

Start with the local harness:

- `Sources/CodeModeEvaluation/EvalModels.swift`: scenario, seed file, permission, expectation, result models.
- `Sources/CodeModeEvaluation/EvalRunner.swift`: deterministic sandbox runner and transcript validator.
- `Sources/CodeModeEvaluation/EvalScenarios.swift`: built-in scenarios and `CodeModeEvalScenarios.all`.
- `Tests/CodeModeEvalTests/CodeModeEvalRunnerTests.swift`: regression tests for built-in scenarios and validator behavior.
- `Tools/CodeModeEval/Sources/CodeModeEvalCLI`: CLI for deterministic runs, LLM runs, planning, summaries, comparisons, and Markdown reports.

Apple Evaluations framework guidance maps to this repo as:

- Evaluation = one `CodeModeEvalScenario` plus its expectations.
- Dataset = categorized scenario set in `CodeModeEvalScenarios.all` and optional LLM suites.
- Subject = `CodeModeAgentTools` for deterministic runs or the Wavelike-backed agent loop for LLM runs.
- Evaluators = `CodeModeEvalExpectation` fields plus `CodeModeEvalRunner.validateTranscript`.
- Aggregation = test pass rate, CLI summaries, scenario summaries, capability pass rate, retry and turn counts.

Apple's Evaluations framework is useful as design guidance, but do not add `import Evaluations` to the package unless the repository is intentionally moving to a compatible Apple beta toolchain and platform. The current package is SwiftPM-based and already has a portable evaluation harness.

## Eval Design Checklist

Treat evaluations as the living specification for the feature under test:

1. Define the behavior in measurable terms before changing prompts or implementation.
2. Add golden, edge, adversarial, and known-failure cases where relevant.
3. Prefer code-based checks when the result is computable: exact JSON output, error code, diagnostic fragment, tool order, allowed capabilities, forbidden capabilities, and required code fragments.
4. Use LLM repeat runs only for model behavior that cannot be proven deterministically.
5. Keep each scenario narrow enough that a failure points to a specific behavior.
6. Include at least one negative assertion when there is a real risk, such as forbidden capabilities or an expected permission denial.

## Adding a Deterministic Scenario

1. Find nearby examples in `EvalScenarios.swift`.
2. Add a `public static let` scenario with a stable dotted id.
3. Add it to `CodeModeEvalScenarios.all` in the appropriate section.
4. Set `task` as the model-facing instruction for LLM runs. Make it precise enough to evaluate.
5. Use `searchCode` when the scenario expects catalog discovery before execution.
6. Use `executeCode` for one-step workflows or `executeSteps` when order matters across multiple tool calls.
7. Set `allowedCapabilities` to the minimum needed by the execute step.
8. Use `seedFiles`, `permissions`, and `catalogPlatform` instead of ad hoc setup in test code.
9. Fill `CodeModeEvalExpectation` with measurable checks:
   - `toolOrder`
   - `exactAllowedCapabilities`
   - `forbiddenCapabilities`
   - `requiredSearchResultFragments`
   - `requiredExecuteCodeFragments` or `requiredExecuteCodeAlternativeFragments`
   - `expectedOutput`
   - `expectedErrorCode`
   - `requiredErrorSuggestionFragments`
   - diagnostic or log fragments when they are part of the contract

Keep expected JSON stable. If order is not semantically meaningful, assert fragments instead of exact arrays.

## Adding LLM Eval Coverage

Use existing deterministic scenarios as the dataset for LLM runs. When adding a scenario that should be part of standard LLM suites:

1. Inspect `LLMEvalSuite` in `Tools/CodeModeEval/Sources/CodeModeEvalCLI/LLM.swift`.
2. Add the scenario id to `smoke`, `core`, `failures`, or `all` only when it matches that suite's purpose.
3. Run `swift run codemode-eval plan --suite <suite>` from `Tools/CodeModeEval` before live model calls.
4. For live calls, prefer a small repeat count first, then increase only after the scenario is stable.
5. Compare reports with the CLI when evaluating a prompt or model change.

Use these metrics as the main quality signals:

- `passRate`: scenario success.
- `exactCapabilityPassRate`: whether the agent used the exact minimal capability set.
- `averageTurns`: whether the task requires too much back-and-forth.
- `averageRetries`: whether transport or model stability regressed.
- failure categories and captured tool calls for root cause.

## Validation Commands

From the repo root:

```sh
swift test --filter CodeModeEvalTests
```

From `Tools/CodeModeEval`:

```sh
swift run codemode-eval list
swift run codemode-eval run <scenario-id> --show-code
swift run codemode-eval plan --suite smoke
```

Use LLM runs only when credentials and budget are intentionally available:

```sh
swift run codemode-eval llm --suite smoke --repeat 1 --output /tmp/codemode-llm.json
swift run codemode-eval summarize /tmp/codemode-llm.json --include-failures
swift run codemode-eval report /tmp/codemode-llm.json --output /tmp/codemode-llm.md
```

## Review Heuristics

Reject or revise evals that:

- Only assert that a command runs without checking behavior.
- Request broader capabilities than the task requires.
- Depend on wall-clock time, network data, or host state when a seeded fixture can express the behavior.
- Combine unrelated bridge behavior in one scenario.
- Add LLM-only coverage for behavior that the deterministic runner can verify.
- Use polished natural-language expectations where a code-based check would be cheaper and more reproducible.
