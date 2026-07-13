@_exported import CodeMode

@attached(extension, conformances: CodeModeProvider, names: named(codeModePath), named(codeModeRegistrations))
public macro CodeMode(path: String, description: String) = #externalMacro(module: "CodeModeMacros", type: "CodeModeMacro")

@attached(peer)
public macro CodeModeParam(_ description: String) = #externalMacro(module: "CodeModeMacros", type: "CodeModeParamMacro")

@attached(peer)
public macro CodeModeResult(_ description: String) = #externalMacro(module: "CodeModeMacros", type: "CodeModeResultMacro")
