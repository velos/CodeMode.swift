import Foundation

/// System-prompt guidance that teaches an agent *why* it is writing a program
/// rather than calling tools one at a time.
///
/// The tool descriptions and the generated TypeScript answer "what is this helper
/// called and what does it take". Neither answers "what shape should my work
/// take", and an agent that never learns the second question will use
/// `executeJavaScript` as a thin RPC — one call per operation — which is the
/// pattern this package exists to replace.
///
/// Pair it with `CodeModeAgentTools.typeDeclarations()`, which supplies the
/// vocabulary this supplies the strategy for:
///
/// ```swift
/// let prompt = CodeModeAgentGuidance.systemPrompt(.standard)
///     + "\n\n"
///     + tools.typeDeclarations()
/// ```
public enum CodeModeAgentGuidance {
    /// How much prompt budget to spend on the guidance.
    ///
    /// Every tier is self-contained and states the core idea; the larger ones add
    /// worked examples and failure modes rather than qualifying what came before,
    /// so a host can drop down a tier without losing a rule.
    public enum Length: String, Sendable, CaseIterable, Comparable {
        /// One paragraph: the core idea and nothing else.
        case brief
        /// The idea, the workflow, and one worked example. The default.
        case standard
        /// Adds fan-out and error-handling examples plus the anti-pattern list.
        /// Worth it when the agent will do open-ended multi-step work.
        case full

        public static func < (lhs: Length, rhs: Length) -> Bool {
            lhs.order < rhs.order
        }

        fileprivate var order: Int {
            switch self {
            case .brief: return 0
            case .standard: return 1
            case .full: return 2
            }
        }

        /// Rough size of this tier's text, for budgeting against a prompt.
        ///
        /// Estimated at four characters per token — the usual English-prose rule
        /// of thumb, not a real tokenization. Treat it as a bound to plan with,
        /// not a number to assert on.
        public var approximateTokenCount: Int {
            CodeModeAgentGuidance.systemPrompt(self).count / 4
        }
    }

    /// The guidance text at the requested length.
    public static func systemPrompt(_ length: Length = .standard) -> String {
        switch length {
        case .brief:
            return core
        case .standard:
            return [core, workflow, workedExample].joined(separator: "\n\n")
        case .full:
            return [core, workflow, workedExample, fanOutExample, antiPatterns].joined(separator: "\n\n")
        }
    }

    /// The largest tier that fits the budget, or `.brief` when nothing does.
    ///
    /// `.brief` is returned even when it exceeds the budget: some guidance is the
    /// difference between an agent that batches and one that does not, so the
    /// floor is deliberate rather than an empty string.
    public static func systemPrompt(approximateTokenBudget: Int) -> String {
        systemPrompt(length(forApproximateTokenBudget: approximateTokenBudget))
    }

    /// The tier `systemPrompt(approximateTokenBudget:)` would choose.
    public static func length(forApproximateTokenBudget budget: Int) -> Length {
        Length.allCases
            .sorted(by: >)
            .first { $0.approximateTokenCount <= budget }
            ?? .brief
    }

    // MARK: - Sections

    private static let core = """
    ## Writing code instead of calling tools

    You have a JavaScript runtime with direct access to this device's APIs. Use it \
    to run whole tasks, not single operations. One `executeJavaScript` call should \
    do the entire job — read, loop, branch, filter, transform, write — and return \
    only the finished answer. Ten helper calls inside one script is normal and \
    fast; ten `executeJavaScript` calls that each make one helper call is the \
    mistake this runtime exists to avoid, because every round trip costs a model \
    turn and pushes intermediate data you do not need through your context. \
    Request only the capabilities your script actually calls.
    """

    private static let workflow = """
    ## How to work

    1. Call `searchJavaScriptAPI` first when you are unsure of helper names, \
    arguments, or result shapes. Return `ref.dts` — the TypeScript declaration — \
    rather than assembling the metadata fields yourself.
    2. Write one script that completes the task. Reach for ordinary control flow: \
    loops over collections, `if` for branching, `try`/`catch` around anything that \
    may fail per item.
    3. Do the filtering and aggregation *in the script*. Return the graded answer — \
    a count, a summary, the three matching records — not the raw collection you \
    read. A large return value is truncated, and the data you did not need cost \
    you context on the way through.
    4. Repair from the structured error. It names the capability, the line and \
    column, and what to change; the suggestions tell you when a retry cannot help.
    """

    private static let workedExample = """
    ## The shape to aim for

    Task: "how much did I spend on the trip, and file the receipts?"

    ```javascript
    // ONE call. Reads, filters, sums, writes, and returns just the total.
    const entries = await apple.fs.list({ path: 'documents:receipts' });
    let total = 0;
    const filed = [];

    for (const entry of entries) {
      if (entry.isDirectory || !entry.name.endsWith('.json')) continue;
      const { text } = await apple.fs.read({ path: entry.path });
      const receipt = JSON.parse(text);
      if (receipt.trip !== 'lisbon') continue;
      total += receipt.amount;
      await apple.fs.move({
        from: entry.path,
        to: `documents:receipts/lisbon/${entry.name}`,
        overwrite: true
      });
      filed.push(entry.name);
    }

    return { total, filedCount: filed.length };
    ```

    `allowedCapabilities: ["fs.list", "fs.read", "fs.move"]` — exactly the three \
    helpers the script calls, and nothing else.
    """

    private static let fanOutExample = """
    ## Handling many items and partial failure

    Keep going when one item fails, and report what happened rather than throwing \
    the whole run away:

    ```javascript
    const results = [];
    for (const city of ['lisbon', 'porto', 'faro']) {
      try {
        const response = await fetch(`https://api.example.com/weather/${city}`);
        if (!response.ok) { results.push({ city, error: response.status }); continue; }
        const data = await response.json();
        results.push({ city, tempC: data.current.temp_c });
      } catch (error) {
        results.push({ city, error: String(error) });
      }
    }
    return results;
    ```

    Native calls run one at a time, so `Promise.all` does not make these overlap — \
    a loop is just as fast here and reads better. Use \
    `await new Promise(r => setTimeout(r, 1000))` to back off between retries; \
    delays are real.
    """

    private static let antiPatterns = """
    ## Anti-patterns

    - **One call per operation.** If your second `executeJavaScript` starts from \
    data the first one returned, both should have been one script.
    - **Returning the raw collection.** Reading 500 records to answer "how many \
    are overdue" should return a number, not 500 records.
    - **Asking for capabilities you do not call.** Request the exact set your \
    script uses; a wider list is refused by hosts that enforce a ceiling, and it \
    is the wrong thing to ask a user to approve.
    - **Forgetting `await`.** An un-awaited helper's failure is silently \
    discarded and you will be told the run succeeded. A \
    `BRIDGE_FAILURES_NOT_SURFACED` diagnostic means exactly this happened.
    - **Re-running a call the error told you not to retry.** \
    `NETWORK_POLICY_VIOLATION`, `UI_PRESENTER_UNAVAILABLE`, and a host-withheld \
    `CAPABILITY_DENIED` will not succeed on a second attempt.
    """
}
