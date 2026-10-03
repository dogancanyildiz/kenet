import Testing

@testable import VaultFormat

/// The merge's last guard, exercised directly with results the merge itself would never build,
/// so that a disabled branch of the guard shows even while the merge is correct.
struct LossCheckTests {
    private func document(_ text: String) -> RawDocument { RawDocument(bytes: Array(text.utf8)) }

    /// Whether the guard accepts `result` as the merge of `newer` and `older` with nothing preserved.
    private func passes(result: String, newer: String, older: String) -> Bool {
        let merged = document(result)
        let body = MergeBody(merged)
        let regions = body.regions.indices.map { index in
            MergedRegion(
                key: body.regions[index].key, kind: body.regions[index].kind, olderIndex: nil,
                entries: RegionMerge.entries(of: index, in: body, dropping: []))
        }
        return LossCheck.passes(
            result: merged, frontmatterLineCount: merged.frontmatterLineRange?.count ?? 0, built: MergedBody(regions),
            newer: document(newer), older: document(older), preserved: Preservation())
    }

    @Test func acceptsAResultThatHoldsEverything() {
        #expect(passes(result: "## Journal\nA\nB\n", newer: "## Journal\nA\nB\n", older: "## Journal\nA\n"))
    }

    @Test func rejectsAMissingFreeTextLine() {
        #expect(!passes(result: "## Journal\nA\n", newer: "## Journal\nA\n", older: "## Journal\nA\nB\n"))
    }

    @Test func rejectsFreeTextMovedToAnotherRegion() {
        #expect(
            !passes(
                result: "## Journal\n\n## Notlar\nA\n", newer: "## Journal\n\n## Notlar\nA\n", older: "## Journal\nA\n")
        )
    }

    @Test func rejectsFreeTextThatLostARepetition() {
        #expect(!passes(result: "## Journal\nA\n", newer: "## Journal\nA\n", older: "## Journal\nA\nA\n"))
    }

    @Test func rejectsBlockOrFrontmatterLinesStandingInForFreeText() {
        let eventElsewhere = "## Events\n- 09:00 A\n\n## Journal\n"
        #expect(!passes(result: eventElsewhere, newer: eventElsewhere, older: "## Journal\n- 09:00 A\n"))
        let inFrontmatter = "---\ntype: journal\n---\n## Journal\n"
        #expect(!passes(result: inFrontmatter, newer: inFrontmatter, older: "## Journal\ntype: journal\n"))
    }

    @Test func acceptsAClosedTaskInPlaceOfAnOpenOneWithTheSameText() {
        #expect(
            passes(result: "- [x] Su ✅ 2026-09-21 ^a\n", newer: "- [x] Su ✅ 2026-09-21 ^a\n", older: "- [ ] Su ^a\n"))
        #expect(
            !passes(
                result: "- [x] Su iç ✅ 2026-09-21 ^a\n", newer: "- [x] Su iç ✅ 2026-09-21 ^a\n", older: "- [ ] Su ^a\n")
        )
    }

    @Test func rejectsAStatusChangeBetweenOpenOrBetweenClosedTasks() {
        #expect(!passes(result: "- [/] Su ^a\n", newer: "- [/] Su ^a\n", older: "- [ ] Su ^a\n"))
        #expect(!passes(result: "- [x] Su ^a\n", newer: "- [x] Su ^a\n", older: "- [-] Su ^a\n"))
        #expect(
            passes(
                result: "- [x] Su ✅ 2026-09-21 ^a\n", newer: "- [x] Su ✅ 2026-09-21 ^a\n",
                older: "- [x] Su ✅ 2026-09-20 ^a\n"))
    }

    @Test func goalsMustHaveProgressed() {
        #expect(
            passes(
                result: "---\ngoals:\n  kitap: 30\n---\n", newer: "---\ngoals:\n  kitap: 30\n---\n",
                older: "---\ngoals:\n  kitap: 20\n---\n"))
        #expect(
            !passes(
                result: "---\ngoals:\n  kitap: 20\n---\n", newer: "---\ngoals:\n  kitap: 20\n---\n",
                older: "---\ngoals:\n  kitap: 30\n---\n"))
        #expect(
            !passes(
                result: "---\ngoals:\n  spor: false\n---\n", newer: "---\ngoals:\n  spor: false\n---\n",
                older: "---\ngoals:\n  spor: true\n---\n"))
    }

    @Test func frontmatterCommentsMustSurvive() {
        #expect(
            !passes(
                result: "---\ntype: journal\n---\n", newer: "---\ntype: journal\n---\n",
                older: "---\n# not\ntype: journal\n---\n"))
        #expect(
            !passes(result: "---\nmood: iyi\n---\n", newer: "---\nmood: iyi\n---\n", older: "---\nmood: iyi # c\n---\n")
        )
        #expect(
            passes(
                result: "---\nmood: iyi # c\n---\n", newer: "---\nmood: iyi # c\n---\n",
                older: "---\nmood: \"iyi\" # c\n---\n"))
    }

    @Test func differingFrontmatterValueIsALoss() {
        #expect(
            !passes(result: "---\nmood: iyi\n---\n", newer: "---\nmood: iyi\n---\n", older: "---\nmood: yorgun\n---\n"))
    }
}
