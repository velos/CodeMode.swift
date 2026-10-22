/// An update argument: omission preserves the field; null clears it.
enum Patch<Value: Sendable>: Sendable {
    case unchanged
    case clear
    case set(Value)

    var isUnchanged: Bool {
        if case .unchanged = self { return true }
        return false
    }

    /// Apply a clear or replacement value; omission never calls the setter.
    func apply(_ update: (Value?) throws -> Void) rethrows {
        switch self {
        case .unchanged: break
        case .clear: try update(nil)
        case let .set(value): try update(value)
        }
    }

    static func decode(_ value: JSONValue?, using decode: () throws -> Value?) throws -> Self {
        guard let value else { return .unchanged }
        if case .null = value { return .clear }
        // Match optional decoding, including its treatment of blank dates.
        guard let decoded = try decode() else { return .clear }
        return .set(decoded)
    }
}
