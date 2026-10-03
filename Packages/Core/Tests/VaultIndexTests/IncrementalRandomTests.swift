import Foundation
import Testing

@testable import VaultIndex

@Test func seededRandomEditsMatchFullRebuild() throws {
    try withVault { temporary in
        let root = temporary.appendingPathComponent("sample")
        try FileManager.default.copyItem(at: Fixtures.root().appendingPathComponent("vaults/sample"), to: root)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        var state: UInt64 = 0x1234_abcd
        func next(_ limit: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            return Int((state >> 32) % UInt64(limit))
        }
        var paths: Set<String> = []
        for step in 0..<100 {
            let path = "notes/Su \(next(12)).md"
            switch next(4) {
            case 0, 1:
                try write(
                    root, path,
                    "---\ntype: person\nname: Deniz Arıkan\naliases: [Selin]\n---\n- [\(step % 2 == 0 ? " " : "x")] Kitap \(step) ^id\(next(4))\n[[Su \(next(12))]] [[Deniz Arıkan]]"
                )
                paths.insert(path)
            case 2:
                if paths.remove(path) != nil {
                    try FileManager.default.removeItem(at: root.appendingPathComponent(path))
                }
            default:
                let destination = "notes/Su \(next(12)).md"
                if paths.contains(path) && !paths.contains(destination) {
                    try FileManager.default.moveItem(
                        at: root.appendingPathComponent(path), to: root.appendingPathComponent(destination))
                    paths.remove(path)
                    paths.insert(destination)
                }
            }
            try index.refresh(vaultRoot: root)
            try equivalent(index, root)
        }
    }
}

@Test func singleChangeInThousandFilesPerformance() throws {
    try withVault { root in
        for number in 0..<1000 {
            try write(root, "notes/Su \(number).md", "- [ ] Kitap ^task\(number)\n[[Su 0]]\nSu Spor")
        }
        let index = try VaultIndex()
        let clock = ContinuousClock()
        let full = try clock.measure { try index.rebuild(vaultRoot: root) }
        try write(root, "notes/Su 500.md", "- [x] Kitap ^task500\n[[Su 0]]\nSu Spor")
        let incremental = try clock.measure {
            let result = try index.refresh(vaultRoot: root)
            #expect(result.updatedPaths == ["notes/Su 500.md"])
        }
        try equivalent(index, root)
        print("INDEX_PERFORMANCE files=1000 rebuild=\(full) refresh=\(incremental)")
    }
}
