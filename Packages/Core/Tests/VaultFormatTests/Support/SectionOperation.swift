import Testing
import VaultFormat

/// Checks the section append fixture independently against its expected bytes.
enum SectionOperation {
    static func check(_ json: JSONValue, description: JSONValue, before: RawDocument, name: String) throws {
        #expect(Set(json.keys) == ["operation", "kind", "lines"])
        #expect(json["operation"] == .string("append"))
        let nameOfKind = try #require(json["kind"]?.stringValue)
        let kind = try #require(DaySectionKind(rawValue: nameOfKind))
        let contents = try #require(json["lines"]?.arrayValue).map { try #require($0.stringValue) }
        if let error = description["expectedError"] {
            #expect(try Fixtures.fileNames(in: "write/\(name)") == ["input.md", "operation.json"])
            #expect { try before.appendingLines(contents, toSection: kind) } throws: {
                ($0 as? EditError)?.fixtureName == error.stringValue
            }
        } else {
            #expect(try Fixtures.fileNames(in: "write/\(name)") == ["expected.md", "input.md", "operation.json"])
            let expected = try Fixtures.bytes(at: "write/\(name)/expected.md")
            let after = try before.appendingLines(contents, toSection: kind)
            #expect(after.serialized() == expected)
            #expect(after == RawDocument(bytes: expected))
            #expect(after.daySections == RawDocument(bytes: expected).daySections)
        }
    }
}
