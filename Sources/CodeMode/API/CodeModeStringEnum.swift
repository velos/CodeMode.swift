import Foundation

/// A string argument with a closed set of accepted values.
///
/// Conforming enums are the single source of truth for a constrained string
/// argument: the advertised `allowedStringValues` in capability metadata, the
/// decode behavior (case-insensitive, alias-aware), and the typed value handed
/// to the implementation all come from one declaration, so they cannot drift.
///
/// Raw values are the canonical spellings advertised to callers. Alternate
/// accepted spellings go in `codeModeAliases`; both are matched
/// case-insensitively, mirroring how bridges have historically parsed
/// constrained strings.
public protocol CodeModeStringEnum: CodeModeJSONDecodable, RawRepresentable, CaseIterable, Sendable
where RawValue == String {
    /// Alternate accepted spellings mapped to their canonical case.
    static var codeModeAliases: [String: Self] { get }
}

extension CodeModeStringEnum {
    public static var codeModeAliases: [String: Self] { [:] }

    /// Every accepted spelling, canonical raw values first, for capability
    /// metadata (`CapabilityArgumentConstraints.allowedStringValues`).
    public static var codeModeAllowedValues: [String] {
        allCases.map(\.rawValue) + codeModeAliases.keys.sorted()
    }

    /// Case-insensitive, alias-aware match; nil when the value is not accepted.
    public static func codeModeValue(matching raw: String) -> Self? {
        let normalized = raw.lowercased()
        if let match = allCases.first(where: { $0.rawValue.lowercased() == normalized }) {
            return match
        }
        return codeModeAliases.first { $0.key.lowercased() == normalized }?.value
    }

    public static func decodeCodeModeJSON(_ value: JSONValue, argumentName: String) throws -> Self {
        guard let string = value.stringValue else {
            throw CodeModeFunctionError.invalidArguments("Argument \(argumentName) must be a string")
        }
        guard let match = codeModeValue(matching: string) else {
            throw CodeModeFunctionError.invalidArguments(
                "Argument \(argumentName) must be one of \(codeModeAllowedValues.joined(separator: ", "))"
            )
        }
        return match
    }
}
