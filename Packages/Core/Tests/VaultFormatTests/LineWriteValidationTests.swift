import Testing

@testable import VaultFormat

struct LineWriteValidationTests {
    @Test func rejectsChangedUntargetedContent() {
        reject("## Events\nSu\n", "## Events\nKitap\n")
    }

    @Test func rejectsChangedUntargetedTerminator() {
        reject("## Events\nSu\n", "## Events\nSu\r\n")
    }

    @Test func rejectsWrongLineCount() {
        reject("## Events\nSu\n", "## Events\nSu\nKitap\n", origins: [0, 1])
    }

    @Test func rejectsChangedSectionOwnership() {
        reject(
            "## Events\nSu\n## Journal\nKitap\n", "## Events\nKitap\n## Journal\nSu\n",
            origins: [0, 3, 2, 1], error: .sectionNotWritable)
    }

    @Test func rejectsChangedSectionCount() {
        reject("## Events\n## Journal\n", "## Events\n", origins: [0], error: .sectionNotWritable)
    }

    @Test func rejectsChangedBOM() {
        reject("## Events\nSu\n", "\u{FEFF}## Events\nSu\n", error: .sectionNotWritable)
    }

    @Test func rejectsChangedFrontmatter() {
        reject(
            "---\nname: Su\n---\n## Events\n", "---\nname: Kitap\n---\n## Events\n",
            changedLine: 1, error: .sectionNotWritable)
    }

    @Test func rejectsShiftedFenceBoundaries() {
        let fence = "      ```\n      [[Deniz Arıkan]]\n      ```\n"
        let original = "## Events\n-    Su ^a\n" + fence
        let damaged = "## Events\n- Su ^a\n" + fence
        #expect(document(original).links.isEmpty)
        #expect(document(damaged).links.count == 1)
        rejectTarget(original, damaged)
    }

    @Test func rejectsChangedEOFFenceBoundary() {
        reject("## Events\nSu\n", "## Events\nSu\n```\n", origins: [0, 1, nil])
    }

    @Test func rejectsWrongTaskStatus() {
        rejectTarget("## Tasks\n- [ ] Su ^a\n", "## Tasks\n- [/] Su ^a\n")
    }

    @Test func rejectsWrongEventTime() {
        rejectTarget("## Events\n- 09:00 Su ^a\n", "## Events\n- 10:00 Su ^a\n")
    }

    @Test func rejectsWrongBlockType() {
        rejectTarget("## Events\n- Su ^a\n", "## Events\n- [ ] Su ^a\n")
    }

    @Test func rejectsWrongTargetTextAndIdentifier() {
        rejectTarget("## Events\n- Su ^a\n", "## Events\n- Kitap ^a\n")
        rejectTarget("## Events\n- Su ^a\n", "## Events\n- Su ^b\n")
    }

    @Test func typedAPIsRefuseForgedTargets() throws {
        let eventDoc = document("## Events\n- Su ^a\n")
        let event = eventDoc.bodyLines.events[0]
        let forgedTask = TaskLine(block: event.block, rawStatus: " ", status: .todo)
        #expect { try eventDoc.changingStatus(of: forgedTask, to: .done) } throws: {
            ($0 as? EditError) == .targetNotFound
        }
        let taskDoc = document("## Tasks\n- [ ] Su ^a\n")
        let forgedEvent = EventLine(
            block: taskDoc.bodyLines.tasks[0].block, time: EventTime(hour: 9, minute: 0, raw: "09:00"))
        #expect { try taskDoc.changingTime(of: forgedEvent, to: LineClock(hour: 9, minute: 0)) } throws: {
            ($0 as? EditError) == .targetNotFound
        }
    }

    private func rejectTarget(_ source: String, _ damaged: String) {
        let before = document(source)
        let target = WrittenBlock.all(before)[0]
        reject(source, damaged, target: target.block, desired: target, changedLine: target.block.line)
    }

    private func reject(
        _ source: String, _ damaged: String, origins: [Int?]? = nil, target: LineBlock? = nil,
        desired: WrittenBlock? = nil, changedLine: Int? = nil, error: EditError = .contentNotRepresentable
    ) {
        let before = document(source)
        #expect {
            try before.validatingLines(
                document(damaged), origins: origins ?? before.lines.indices.map { $0 },
                target: target, desired: desired, changedLine: changedLine)
        } throws: { ($0 as? EditError) == error }
    }

    private func document(_ text: String) -> RawDocument { RawDocument(bytes: Array(text.utf8)) }
}
