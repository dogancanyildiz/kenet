import Foundation
import GoalTracking
import Testing
import VaultFormat

struct GoalStoreTests {
    @Test func writesAndRemovesLogsInIndex() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try await vault.store.settingGoalValue(on: storeDate, key: "spor", value: .boolean(true))
        #expect(try vault.index.goalLogs(key: "spor").map(\.value) == ["true"])
        try await vault.store.settingGoalValue(on: storeDate, key: "kitap", value: .number(20))
        #expect(try vault.index.goalLogs().count == 2)
        try await vault.store.settingGoalValue(on: storeDate, key: "spor", value: nil)
        #expect(try vault.index.goalLogs(key: "spor").isEmpty)
        #expect(!String(decoding: try vault.bytes(), as: UTF8.self).contains("false"))
        try vault.check()
    }

    @Test(arguments: [0.0000001, 1e20, 20.029, Double.leastNonzeroMagnitude, Double.greatestFiniteMagnitude])
    func numericSpellingHasNoExponentAndRoundTrips(_ value: Double) async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try await vault.store.settingGoalValue(on: storeDate, key: "su", value: .number(value))
        let log = try #require(vault.index.goalLogs(key: "su").first)
        #expect(log.kind == "number")
        #expect(Double(log.value) == value)
        #expect(!log.value.contains("e"))
        let before = try vault.bytes()
        try await vault.store.settingGoalValue(on: storeDate, key: "su", value: .number(value))
        #expect(try vault.bytes() == before)
        try vault.check()
    }

    @Test(arguments: [-1.0, Double.infinity, Double.nan])
    func invalidValuesNeverCreateFiles(_ value: Double) async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        await #expect(throws: EditError.invalidValue) {
            try await vault.store.settingGoalValue(on: storeDate, key: "su", value: .number(value))
        }
        #expect(try vault.index.files().isEmpty)
    }
}
