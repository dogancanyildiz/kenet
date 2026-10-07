import Foundation
import GoalTracking
import Testing
import VaultFormat

struct GoalReadScopeTests {
    @Test func settingGoalValueReadCountIsIndependentOfVaultSize() async throws {
        let reader = CountingReader()
        let vault = try StoreVault(readFile: reader.read)
        defer { vault.remove() }
        try vault.write(
            "goals/Spor.md",
            """
            ---
            type: goal
            name: Spor
            key: spor
            period: day
            kind: boolean
            target: 1
            ---

            """)
        for index in 0..<80 {
            try vault.write(
                "people/Person-\(index).md",
                """
                ---
                type: person
                name: Person \(index)
                ---

                """)
        }
        try vault.index.rebuild(vaultRoot: vault.root)

        reader.reset()
        try await vault.store.settingGoalValue(on: storeDate, key: "spor", value: .boolean(true))
        let smallVaultReads = Set(reader.markdownPaths(under: vault.root))
        #expect(smallVaultReads.contains(storePath))
        #expect(smallVaultReads.allSatisfy { !$0.hasPrefix("people/") })
        #expect(smallVaultReads.count <= 5)

        for index in 80..<240 {
            try vault.write(
                "people/Person-\(index).md",
                """
                ---
                type: person
                name: Person \(index)
                ---

                """)
        }
        let later = storeDate.addingDays(1)!
        reader.reset()
        try await vault.store.settingGoalValue(on: later, key: "spor", value: .boolean(true))
        let largeVaultReads = Set(reader.markdownPaths(under: vault.root))
        #expect(largeVaultReads.contains(vault.store.dayFilePath(for: later)))
        #expect(largeVaultReads.allSatisfy { !$0.hasPrefix("people/") })
        #expect(largeVaultReads.count == smallVaultReads.count)
        #expect(largeVaultReads.count <= 5)
    }
}
