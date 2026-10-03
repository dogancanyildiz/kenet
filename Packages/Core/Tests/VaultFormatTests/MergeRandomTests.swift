import Testing
import VaultFormat

/// The merge contract on random pairs: two edits of a common ancestor, and arbitrary bytes.
struct MergeRandomTests {
    @Test func editsOfACommonAncestorMergeWithoutLoss() {
        var random = SeededGenerator(seed: 0x4D45_5247)
        var preservedCount = 0
        var fallbacks = 0
        for iteration in 0..<1500 {
            let ancestor = MergeSampleDay.ancestor(using: &random)
            let a = MergeSampleDay.edited(ancestor, using: &random, tag: "a\(iteration)")
            let b = MergeSampleDay.edited(ancestor, using: &random, tag: "b\(iteration)")
            let times = random.next() % 4 == 0 ? (3, 3) : (Int(random.next() % 10), Int(random.next() % 10))
            let result = check(
                MergeVersion(bytes: a, modificationTime: times.0), MergeVersion(bytes: b, modificationTime: times.1),
                label: "iteration \(iteration)")
            if !result.preserved.isEmpty { preservedCount += 1 }
            if result.fellBack { fallbacks += 1 }
        }
        // The generator must produce both clean merges and conflicts, or the test proves little.
        #expect(preservedCount > 100 && preservedCount < 1400, "\(preservedCount) merges preserved a version")
        // With every code fence closed, the last guard must never have to step in.
        #expect(fallbacks == 0, "\(fallbacks) merges fell back")
    }

    @Test func unclosedFencesAreTheOnlyReasonToFallBack() {
        var random = SeededGenerator(seed: 0x4645_4E43)
        var fallbacks = 0
        let count = 1500
        for iteration in 0..<count {
            let ancestor = MergeSampleDay.ancestor(using: &random)
            let a = MergeSampleDay.edited(ancestor, using: &random, tag: "a\(iteration)", unclosedFences: true)
            let b = MergeSampleDay.edited(ancestor, using: &random, tag: "b\(iteration)", unclosedFences: true)
            let result = check(
                MergeVersion(bytes: a, modificationTime: 1), MergeVersion(bytes: b, modificationTime: 2),
                label: "fences \(iteration)")
            if result.fellBack {
                fallbacks += 1
                let fence = Array("```".utf8)
                let hasFence = [a, b].contains { bytes in bytes.indices.contains { bytes[$0...].starts(with: fence) } }
                #expect(hasFence, "fences \(iteration): fell back without a fence")
            }
        }
        // The fallback path itself is covered by the `unclosed-fence-falls-back` fixture.
        #expect(fallbacks * 100 <= count, "\(fallbacks) of \(count) merges fell back")
    }

    @Test func arbitraryBytesNeverCrashAndNeverLoseContent() {
        var random = SeededGenerator(seed: 0x4241_5954)
        for iteration in 0..<600 {
            let a = MergeSampleDay.garbage(using: &random)
            let b =
                random.next() % 3 == 0
                ? MergeSampleDay.garbage(using: &random) : MergeSampleDay.mutated(a, using: &random)
            check(
                MergeVersion(bytes: a, modificationTime: Int(random.next() % 3)),
                MergeVersion(bytes: b, modificationTime: Int(random.next() % 3)), label: "garbage \(iteration)")
        }
    }

    /// Checks every property of the contract on one pair and returns the merge.
    @discardableResult
    private func check(_ a: MergeVersion, _ b: MergeVersion, label: String) -> MergeResult {
        let result = ConflictMerge.merge(a, b)
        #expect(ConflictMerge.merge(b, a) == result, "\(label): order of arguments")
        #expect(ConflictMerge.merge(a, b) == result, "\(label): determinism")
        #expect(RawDocument(bytes: result.bytes).serialized() == result.bytes, "\(label): round trip")
        #expect(losslessViolations(of: result.bytes) == [], "\(label): round trip")

        let later = MergeVersion(bytes: result.bytes, modificationTime: max(a.modificationTime, b.modificationTime) + 1)
        #expect(
            ConflictMerge.merge(later, a).bytes == result.bytes,
            "\(label): re-merge with a\n\(visible(a.bytes))\n--- b\n\(visible(b.bytes))\n--- result\n\(visible(result.bytes))\n--- re-merged\n\(visible(ConflictMerge.merge(later, a).bytes))"
        )
        #expect(
            ConflictMerge.merge(later, b).bytes == result.bytes,
            "\(label): re-merge with b\n\(visible(a.bytes))\n--- b\n\(visible(b.bytes))\n--- result\n\(visible(result.bytes))\n--- re-merged\n\(visible(ConflictMerge.merge(later, b).bytes))"
        )

        for (name, version) in [("a", a), ("b", b)] {
            let violations = MergeLossCheck.violations(
                version: version.bytes, result: result.bytes, isPreserved: result.preserved.contains(version))
            #expect(
                violations == [],
                "\(label): \(name) loses \(violations)\n\(visible(a.bytes))\n--- b\n\(visible(b.bytes))\n--- result\n\(visible(result.bytes))"
            )
        }
        let ordered = result.preserved.map(\.modificationTime)
        #expect(ordered == ordered.sorted(), "\(label): preserved versions are reported older first")
        return result
    }
}
