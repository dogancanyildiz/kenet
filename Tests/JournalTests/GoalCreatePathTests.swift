import Foundation
import GoalTracking
import Testing
import VaultFormat

@testable import Journal

@MainActor
struct GoalCreatePathTests {
    @Test func createGoalWithColonAppearsWithoutRebuild() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()

        try await context.store.createGoal(
            name: "Koşu: 5 km", period: .day, kind: .number, target: 5, unit: "km")

        #expect(context.store.content.goals.contains { $0.name == "Koşu: 5 km" })
        let root = try #require(context.store.vaultURL)
        #expect(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("goals/Koşu 5 km.md").path))
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent("goals/Koşu: 5 km.md").path))

        await context.store.refresh()
        #expect(context.store.content.goals.contains { $0.name == "Koşu: 5 km" })
        #expect(context.store.content.goals.count == 1)
    }
}
