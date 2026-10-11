import Foundation
import Testing

@testable import VaultIndex

struct CadenceFieldTests {
    @Test func cadenceFieldsMatchFixture() throws {
        let expected = try decode("index/cadence/fields.json")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: vault())
        #expect(try index.cadenceFields() == expected)
    }

    /// `cadence_snoozed_until` is a date and would otherwise be an anniversary.
    @Test func cadenceSnoozeIsNotAnAnniversary() throws {
        let expected = try decode("index/cadence/anniversaries.json")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: vault())
        let fields = try index.anniversaryFields()
        #expect(fields == expected)
        #expect(fields.allSatisfy { !PersonCadenceKeys.contains($0.key) })
        #expect(fields.contains { $0.key == "doğum günü" })
        #expect(fields.contains { $0.file == "books/Fable.md" && $0.key == "bitirme" })
    }

    private func vault() throws -> URL {
        try Fixtures.root().appendingPathComponent("vaults/cadence")
    }

    private func decode(_ path: String) throws -> [IndexedEntityField] {
        let url = try Fixtures.root().appendingPathComponent(path)
        return try JSONDecoder().decode([IndexedEntityField].self, from: Data(contentsOf: url))
    }
}

private enum PersonCadenceKeys {
    static let values = ["cadence_days", "cadence_snoozed_until", "cadence_paused"]
    static func contains(_ key: String) -> Bool { values.contains(key) }
}
