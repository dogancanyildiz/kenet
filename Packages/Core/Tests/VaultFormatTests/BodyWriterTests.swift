import Testing
import VaultFormat

struct BodyWriterTests {
    @Test func generatedIDsRetryAndRemainBounded() throws {
        var random = SeededGenerator(seed: 501)
        var reference = SeededGenerator(seed: 501)
        let first = try BlockIDGenerator.generate(using: &reference, isTaken: { _ in false })
        let second = try BlockIDGenerator.generate(using: &reference, isTaken: { _ in false })
        var queries: [String] = []
        let actual = try BlockIDGenerator.generate(using: &random) {
            queries.append($0)
            return $0 == first
        }
        #expect(queries == [first, second])
        #expect(actual == second)
        for _ in 0..<1000 {
            let id = try BlockIDGenerator.generate(using: &random, isTaken: { _ in false })
            #expect(id.utf8.count == 6)
            #expect(id.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) })
        }
        var calls = 0
        #expect {
            try BlockIDGenerator.generate(using: &random, attempts: 3) { _ in
                calls += 1
                return true
            }
        } throws: { ($0 as? EditError) == .identifierExhausted }
        #expect(calls == 3)
    }

    @Test func sampleEventsKeepTheirBytesAndOrder() throws {
        let appendExceptions: Set<String> = ["ogyr3x", "5fdhjk", "tgiqhg", "9ahej8"]
        var observed: Set<String> = []
        for path in try Fixtures.markdownPaths(in: "vaults/sample/journal") {
            let before = RawDocument(bytes: try Fixtures.bytes(at: path))
            for event in before.bodyLines.events {
                #expect(
                    try before.changingText(of: event.block, to: event.block.text).serialized() == before.serialized())
                let deleted = try before.deletingBlock(event.block)
                let time = try event.time.map { try LineClock(hour: $0.hour, minute: $0.minute) }
                let restored = try deleted.addingEvent(
                    text: event.block.text, id: try #require(event.block.id), time: time)
                if let id = event.block.id, appendExceptions.contains(id) {
                    observed.insert(id)
                    let values = eventValues(before)
                    let expected = values.filter { $0[1] != id } + values.filter { $0[1] == id }
                    #expect(eventValues(restored) == expected)
                } else {
                    #expect(eventValues(restored) == eventValues(before), "\(path), line \(event.block.line + 1)")
                }
            }
        }
        #expect(observed == appendExceptions)
    }

    @Test func staleValuesAndRangesNeverEditAnotherBlock() throws {
        let before = document("## Events\n- 9:05 Su ^aaa111\n  Kitap\n- Spor ^bbb222\n")
        let event = try #require(before.bodyLines.events.first)
        let changed = try before.changingText(of: event.block, to: "Kitap")
        #expect { try changed.deletingBlock(event.block) } throws: { ($0 as? EditError) == .targetNotFound }
        let retimed = try before.changingTime(of: event, to: LineClock(hour: 10, minute: 0))
        #expect { try retimed.changingTime(of: event, to: nil) } throws: { ($0 as? EditError) == .targetNotFound }
        let shortened = document("## Events\n- 9:05 Su ^aaa111\n- Spor ^bbb222\n")
        #expect { try shortened.changingText(of: event.block, to: "Kitap") } throws: {
            ($0 as? EditError) == .targetNotFound
        }
        let differentID = try before.changingText(of: event.block, to: "Su", newID: "new123")
        #expect { try differentID.deletingBlock(event.block) } throws: { ($0 as? EditError) == .targetNotFound }
        let decomposed = document("## Events\n- e\u{301} ^aaa111\n")
        let composed = document("## Events\n- é ^aaa111\n")
        #expect { try composed.deletingBlock(decomposed.bodyLines.events[0].block) } throws: {
            ($0 as? EditError) == .targetNotFound
        }
    }

    @Test func suppliedIdentifierDoesNotHideTextAmbiguity() throws {
        let before = document("## Events\n- Su\n")
        let event = before.bodyLines.events[0]
        #expect { try before.changingText(of: event.block, to: "14:30 toplantı", newID: "abc123") } throws: {
            ($0 as? EditError) == .contentNotRepresentable
        }
        #expect(
            try before.changingText(of: event.block, to: "Su ^other", newID: "abc123").bodyLines.events[0].block.text
                == "Su ^other")
    }

    private func document(_ text: String) -> RawDocument { RawDocument(bytes: Array(text.utf8)) }

    private func eventValues(_ document: RawDocument) -> [[String]] {
        document.bodyLines.events.map {
            [$0.block.text, $0.block.id ?? "", $0.time.map { "\($0.hour):\($0.minute)" } ?? ""]
        }
    }
}
