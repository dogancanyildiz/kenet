import Foundation
import GoalTracking
import Testing
import VaultFormat

struct GoalWriteFixture: Decodable, Sendable {
    enum Value: Decodable, Sendable {
        case boolean(Bool)
        case number(Double)
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let flag = try? container.decode(Bool.self) {
                self = .boolean(flag)
            } else {
                self = .number(try container.decode(Double.self))
            }
        }
        var value: GoalValue {
            switch self {
            case .boolean(let flag): .boolean(flag)
            case .number(let number): .number(number)
            }
        }
    }
    let id: String, day: String, key: String
    let value: Value?
    let input: String?, expected: String?, error: String?
}

func goalWriteCases() throws -> [GoalWriteFixture] {
    try JSONDecoder().decode(
        [GoalWriteFixture].self,
        from: Data(contentsOf: Fixtures.root().appendingPathComponent("goals/writes/cases.json")))
}

@Test(arguments: try goalWriteCases())
func goalStoreFixtures(_ fixture: GoalWriteFixture) async throws {
    let vault = try StoreVault()
    defer { vault.remove() }
    let directory = try Fixtures.root().appendingPathComponent("goals/writes")
    if let input = fixture.input {
        try vault.write(
            storePath, String(decoding: Data(contentsOf: directory.appendingPathComponent(input)), as: UTF8.self))
    }
    try vault.index.rebuild(vaultRoot: vault.root)
    let attributes = try? FileManager.default.attributesOfItem(
        atPath: vault.root.appendingPathComponent(storePath).path)
    if fixture.error != nil {
        await #expect(throws: EditError.notAMapping(key: "goals")) {
            try await vault.store.settingGoalValue(on: storeDate, key: fixture.key, value: fixture.value?.value)
        }
    } else {
        try await vault.store.settingGoalValue(
            on: try #require(CalendarDate(fixture.day)), key: fixture.key, value: fixture.value?.value)
    }
    if let expected = fixture.expected {
        let expectedBytes = try Data(contentsOf: directory.appendingPathComponent(expected))
        #expect(try vault.bytes() == expectedBytes, "\(fixture.id)")
        if let input = fixture.input, try Data(contentsOf: directory.appendingPathComponent(input)) == expectedBytes {
            let after = try FileManager.default.attributesOfItem(
                atPath: vault.root.appendingPathComponent(storePath).path)
            #expect(attributes?[.modificationDate] as? Date == after[.modificationDate] as? Date)
            #expect(attributes?[.systemFileNumber] as? NSNumber == after[.systemFileNumber] as? NSNumber)
        }
    } else {
        #expect(!FileManager.default.fileExists(atPath: vault.root.appendingPathComponent(storePath).path))
    }
    try vault.check()
}
