import ArgumentParser

struct LLM: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "llm",
        abstract: "Run live model evaluation scenarios."
    )

    @Argument(help: "Scenario IDs to run. Omit to use --suite.")
    var scenarioIDs: [String] = []

    @Option(name: .long, help: "Scenario suite to run when no scenario IDs are provided: smoke, core, failures, catalog, or all.")
    var suite: LLMEvalSuite = .smoke

    @Option(name: .customLong("repeat"), help: "Number of times to run each selected scenario.")
    var repeatCount = 1

    @Option(name: .long, help: "Model ID.")
    var model: String?

    @Option(name: .long, help: "Path to a dotenv file containing model credentials.")
    var envFile = ".env"

    @Option(name: .long, help: "Maximum model/tool turns per scenario.")
    var maxTurns = 6

    @Option(name: .long, help: "Maximum retries for transient model transport errors.")
    var modelRetries = 3

    @Option(name: .long, help: "Base delay in milliseconds for transient model transport retries.")
    var retryDelayMs = 2_000

    @Option(name: .long, help: "Delay in milliseconds before each model request.")
    var requestDelayMs = 0

    @Option(name: .long, help: "Maximum output tokens for each model call.")
    var maxOutputTokens: Int?

    @Option(name: .long, help: "Optional reasoning effort: none, low, medium, high, or xhigh.")
    var reasoningEffort: String?

    @Flag(name: .long, help: "Emit machine-readable JSON.")
    var json = false

    @Option(name: .long, help: "Write the JSON report to a file path.")
    var output: String?

    @Flag(name: .long, help: "Suppress per-scenario progress output on stderr.")
    var quiet = false

    @Flag(name: .long, help: "Print captured tool code in text output.")
    var showCode = false

    mutating func run() async throws {
        throw ValidationError(
            """
            Live LLM evals are not included in the default CodeModeEval package because they require private Wavelike dependencies.
            Use `codemode-eval run` for deterministic checks and `codemode-eval plan` to preview LLM suite budgets.
            """
        )
    }
}
