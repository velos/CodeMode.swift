import Foundation
import Testing
@testable import CodeMode

@Test func nestedResultSchemasRoundTripWithCompactJSON() throws {
    let schema: CodeModeResultSchema = .nullable(.array(.object([
        .init(name: "stats", schema: .dictionary(.number), hint: "Counts."),
        .init(name: "enabled", schema: .bool),
        .init(name: "note", schema: .nullable(.string)),
        .init(name: "raw", schema: .any),
    ])))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let encoded = try encoder.encode(schema)
    #expect(String(decoding: encoded, as: UTF8.self) == #"{"nullable":{"array":{"object":[{"hint":"Counts.","name":"stats","schema":{"dictionary":"number"}},{"name":"enabled","schema":"boolean"},{"name":"note","schema":{"nullable":"string"}},{"name":"raw","schema":"any"}]}}}"#)
    #expect(try JSONDecoder().decode(CodeModeResultSchema.self, from: encoded) == schema)
}

@Test(arguments: [#""bool""#, "1", "{}", #"{"unknown":"string"}"#, #"{"array":"string","nullable":"number"}"#])
func resultSchemaDecodingRejectsInvalidShapes(json: String) {
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(CodeModeResultSchema.self, from: Data(json.utf8))
    }
}
