---
name: codemode-synthetic-eval-datasets
description: Use when designing, generating, validating, or importing synthetic evaluation datasets for CodeMode.swift eval scenarios.
metadata:
  short-description: Build CodeMode synthetic eval data
---

# CodeMode Synthetic Eval Datasets

Use this skill when the user asks to generate, expand, validate, rebalance, or import synthetic evaluation data for CodeMode.swift.

The output should usually become typed Swift scenarios in `Sources/CodeModeEvaluation/EvalScenarios.swift`, plus tests in `Tests/CodeModeEvalTests`, not an unreviewed blob of generated data.

## Apple-Informed Principles

Follow these dataset design rules:

- Start with high-quality human-written seeds. Synthetic data amplifies seed quality and seed gaps.
- Categorize samples by purpose: golden, edge, adversarial, known failures, permission failures, platform-gated catalog discovery, and capability-minimization checks.
- Generate within focused categories instead of asking for one broad "diverse" set.
- Include hard and adversarial seeds. Aim for at least 20 to 30 percent difficult human-authored anchors when building a synthetic set.
- Keep at least 20 to 30 percent human-written samples in any expanded dataset as calibration anchors.
- Validate generated samples programmatically, then manually review a random slice before relying on them.
- Prefer 50 to 200 strong samples per feature or category over thousands of noisy, duplicate, or ambiguous cases.

## CodeMode Dataset Shape

Represent synthetic output in CodeMode terms:

- `id`: stable dotted id, grouped by domain, for example `fs.synthetic.long-path-read`.
- `title`: short human-readable title.
- `task`: model-facing instruction that can be evaluated.
- `searchCode`: catalog lookup the agent should perform, if discovery is part of the behavior.
- `executeCode` or `executeSteps`: expected tool-side behavior for deterministic replay.
- `allowedCapabilities`: exact minimum capability set.
- `seedFiles`: deterministic fixtures under `tmp:`, `documents:`, or `caches:`.
- `permissions`: explicit permission status and request behavior.
- `catalogPlatform`: platform override when testing platform-specific availability.
- `expectation`: measurable checks on tool order, capabilities, output, errors, diagnostics, and code fragments.

Do not import generated examples directly if expected outputs are ambiguous. Turn them into deterministic scenarios with explicit expected JSON or explicit failure expectations.

## Generation Workflow

1. Identify the feature and quality dimensions:
   - correctness
   - capability minimization
   - tool-call order
   - argument validation
   - permission behavior
   - platform pruning
   - diagnostic quality
   - recovery after invalid arguments
2. Write 5 to 15 seed scenarios by hand.
3. Label each seed with category, difficulty, feature area, required capabilities, and the expected failure mode if any.
4. Generate more cases one category at a time:
   - golden filesystem reads
   - adversarial path policy escapes
   - catalog alias lookups
   - permission denied flows
   - invalid argument repair cases
   - platform-pruned iOS-only or macOS-only helpers
5. Validate generated candidates:
   - unique id
   - unique or intentionally varied task
   - exact minimal capability list
   - no impossible host state
   - all seeded paths stay inside allowed roots
   - expected output is derivable from seeded data
   - no leaking the expected answer in a way that invalidates the task
6. Promote accepted samples into `CodeModeEvalScenario` declarations.
7. Add them to `CodeModeEvalScenarios.all` or to a new grouped collection if the set is large.
8. Run deterministic tests before any LLM run.

## Candidate Review Checklist

For each generated candidate, answer:

- What exact behavior does this sample measure?
- Which category does it belong to?
- Is the expected result deterministic?
- Could a model pass by using a broader capability than necessary?
- Does `requiredExecuteCodeAlternativeFragments` allow legitimate API aliases without allowing unrelated implementations?
- Is this a near-duplicate of an existing scenario?
- Would failure produce a useful, localized signal?

Discard or rewrite candidates that fail these checks.

## Prompt Pattern for Synthetic Candidates

When asking a model to draft candidates, keep the prompt constrained:

```text
Generate CodeMode evaluation scenario candidates for <feature area>.
Category: <golden|edge|adversarial|known-failure|permission|platform>.
Each candidate must include: id, title, task, seedFiles, allowedCapabilities,
expectedOutput or expectedErrorCode, and rationale.
Do not include cases that require live network, clock time, user contacts,
real calendars, Photos library contents, or host filesystem state.
Vary phrasing, input length, and difficulty. Keep expected outputs deterministic.
```

Then convert accepted candidates to Swift manually or with a small script, preserving the local formatting style.

## Validation Commands

From the repo root:

```sh
swift test --filter CodeModeEvalTests
```

From `Tools/CodeModeEval`:

```sh
swift run codemode-eval run <scenario-id> --show-code
swift run codemode-eval plan --suite core
```

For LLM-backed validation after deterministic checks pass:

```sh
swift run codemode-eval llm <scenario-id> --repeat 3 --output /tmp/codemode-synthetic-smoke.json
swift run codemode-eval report /tmp/codemode-synthetic-smoke.json --all-runs --include-code
```

## When to Use Apple's Evaluations Framework Directly

Only add a direct `Evaluations` framework target when the user explicitly wants Apple's framework adoption and the local toolchain supports it. In that case:

- Model each CodeMode scenario as a `ModelSample` with explicit expected values.
- Put the CodeMode tool or agent under test in the `subject(from:)` implementation.
- Use code-based `Evaluator` checks for deterministic behavior.
- Use tool-call trajectory expectations for tool order and arguments.
- Aggregate pass/fail metrics with means and scored metrics with medians or maxima, depending on what the metric represents.
- Keep the existing CodeMode harness running until the new framework produces equivalent or better regression signal.
