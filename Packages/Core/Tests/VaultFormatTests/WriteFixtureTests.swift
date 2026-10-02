import Testing
import VaultFormat

/// Every directory under `Fixtures/write` holds an `input.md`, the `operation.json` to apply and
/// either the `expected.md` it must produce byte for byte or the error it must be refused with.
struct WriteFixtureTests {
    @Test func casesExist() throws {
        #expect(try !Fixtures.caseNames(in: "write").isEmpty)
    }

    @Test(arguments: try Fixtures.caseNames(in: "write"))
    func operationWritesAsExpected(name: String) throws {
        let input = try Fixtures.bytes(at: "write/\(name)/input.md")
        let description = try Fixtures.json(at: "write/\(name)/operation.json")
        let before = RawDocument(bytes: input)

        #expect(
            Set(description.keys).isSubset(of: ["frontmatter", "sections", "expectedError"]),
            "unknown keys in \(description.keys)")
        if let section = description["sections"] {
            try SectionOperation.check(section, description: description, before: before, name: name)
            return
        }
        let operation = try FrontmatterOperation(json: try #require(description["frontmatter"]))

        if let expectedError = description["expectedError"] {
            #expect(try Fixtures.fileNames(in: "write/\(name)") == ["input.md", "operation.json"])
            #expect {
                try operation.apply(to: before)
            } throws: { error in
                (error as? EditError)?.fixtureName == expectedError.stringValue
            }
            return
        }

        #expect(try Fixtures.fileNames(in: "write/\(name)") == ["expected.md", "input.md", "operation.json"])
        let expected = try Fixtures.bytes(at: "write/\(name)/expected.md")
        let after = try operation.apply(to: before)

        #expect(after.serialized() == expected, "the operation writes:\n\(visible(after.serialized()))")
        #expect(frontmatterEditViolations(before: before, after: after, operation: operation) == [])
        // The model the edit returns is the model a fresh read of the expected file gives.
        #expect(after == RawDocument(bytes: expected))
        #expect(before.serialized() == input)
    }
}
