import Foundation

/// Generates TypeScript declarations for the CodeMode JavaScript surface.
///
/// The registry already holds names, required/optional arguments, types, enum
/// constraints, and hints; before this, the model saw that as a flat
/// `argumentTypes` map of six coarse cases and a prose `resultSummary`. Models
/// write markedly better code against real declarations, so the same metadata is
/// emitted as `.d.ts` — per capability for search results, and whole-surface for
/// a system prompt.
///
/// Result types are `CodeModeValue` for now: built-in tools return untyped
/// `JSONValue` dictionaries, so a typed result would be a fiction. The prose
/// `resultSummary` is carried in the doc comment instead, and a per-capability
/// result schema can tighten this later without changing the shape here.
public enum TypeScriptDeclarations {
    /// Shared types and the runtime globals that are not catalog capabilities.
    ///
    /// Hand-authored deliberately: these are the Node-compatibility shims in
    /// `RuntimeJavaScript.bootstrap`, and unlike the namespaced helpers they take
    /// *positional* arguments, which the catalog has no way to express. Keeping
    /// them here means the declarations tell the truth about both conventions.
    public static let preamble = """
    /** Any JSON-representable value. Bridge results are JSON, not class instances. */
    type CodeModeValue =
      | null
      | boolean
      | number
      | string
      | CodeModeValue[]
      | { [key: string]: CodeModeValue };

    declare const console: {
      log(...values: unknown[]): void;
      info(...values: unknown[]): void;
      warn(...values: unknown[]): void;
      error(...values: unknown[]): void;
    };

    interface CodeModeResponse {
      ok: boolean;
      status: number;
      statusText: string;
      headers: { get(name: string): string | null };
      text(): Promise<string>;
      json(): Promise<CodeModeValue>;
    }

    /**
     * HTTP(S) fetch. Runs on an isolated session: no app cookies, no stored
     * credentials. Cookie/Authorization/Proxy-* request headers are refused
     * unless the host app permits them.
     */
    declare function fetch(
      url: string,
      options?: {
        method?: string;
        headers?: { [name: string]: string };
        body?: string;
        bodyBase64?: string;
        timeoutMs?: number;
        responseEncoding?: "text" | "base64";
      }
    ): Promise<CodeModeResponse>;

    /**
     * Node-style filesystem aliases. Unlike the apple.* helpers these take
     * POSITIONAL arguments and return Node-like values.
     */
    declare const fs: {
      promises: {
        readFile(path: string, encoding?: "utf8" | "base64"): Promise<string>;
        writeFile(path: string, data: string, encoding?: "utf8" | "base64"): Promise<CodeModeValue>;
        readdir(path: string): Promise<CodeModeValue[]>;
        stat(path: string): Promise<CodeModeValue>;
        access(path: string): Promise<CodeModeValue>;
        mkdir(path: string, options?: { recursive?: boolean }): Promise<CodeModeValue>;
        rm(path: string, options?: { recursive?: boolean }): Promise<CodeModeValue>;
        rename(from: string, to: string, options?: { overwrite?: boolean; recursive?: boolean }): Promise<CodeModeValue>;
        copyFile(from: string, to: string, options?: { overwrite?: boolean; recursive?: boolean }): Promise<CodeModeValue>;
      };
    };

    declare const path: {
      join(...parts: string[]): string;
    };
    """

    /// The declaration for one capability, suitable for a search result payload.
    public static func declaration(for reference: JavaScriptAPIReference) -> String {
        guard let canonical = canonicalName(for: reference) else {
            return ""
        }
        let name = canonical.replacingOccurrences(of: ".", with: "_")
        return "\(documentation(for: reference, canonicalName: canonical))\ndeclare function \(name)\(functionSignature(for: reference));"
    }

    /// The whole surface: the preamble plus every capability, grouped into
    /// namespaces by its canonical dotted JavaScript name.
    public static func surface(for references: [JavaScriptAPIReference]) -> String {
        var root = Namespace(name: "")
        for reference in references.sorted(by: { $0.capability < $1.capability }) {
            guard let canonical = canonicalName(for: reference) else {
                continue
            }
            var components = canonical.split(separator: ".").map(String.init)
            guard components.count >= 2 else {
                // A bare global such as `fetch` is covered by the preamble.
                continue
            }
            let functionName = components.removeLast()
            root.insert(
                Member(
                    name: functionName,
                    documentation: documentation(for: reference, canonicalName: canonical),
                    signature: functionSignature(for: reference)
                ),
                at: components
            )
        }

        let body = root.children
            .sorted { $0.key < $1.key }
            .map { render(namespace: $0.value, indent: "", isTopLevel: true) }
            .joined(separator: "\n\n")

        return """
        // CodeMode JavaScript API — generated from the capability registry.
        // Only helpers supported on the current host platform appear here.

        \(preamble)

        \(body)
        """
    }

    // MARK: - Declaration pieces

    /// The namespaced helper name, preferred over Node-style aliases: aliases use
    /// positional arguments the catalog cannot describe, and are documented in
    /// the preamble instead.
    private static func canonicalName(for reference: JavaScriptAPIReference) -> String? {
        reference.jsNames.first { $0.contains(".") && $0.hasPrefix("fs.promises.") == false }
            ?? reference.jsNames.first
    }

