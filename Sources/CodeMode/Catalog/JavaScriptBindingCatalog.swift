import Foundation

enum JavaScriptBindingCatalog {
    static func pruningScript(removingJavaScriptNames names: some Sequence<String>) -> String {
        let bindingsToRemove = Array(Set(names)).sorted()

        guard bindingsToRemove.isEmpty == false else {
            return ""
        }

        var lines = bindingsToRemove.map { name in
            "delete globalThis.\(name);"
        }

        let groupPaths = Set(
            bindingsToRemove.compactMap { name -> String? in
                let components = name.split(separator: ".")
                guard components.count >= 2 else {
                    return nil
                }
                return components.dropLast().joined(separator: ".")
            }
        )

        for path in groupPaths.sorted(by: { lhs, rhs in
            lhs.components(separatedBy: ".").count > rhs.components(separatedBy: ".").count
        }) {
            lines.append("if (globalThis.\(path) && Object.keys(globalThis.\(path)).length === 0) { delete globalThis.\(path); }")
        }

        for root in ["apple", "ios", "fs"] {
            lines.append("if (globalThis.\(root) && Object.keys(globalThis.\(root)).length === 0) { delete globalThis.\(root); }")
        }

        return lines.joined(separator: "\n")
    }
}
