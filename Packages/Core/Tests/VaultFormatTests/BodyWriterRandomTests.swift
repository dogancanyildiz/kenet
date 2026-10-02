import Testing
import VaultFormat

struct BodyWriterRandomTests {
    @Test func validRandomOperationsMustSucceedUnlessBlankWouldFuse() throws {
        var random = SeededGenerator(seed: 0x501)
        var successes = 0
        var fusionRejections = 0
        for iteration in 0..<2000 {
            let before = makeDocument(using: &random)
            var attempt = ""
            do {
                let body = before.bodyLines
                let op = Int(random.next() % 6)
                attempt = "op=\(op)"
                let newID = random.next() % 2 == 0 ? "edited\(iteration)" : nil
                let text = ["Kitap", " \tSu\t ", "Spor", "[[Deniz Arıkan]]"][Int(random.next() % 4)]
                var target: LineBlock?
                var desiredText: String?
                var desiredID: String?
                var desiredTime: EventTime?
                var desiredStatus: String?
                let after: RawDocument
                func checked(
                    _ apply: () throws -> RawDocument, changes: [ReferenceEdit.Replacement]
                ) throws -> RawDocument? {
                    let expectedCount =
                        before.lines.count + changes.reduce(0) { $0 + $1.contents.count - $1.range.count }
                    let bytes = ReferenceEdit.bytes(before.serialized(), applying: changes)
                    if ReferenceModel.lines(bytes).count != expectedCount {
                        fusionRejections += 1
                        #expect { try apply() } throws: { ($0 as? EditError) == .contentNotRepresentable }
                        return nil
                    }
                    return try apply()
                }
                switch op {
                case 0:
                    let clock = try LineClock(hour: Int(random.next() % 24), minute: 5)
                    let position = eventPosition(before, clock: clock)
                    guard
                        let result = try checked(
                            { try before.addingEvent(text: text, id: "new123", time: clock) },
                            changes: [.init(range: position..<position, contents: [Array("- Kitap".utf8)])])
                    else { continue }
                    after = result
                    desiredText = text == " \tSu\t " ? "Su" : text
                    desiredID = "new123"
                    desiredTime = after.bodyLines.events.first { $0.block.id == "new123" }?.time
                    #expect(desiredTime?.hour == clock.hour && desiredTime?.minute == clock.minute)
                case 1:
                    let section = before.daySections.section(.tasks)!
                    let position =
                        section.lineRange.last { !before.lines[$0].content.allSatisfy { $0 == 32 || $0 == 9 } }! + 1
                    guard
                        let result = try checked(
                            { try before.addingTask(text: text, id: "new123") },
                            changes: [.init(range: position..<position, contents: [Array("- [ ] Kitap".utf8)])])
                    else { continue }
                    after = result
                    desiredText = text == " \tSu\t " ? "Su" : text
                    desiredID = "new123"
                    desiredStatus = " "
                case 2:
                    let blocks = body.events.map(\.block) + body.tasks.map(\.block)
                    target = blocks[Int(random.next() % UInt64(blocks.count))]
                    after = try before.changingText(of: target!, to: text, newID: newID)
                    desiredText = text == " \tSu\t " ? "Su" : text
                    desiredID = newID ?? target!.id
                    desiredTime = body.events.first { $0.block == target }?.time
                    desiredStatus = body.tasks.first { $0.block == target }?.rawStatus
                case 3:
                    let event = body.events[Int(random.next() % UInt64(body.events.count))]
                    target = event.block
                    let clock = try random.next() % 2 == 0 ? nil : LineClock(hour: Int(random.next() % 24), minute: 5)
                    var changes: [ReferenceEdit.Replacement] = []
                    if let clock, event.time?.hour != clock.hour || event.time?.minute != clock.minute {
                        let position = eventPosition(before, clock: clock, excluding: event.block)
                        let range = event.block.lineRange
                        let between =
                            position < range.lowerBound
                            ? position..<range.lowerBound : range.upperBound..<max(range.upperBound, position)
                        if !before.lines[between].allSatisfy({ $0.content.allSatisfy { $0 == 32 || $0 == 9 } }) {
                            changes = [
                                .init(range: range, contents: []),
                                .init(range: position..<position, contents: before.lines[range].map(\.content)),
                            ]
                        }
                    }
                    guard
                        let result = try checked(
                            { try before.changingTime(of: event, to: clock, newID: newID) }, changes: changes)
                    else { continue }
                    after = result
                    desiredText = event.block.text
                    desiredID = newID ?? event.block.id
                    let written = after.bodyLines.events.first { $0.block.id == desiredID }
                    #expect(written?.time?.hour == clock?.hour && written?.time?.minute == clock?.minute)
                    desiredTime = written?.time
                case 4:
                    let blocks = body.events.map(\.block) + body.tasks.map(\.block)
                    target = blocks[Int(random.next() % UInt64(blocks.count))]
                    guard
                        let result = try checked(
                            { try before.deletingBlock(target!) },
                            changes: [.init(range: target!.lineRange, contents: [])])
                    else { continue }
                    after = result
                default:
                    let task = body.tasks[Int(random.next() % UInt64(body.tasks.count))]
                    target = task.block
                    let status = [TaskStatus.todo, .inProgress, .done, .cancelled][Int(random.next() % 4)]
                    after = try before.changingStatus(of: task, to: status, newID: newID)
                    desiredText = task.block.text
                    desiredID = newID ?? task.block.id
                    let raw = [TaskStatus.todo: " ", .inProgress: "/", .done: "x", .cancelled: "-"]
                    desiredStatus = task.status == status ? task.rawStatus : raw[status]
                }
                successes += 1
                #expect(after == RawDocument(bytes: after.serialized()))
                #expect(after.frontmatter == before.frontmatter && after.hasByteOrderMark == before.hasByteOrderMark)
                #expect(after.daySections.sections.map(\.kind) == before.daySections.sections.map(\.kind))
                func excluded(_ block: LineBlock) -> Bool {
                    if op == 4, let target { return target.lineRange.contains(block.line) }
                    return block == target
                }
                let retainedEvents = body.events.filter { !excluded($0.block) }
                let retainedTasks = body.tasks.filter { !excluded($0.block) }
                let newEvents = after.bodyLines.events.filter { $0.block.id != desiredID }
                let newTasks = after.bodyLines.tasks.filter { $0.block.id != desiredID }
                #expect(
                    retainedEvents.map { signature($0.block, time: $0.time?.raw) }
                        == newEvents.map { signature($0.block, time: $0.time?.raw) }, "iteration \(iteration)")
                #expect(
                    retainedTasks.map { signature($0.block, time: $0.rawStatus) }
                        == newTasks.map { signature($0.block, time: $0.rawStatus) }, "iteration \(iteration)")
                if let desiredID {
                    let written = (after.bodyLines.events.map(\.block) + after.bodyLines.tasks.map(\.block)).first {
                        $0.id == desiredID
                    }
                    #expect(written?.text == desiredText)
                    #expect(written?.lineRange.count == target?.lineRange.count ?? 1)
                    #expect(after.bodyLines.events.first { $0.block.id == desiredID }?.time == desiredTime)
                    #expect(after.bodyLines.tasks.first { $0.block.id == desiredID }?.rawStatus == desiredStatus)
                }
                let operation = ["add-event", "add-task", "text", "time", "delete", "status"][op]
                BodyOperation.checkUntouched(
                    before, after,
                    json: .object([
                        "operation": .string(operation), "line": .integer((target?.line ?? -1) + 1),
                    ]))
            } catch {
                print("Failed valid random iteration \(iteration), \(attempt): \(visible(before.serialized()))")
                throw error
            }
        }
        #expect(successes > 0 && fusionRejections > 0 && successes + fusionRejections == 2000)
        print(
            "Random operations: \(successes) successes, \(fusionRejections) independently predicted blank-fusion rejections"
        )
    }

    @Test func knownInvalidRandomOperationsAreRefusedForTheirReason() throws {
        var random = SeededGenerator(seed: 0xBAD)
        for _ in 0..<300 {
            let choices: [(String, EditError)] = [
                ("", .emptyText), (" \t", .emptyText), ("Su\nKitap", .lineBreakInContent),
                ("Su\rKitap", .lineBreakInContent), ("14:30 toplantı", .contentNotRepresentable),
                ("[ ] x", .contentNotRepresentable), ("Su ^abc123", .contentNotRepresentable),
            ]
            let (text, error) = choices[Int(random.next() % UInt64(choices.count))]
            let before = RawDocument(bytes: Array("## Events\n- Su\n".utf8))
            #expect { try before.changingText(of: before.bodyLines.events[0].block, to: text) } throws: {
                ($0 as? EditError) == error
            }
            #expect(before.serialized() == Array("## Events\n- Su\n".utf8))
            if random.next() % 3 == 0 {
                let fenced = RawDocument(bytes: Array("## Events\n```\nSu\n".utf8))
                #expect { try fenced.addingEvent(text: "Kitap", id: "abc123") } throws: {
                    ($0 as? EditError) == .contentNotRepresentable
                }
            }
        }
    }

    /// Test-side reference placement; fusion is then predicted from independently assembled bytes.
    private func eventPosition(_ document: RawDocument, clock: LineClock, excluding target: LineBlock? = nil) -> Int {
        if let next = document.bodyLines.events.first(where: {
            $0.block != target && $0.time.map { $0.hour * 60 + $0.minute > clock.hour * 60 + clock.minute } == true
        }) {
            return next.block.line
        }
        return document.daySections.section(.events)!.lineRange.last {
            target?.lineRange.contains($0) != true && !document.lines[$0].content.allSatisfy { $0 == 32 || $0 == 9 }
        }! + 1
    }

    private func makeDocument(using random: inout SeededGenerator) -> RawDocument {
        var contents = [
            "## Tasks", "- [ ] Su ^parent", "  - [/] Kitap ^child", "> *  [X] Spor ^quote", "", "## Events",
        ]
        for index in 0..<Int(random.next() % 6 + 1) {
            let marker = ["- ", "*    ", "+  "][Int(random.next() % 3)]
            let time = random.next() % 2 == 0 ? "" : "9:05 "
            let text = random.next() % 3 == 0 ? "" : "Su "
            contents.append(marker + time + text + "^id\(index)")
            if random.next() % 2 == 0 { contents.append("  Kitap") }
            if random.next() % 2 == 0 { contents.append("") }
        }
        contents += ["## Journal", "Spor"]
        var bytes: [UInt8] = []
        for (index, content) in contents.enumerated() {
            bytes += Array(content.utf8)
            if index < contents.count - 1 || random.next() % 2 == 0 {
                bytes += [[UInt8]("\n".utf8), Array("\r\n".utf8), Array("\r".utf8)][Int(random.next() % 3)]
            }
        }
        if random.next() % 3 == 0 { bytes = RawDocument.byteOrderMark + bytes }
        return RawDocument(bytes: bytes)
    }

    private func signature(_ block: LineBlock, time: String?) -> [[UInt8]] {
        [Array(block.text.utf8), Array((block.id ?? "").utf8), Array((time ?? "").utf8)]
    }
}
