import Foundation
import Testing
import VaultFormat
import VaultIndex

struct GraceDayQueryTests {
    @Test func markdownQueryCarriesGraceWithoutChangingSource() throws {
        let root = try Fixtures.root().appendingPathComponent("goal-chain/query")
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "md" }
        let before = try files.map { try Data(contentsOf: $0) }
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let today = CalendarDate("2026-09-17")!
        let row = try #require(try index.goalStatus(key: "orbit", today: today))
        #expect(row.status.streak == 15)
        #expect(row.graceDaysAvailable == 0)
        #expect(row.graceSpentDays == [CalendarDate("2026-09-15")!, CalendarDate("2026-09-16")!])
        #expect(try index.goalStatuses(today: today) == [row])
        #expect(try files.map { try Data(contentsOf: $0) } == before)
    }
}
