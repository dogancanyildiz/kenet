import Foundation
import Testing
import VaultStore

struct ConcurrencyTests {
    @Test func concurrentStoresForOneRootLoseNoWrites() async throws {
        let random = CountingRandom()
        let vault = try StoreVault(random: { random.next() })
        defer { vault.remove() }
        let second = VaultStore(vaultRoot: vault.root, index: vault.index, randomValue: { random.next() })
        try await withThrowingTaskGroup(of: Void.self) { group in
            for number in 0..<32 {
                group.addTask {
                    let store = number.isMultiple(of: 2) ? vault.store : second
                    try await store.addingTask(on: storeDate, text: "Kitap " + String(number))
                }
            }
            try await group.waitForAll()
        }
        let blocks = try vault.index.blocks(on: storeDate)
        #expect(blocks.count == 32)
        #expect(Set(blocks.compactMap(\.identifier)).count == 32)
        #expect(Set(blocks.map(\.text)) == Set((0..<32).map { "Kitap " + String($0) }))
        try vault.check()
    }
}
