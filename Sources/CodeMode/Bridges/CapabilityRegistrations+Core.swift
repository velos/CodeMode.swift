import Foundation

extension DefaultCapabilityRegistrationBuilder {
    // PHASE3-SKIP: networkFetch declares nested dotted-path arguments
    // (options.method, options.headers, …). The @BuiltInCodeMode Arguments
    // model is flat — property names map to top-level JSON keys — so it cannot
    // reproduce the advertised optionalArguments list without changing it.
    // Its options.responseEncoding constraint stays in the central defaults
    // table. Left on the flat-init idiom.
    func networkRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                jsNames: ["fetch"],
                descriptor: .init(
                    id: .networkFetch,
                    title: "Fetch HTTP resource",
                    summary: "Perform HTTP(S) requests through URLSession via a fetch-compatible API.",
                    tags: ["network", "http", "fetch"],
                    example: "await fetch('https://api.example.com/data').then(r => r.json())",
                    requiredArguments: ["url"],
                    optionalArguments: [
                        "options.method",
                        "options.headers",
                        "options.body",
                        "options.bodyBase64",
                        "options.timeoutMs",
                        "options.responseEncoding",
                    ],
                    argumentHints: [
                        "url": "Absolute HTTP(S) URL string.",
                        "options.method": "HTTP method; defaults to GET.",
                        "options.headers": "Object of header key/value string pairs.",
                        "options.body": "UTF-8 request body string.",
                        "options.bodyBase64": "Base64-encoded request body. Mutually exclusive with options.body.",
                        "options.timeoutMs": "Request and bridge wait timeout in milliseconds; defaults to 30000.",
                        "options.responseEncoding": "text (default) or base64.",
                    ],
                    resultSummary: "Object with ok/status/statusText/headers/bodyText or bodyBase64."
                ),
                handler: { args, context in
                    try network.fetch(arguments: args, context: context)
                }
            ),
        ]
    }


    func keychainRegistrations() -> [CapabilityRegistration] {
        KeychainCodeModeBuiltIns(keychain: keychain).capabilityRegistrations()
    }


    func filesystemRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: FSListTool(fs: fs)),
            CapabilityRegistration(tool: FSReadTool(fs: fs)),
            CapabilityRegistration(tool: FSWriteTool(fs: fs)),
            CapabilityRegistration(tool: FSMoveTool(fs: fs)),
            CapabilityRegistration(tool: FSCopyTool(fs: fs)),
            CapabilityRegistration(tool: FSDeleteTool(fs: fs)),
            CapabilityRegistration(tool: FSStatTool(fs: fs)),
            CapabilityRegistration(tool: FSMkdirTool(fs: fs)),
            CapabilityRegistration(tool: FSExistsTool(fs: fs)),
            CapabilityRegistration(tool: FSAccessTool(fs: fs)),
        ]
    }
}
