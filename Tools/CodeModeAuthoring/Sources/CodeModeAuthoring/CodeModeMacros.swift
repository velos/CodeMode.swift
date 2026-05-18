@_exported import CodeMode

@attached(extension, conformances: CodeModeProvider, names: named(codeModePath), named(codeModeRegistrations))
public macro CodeMode(path: String) = #externalMacro(module: "CodeModeMacros", type: "CodeModeMacro")

@attached(peer)
public macro CodeModeDescription(_ text: String) = #externalMacro(module: "CodeModeMacros", type: "CodeModeDescriptionMacro")

@attached(peer)
public macro CodeModeName(_ text: String) = #externalMacro(module: "CodeModeMacros", type: "CodeModeNameMacro")

@attached(peer)
public macro CodeModeParam(_ name: String, _ description: String) = #externalMacro(module: "CodeModeMacros", type: "CodeModeParamMacro")

@attached(peer)
public macro CodeModeResult(_ description: String) = #externalMacro(module: "CodeModeMacros", type: "CodeModeResultMacro")