    private static func documentation(for reference: JavaScriptAPIReference, canonicalName: String) -> String {
        var lines = ["/**"]
        lines.append(" * \(reference.summary)")
        lines.append(" *")
        lines.append(" * Capability: \(reference.capability)")
        lines.append(" * Returns: \(reference.resultSummary)")

        let aliases = reference.jsNames.filter { $0 != canonicalName }
        if aliases.isEmpty == false {
            // Only the fs.promises.* shims are positional; other aliases are
            // additional namespaced spellings of the same object-argument call.
            let positional = aliases.filter { $0.hasPrefix("fs.promises.") || $0 == "fetch" }
            let note = positional.isEmpty ? "" : " — \(positional.joined(separator: ", ")) take positional arguments"
            lines.append(" * Aliases: \(aliases.joined(separator: ", "))\(note)")
        }
        if reference.example.isEmpty == false {
            lines.append(" *")
            lines.append(" * @example \(reference.example)")
        }
        lines.append(" */")
        return lines.joined(separator: "\n")
    }

    private static func functionSignature(for reference: JavaScriptAPIReference) -> String {
        let tree = ArgumentTree(reference: reference)
        guard tree.isEmpty == false else {
            return "(): Promise<CodeModeValue>"
        }
        // `args` is optional only when nothing in it is required.
        let optionalMarker = reference.requiredArguments.isEmpty ? "?" : ""
        return "(args\(optionalMarker): \(tree.render(indent: ""))): Promise<CodeModeValue>"
    }

    // MARK: - Argument tree
    //
    // Arguments are declared as dotted paths (`options.timeoutMs`), so the object
    // literal has to be rebuilt from them.

    private struct ArgumentTree {
        private var children: [String: ArgumentTree] = [:]
        private var leaves: [Leaf] = []

        private struct Leaf {
            var name: String
            var type: String
            var optional: Bool
            var hint: String?
        }

        init(reference: JavaScriptAPIReference) {
            let allPaths = Array(Set(
                reference.requiredArguments + reference.optionalArguments + Array(reference.argumentTypes.keys)
            )).sorted()
            let required = Set(reference.requiredArguments)

            for path in allPaths {
                let components = path.split(separator: ".").map(String.init)
                insert(
                    components: components,
                    leaf: Leaf(
                        name: components.last ?? path,
                        type: TypeScriptDeclarations.tsType(
                            for: reference.argumentTypes[path] ?? .any,
                            allowedValues: reference.argumentConstraints.allowedStringValues[path]
                        ),
                        // A nested path is optional unless the exact path is
                        // listed as required.
                        optional: required.contains(path) == false,
                        hint: reference.argumentHints[path]
                    )
                )
            }
        }

        private init() {}

        var isEmpty: Bool {
            children.isEmpty && leaves.isEmpty
        }

        private mutating func insert(components: [String], leaf: Leaf) {
            guard components.count > 1 else {
                // A declared parent (`options: object`) whose children also appear
                // is represented by the nested literal, not by a duplicate leaf.
                if children[leaf.name] == nil, leaves.contains(where: { $0.name == leaf.name }) == false {
                    leaves.append(leaf)
                }
                return
            }
            let head = components[0]
            leaves.removeAll { $0.name == head }
            var child = children[head] ?? ArgumentTree()
            child.insert(components: Array(components.dropFirst()), leaf: leaf)
            children[head] = child
        }

        func render(indent: String) -> String {
            let inner = indent + "  "
            var lines: [String] = ["{"]

            for leaf in leaves.sorted(by: { $0.name < $1.name }) {
                if let hint = leaf.hint, hint.isEmpty == false {
                    lines.append("\(inner)/** \(hint) */")
                }
                lines.append("\(inner)\(leaf.name)\(leaf.optional ? "?" : ""): \(leaf.type);")
            }

            for (name, child) in children.sorted(by: { $0.key < $1.key }) {
                lines.append("\(inner)\(name)?: \(child.render(indent: inner));")
            }

            lines.append("\(indent)}")
            return lines.joined(separator: "\n")
        }
    }

    private static func tsType(for type: CapabilityArgumentType, allowedValues: [String]?) -> String {
        if let allowedValues, allowedValues.isEmpty == false {
            // The constraint is the type: a union beats `string` plus prose the
            // model has to notice.
            return allowedValues.map { "\"\($0)\"" }.joined(separator: " | ")
        }

        switch type {
        case .string:
            return "string"
        case .number:
            return "number"
        case .bool:
            return "boolean"
        case .object:
            return "{ [key: string]: CodeModeValue }"
        case .array:
            return "CodeModeValue[]"
        case .any:
            return "CodeModeValue"
        }
    }

    // MARK: - Namespace rendering

    private struct Member {
        var name: String
        var documentation: String
        var signature: String
    }

    private final class Namespace {
        let name: String
        var children: [String: Namespace] = [:]
        var members: [Member] = []

        init(name: String) {
            self.name = name
        }

        func insert(_ member: Member, at path: [String]) {
            guard let head = path.first else {
                members.append(member)
                return
            }
            let child = children[head] ?? Namespace(name: head)
            children[head] = child
            child.insert(member, at: Array(path.dropFirst()))
        }
    }

    private static func render(namespace: Namespace, indent: String, isTopLevel: Bool) -> String {
        let inner = indent + "  "
        var lines = ["\(indent)\(isTopLevel ? "declare namespace" : "namespace") \(namespace.name) {"]

        for member in namespace.members.sorted(by: { $0.name < $1.name }) {
            lines.append(indented(member.documentation, by: inner))
            lines.append("\(inner)function \(member.name)\(indented(member.signature, by: inner, skipFirstLine: true));")
        }

        for (_, child) in namespace.children.sorted(by: { $0.key < $1.key }) {
            lines.append(render(namespace: child, indent: inner, isTopLevel: false))
        }

        lines.append("\(indent)}")
        return lines.joined(separator: "\n")
    }

    private static func indented(_ text: String, by indent: String, skipFirstLine: Bool = false) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { index, line in
                index == 0 && skipFirstLine ? String(line) : indent + line
            }
            .joined(separator: "\n")
    }
}
