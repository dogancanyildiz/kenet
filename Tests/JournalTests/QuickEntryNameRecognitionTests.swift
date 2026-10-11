import DateParsing
import EntityRecognition
import Foundation
import Testing
import VaultFormat

@testable import Journal

/// Undoing a recognized name: the occurrence stays plain words, is not linked and is not asked about.
@MainActor
struct QuickEntryNameRecognitionTests {
    private static func eventModel(_ context: TaskTestContext) -> QuickEntryModel {
        let date = context.today
        let model = QuickEntryModel(store: context.store, day: date, today: { date })
        model.languages = [.turkish, .english]
        return model
    }

    private static func bytes(of range: Range<Int>, in model: QuickEntryModel) -> String {
        String(decoding: Array(model.text.utf8)[range], as: UTF8.self)
    }

    private static func undo(_ spelling: String, occurrence: Int = 0, in model: QuickEntryModel) throws {
        let names = model.recognizedNames.filter { $0.spelling == spelling }
        try #require(names.count > occurrence)
        model.undoRecognition(names[occurrence])
    }

    private static var one: LineClock { get throws { try LineClock(hour: 13, minute: 0) } }

    @Test func withoutAnUndoEveryNameHasAChipAndTheLineIsUnchanged() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = Self.eventModel(context)
        model.text = "Deniz ile Liman Ofis'te"
        #expect(model.recognizedNames.map(\.spelling) == ["Deniz", "Liman Ofis"])
        #expect(model.recognizedNames.map(\.kind) == [.person, .place])
        #expect(try await model.submit(time: Self.one))
        let id = try #require(context.document().bodyLines.events.first?.block.id)
        #expect(
            try Data(contentsOf: context.file)
                == Data(
                    "---\ntype: journal\ndate: 2026-10-03\n---\n\n## Events\n- 13:00 [[Deniz Arıkan|Deniz]] ile [[Liman Ofis]]'te ^\(id)\n"
                        .utf8))
        #expect(model.suppressedNames.isEmpty && model.recognizedNames.isEmpty)
    }

    @Test func undoneEventNameIsWrittenPlainWithItsSuffixAndTheOtherOccurrenceIsLinked() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = Self.eventModel(context)
        model.text = "Deniz'le kahve, sonra Deniz'i ara"
        #expect(model.recognizedNames.map(\.spelling) == ["Deniz", "Deniz"])
        try Self.undo("Deniz", occurrence: 0, in: model)
        #expect(model.suppressedNames == [0..<5])
        #expect(
            model.recognizedNames.map(\.byteRange) == [
                "Deniz'le kahve, sonra ".utf8.count..<"Deniz'le kahve, sonra Deniz".utf8.count
            ])
        #expect(try await model.submit(time: Self.one))
        let id = try #require(context.document().bodyLines.events.first?.block.id)
        #expect(
            try Data(contentsOf: context.file)
                == Data(
                    "---\ntype: journal\ndate: 2026-10-03\n---\n\n## Events\n- 13:00 Deniz'le kahve, sonra [[Deniz Arıkan|Deniz]]'i ara ^\(id)\n"
                        .utf8))
    }

    /// Only the occurrence the chip named stays plain: undoing the second leaves the first linked.
    @Test func undoneTaskNameIsTheOccurrenceTheChipNamed() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.mode = .task
        model.text = "yarın Deniz'e sor, Deniz'le git"
        #expect(model.taskExpressions.map(\.spelling) == ["yarın"])
        #expect(model.recognizedNames.map(\.spelling) == ["Deniz", "Deniz"])
        try Self.undo("Deniz", occurrence: 1, in: model)
        #expect(model.suppressedNames.map { Self.bytes(of: $0, in: model) } == ["Deniz"])
        #expect(await model.submit(time: nil))
        let id = try #require(context.document().bodyLines.tasks.first?.block.id)
        #expect(
            try Data(contentsOf: context.file)
                == Data(
                    "---\ntype: journal\ndate: 2026-10-03\n---\n\n## Tasks\n- [ ] [[Deniz Arıkan|Deniz]]'e sor, Deniz'le git 📅 2026-10-04 ^\(id)\n"
                        .utf8))
        #expect(model.text.isEmpty && model.suppressedNames.isEmpty && model.suppressedExpressions.isEmpty)
    }

    @Test func undoneAmbiguousNameIsNotAskedAbout() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = Self.eventModel(context)
        model.text = "Mert Aksu ile Ece"
        let names = model.recognizedNames
        #expect(names.map(\.spelling) == ["Mert Aksu", "Ece"] && names.map(\.isAmbiguous) == [true, false])
        try Self.undo("Mert Aksu", in: model)
        #expect(model.composer.beginResolution())
        #expect(model.pendingAmbiguity == nil && model.pendingUnknown == nil)
        model.awaitingResolution = false
        #expect(try await model.submit(time: Self.one))
        #expect(try context.document().bodyLines.events.map(\.block.text) == ["Mert Aksu ile [[Ece Yalın|Ece]]"])
    }

    /// The same text without the undo asks, so the test above proves the undo and not the vault.
    @Test func withoutTheUndoTheAmbiguousNameIsAskedAbout() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = Self.eventModel(context)
        model.text = "Mert Aksu ile Ece"
        #expect(try await !model.submit(time: Self.one))
        #expect(model.pendingAmbiguity?.spelling == "Mert Aksu")
    }

    /// Of two ambiguous occurrences the one not undone is still asked about; the strip's choice
    /// pins it, which takes its chip away, and the undone one stays plain.
    @Test func theAmbiguousOccurrenceNotUndoneIsStillAskedAndItsChoiceHasNoChip() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = Self.eventModel(context)
        model.text = "Mert Aksu ile Mert Aksu"
        #expect(model.recognizedNames.map(\.isAmbiguous) == [true, true])
        try Self.undo("Mert Aksu", occurrence: 1, in: model)
        #expect(try await !model.submit(time: Self.one))
        let asked = try #require(model.pendingAmbiguity)
        #expect(model.globalRange(asked.position) == 0..<"Mert Aksu".utf8.count)
        model.choose(try #require(asked.candidates.first { $0.qualifier == "iş" }), for: asked)
        #expect(model.recognizedNames.isEmpty)
        #expect(try await model.submit(time: Self.one))
        #expect(
            try context.document().bodyLines.events.map(\.block.text) == [
                "[[Mert Aksu (iş)|Mert Aksu]] ile Mert Aksu"
            ])
    }

    /// A bare name has no "add as person" question; an undone one next to an unknown `@` name
    /// leaves that question about the unknown name only.
    @Test func undoneNameLeavesOnlyTheUnknownNameQuestion() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = Self.eventModel(context)
        model.text = "Mert Aksu ve @Yeni Kişi"
        try Self.undo("Mert Aksu", in: model)
        #expect(try await !model.submit(time: Self.one))
        #expect(model.pendingAmbiguity == nil && model.pendingUnknown?.spelling == "Yeni Kişi")
        model.dismissUnknown(try #require(model.pendingUnknown))
        // Deleting the `@` moved the text after the undone name, not the name itself.
        #expect(model.suppressedNames.map { Self.bytes(of: $0, in: model) } == ["Mert Aksu"])
        #expect(try await model.submit(time: Self.one))
        #expect(try context.document().bodyLines.events.map(\.block.text) == ["Mert Aksu ve Yeni Kişi"])
    }

    @Test func explicitMentionGetsNoChipAndIsLinked() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = Self.eventModel(context)
        model.text = "@Deniz ile Ece"
        #expect(model.recognizedNames.map(\.spelling) == ["Ece"])
        try Self.undo("Ece", in: model)
        #expect(model.recognizedNames.isEmpty)
        #expect(try await model.submit(time: Self.one))
        #expect(try context.document().bodyLines.events.map(\.block.text) == ["[[Deniz Arıkan|Deniz]] ile Ece"])
    }

    /// Writing `@` in front of an undone name asks for the link: it is linked and has no chip.
    @Test func anAtSignOnAnUndoneNameLinksIt() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = Self.eventModel(context)
        model.text = "Deniz geldi"
        try Self.undo("Deniz", in: model)
        model.text = "@Deniz geldi"
        #expect(model.suppressedNames == [1..<6])
        #expect(model.recognizedNames.isEmpty)
        #expect(try await model.submit(time: Self.one))
        #expect(try context.document().bodyLines.events.map(\.block.text) == ["[[Deniz Arıkan|Deniz]] geldi"])
    }

    /// A suggestion, a calendar attendee and a nearby place pin their name: the user chose it.
    @Test func pinnedNamesGetNoChip() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = Self.eventModel(context)
        model.text = "@Mert"
        let entity = try #require(model.suggestions().first { $0.qualifier == "iş" })
        model.selectSuggestion(entity)
        #expect(model.text == "Mert Aksu" && model.recognizedNames.isEmpty)

        model.text = ""
        var event = CalendarEvent(
            id: "e", title: "Ece ile plan", start: Date(), end: Date().addingTimeInterval(3600), isAllDay: false,
            color: CalendarEventColor(red: 0, green: 0, blue: 0, alpha: 1))
        event.attendees = [Attendee(name: "Deniz Arıkan"), Attendee(name: "Ada Soylu")]
        #expect(model.applyCalendarDraft(event))
        #expect(model.text == "Ece ile plan @Deniz Arıkan ")
        #expect(model.recognizedNames.map(\.spelling) == ["Ece"])
        #expect(model.unknownAttendees == ["Ada Soylu"])
    }

    @Test func editsMoveAnUndoneNameAndDeletingItForgetsTheUndo() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = Self.eventModel(context)
        model.text = "Deniz'i ara"
        try Self.undo("Deniz", in: model)
        model.text = "Deniz'i ara lütfen"
        #expect(model.suppressedNames == [0..<5] && model.recognizedNames.isEmpty)
        model.text = "Önce Çınaraltı'da Deniz'i ara lütfen"
        #expect(model.suppressedNames.map { Self.bytes(of: $0, in: model) } == ["Deniz"])
        #expect(model.recognizedNames.isEmpty)
        model.text = "Önce Çınaraltı'da ara lütfen"
        #expect(model.suppressedNames.isEmpty)
        // Typed again, it is a new recognition with its chip.
        model.text = "Önce Çınaraltı'da Deniz'i ara lütfen"
        #expect(model.recognizedNames.map(\.spelling) == ["Deniz"])
    }

    @Test func losingOneOfTwoEqualNamesForgetsTheUndoInsteadOfGuessing() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = Self.eventModel(context)
        model.text = "Ece Ece geldi"
        try Self.undo("Ece", occurrence: 0, in: model)
        #expect(model.recognizedNames.map(\.byteRange) == [4..<7])
        model.text = "Ece Ece geldi!"
        #expect(model.suppressedNames == [0..<3])
        model.text = "Ece geldi!"
        #expect(model.suppressedNames.isEmpty && model.recognizedNames.map(\.spelling) == ["Ece"])
    }

    @Test func multibyteNamesAndSuffixesStayAsTyped() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = Self.eventModel(context)
        model.text = "Çınaraltı Kafe'de Baran'la buluştuk"
        let names = model.recognizedNames
        #expect(names.map(\.spelling) == ["Çınaraltı Kafe", "Baran"])
        #expect(
            names.map(\.byteRange) == [
                0..<"Çınaraltı Kafe".utf8.count, "Çınaraltı Kafe'de ".utf8.count..<"Çınaraltı Kafe'de Baran".utf8.count,
            ])
        try Self.undo("Çınaraltı Kafe", in: model)
        #expect(try await model.submit(time: Self.one))
        #expect(
            try context.document().bodyLines.events.map(\.block.text) == [
                "Çınaraltı Kafe'de [[Baran Tunç|Baran]]'la buluştuk"
            ])
    }

    /// The first submit takes the date out and stops at the question; the undone name moved with it.
    @Test func undoSurvivesTaskPreparationAndAQuestionBetweenTwoSubmits() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.mode = .task
        model.text = "!! yarın Deniz'i ve Mert Aksu'yu ara her hafta"
        try Self.undo("Deniz", in: model)
        #expect(await !model.submit(time: nil))
        #expect(model.text == "Deniz'i ve Mert Aksu'yu ara")
        #expect(model.suppressedNames.map { Self.bytes(of: $0, in: model) } == ["Deniz"])
        #expect(model.recognizedNames.map(\.spelling) == ["Mert Aksu"])
        model.skip(try #require(model.pendingAmbiguity))
        #expect(await model.submit(time: nil))
        let task = try #require(context.document().bodyLines.tasks.first)
        #expect(task.text == "Deniz'i ve Mert Aksu'yu ara")
        #expect(task.dueDate == CalendarDate("2026-10-04") && task.priority == .high)
        #expect(task.recurrence?.rule == "every week")
    }

    /// Taking the date out of "Mert yarın Aksu" joins the undone "Mert" into "Mert Aksu": the joined
    /// name holds the undone occurrence, so it is written plain and not asked about.
    @Test func anExpressionTakenOutBetweenWordsKeepsTheUndoneNamePlain() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let asked = context.model()
        asked.mode = .task
        asked.text = "Mert yarın Aksu'yu ara"
        // Without the undo the joined name is asked about, so the vault does make the join.
        #expect(await !asked.submit(time: nil))
        #expect(asked.pendingAmbiguity?.spelling == "Mert Aksu")

        let model = context.model()
        model.mode = .task
        model.text = "Mert yarın Aksu'yu ara"
        #expect(model.recognizedNames.map(\.spelling) == ["Mert"])
        try Self.undo("Mert", in: model)
        #expect(await model.submit(time: nil))
        let task = try #require(context.document().bodyLines.tasks.first)
        #expect(task.text == "Mert Aksu'yu ara" && task.dueDate == CalendarDate("2026-10-04"))

        // An undo the longer name already covered while typing hides nothing and spreads to nothing.
        let longer = context.model()
        longer.mode = .task
        longer.text = "Deniz"
        try Self.undo("Deniz", in: longer)
        longer.text = "Deniz Arıkan'ı yarın ara"
        #expect(longer.suppressedNames == [0..<5] && longer.recognizedNames.map(\.spelling) == ["Deniz Arıkan"])
        #expect(await longer.submit(time: nil))
        #expect(try context.document().bodyLines.tasks.map(\.text).last == "[[Deniz Arıkan]]'ı ara")
    }

    /// A person named like a weekday: in a task the word is the date and its name chip waits
    /// until the date chip is undone, so the row never offers a link sending would not make.
    @Test func aNameInsideATaskExpressionGetsItsChipOnceTheExpressionIsUndone() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        try Data("---\ntype: person\nname: Cuma\naliases: []\n---\n".utf8)
            .write(to: context.root.appendingPathComponent("people/Cuma.md"))
        await context.start()
        let model = context.model()
        model.text = "Cuma'yı ara"
        #expect(model.recognizedNames.map(\.spelling) == ["Cuma"])
        model.mode = .task
        #expect(model.taskExpressions.map(\.spelling) == ["Cuma"])
        #expect(model.recognizedNames.isEmpty)
        model.undoRecognition(try #require(model.taskExpressions.first))
        #expect(model.recognizedNames.map(\.spelling) == ["Cuma"] && model.dueDate == nil)
        #expect(await model.submit(time: nil))
        let task = try #require(context.document().bodyLines.tasks.first)
        #expect(task.text == "[[Cuma]]'yı ara" && task.dueDate == nil)
    }

    /// Edits next to, inside and over an undone name: it follows its bytes, an edit inside or a
    /// retyped text forgets it, and a name typed again is a new recognition with its chip.
    @Test func editsAroundInsideAndOverAnUndoneName() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = Self.eventModel(context)
        model.text = "Deniz geldi"
        try Self.undo("Deniz", in: model)
        // Typing on after the name and back keeps the undo on the same bytes.
        model.text = "Denizli geldi"
        #expect(model.suppressedNames == [0..<5] && model.recognizedNames.isEmpty)
        model.text = "Deniz geldi"
        #expect(model.suppressedNames == [0..<5] && model.recognizedNames.isEmpty)
        model.text = "Bugün Deniz geldi"
        #expect(model.suppressedNames.map { Self.bytes(of: $0, in: model) } == ["Deniz"])
        // An edit inside the name forgets the undo.
        model.text = "Bugün Dexniz geldi"
        #expect(model.suppressedNames.isEmpty)
        model.text = "Bugün Deniz geldi"
        #expect(model.recognizedNames.map(\.spelling) == ["Deniz"])
        // Cut and pasted elsewhere is a new occurrence.
        try Self.undo("Deniz", in: model)
        model.text = "Bugün geldi"
        model.text = "Bugün geldi Deniz"
        #expect(model.suppressedNames.isEmpty && model.recognizedNames.map(\.spelling) == ["Deniz"])
        // The whole text replaced at once, even by the same words, forgets the undo.
        try Self.undo("Deniz", in: model)
        model.text = "Deniz Bugün geldi"
        #expect(model.suppressedNames.isEmpty && model.recognizedNames.map(\.spelling) == ["Deniz"])
        try Self.undo("Deniz", in: model)
        model.text = ""
        model.text = "Deniz Bugün geldi"
        #expect(model.suppressedNames.isEmpty && model.recognizedNames.map(\.spelling) == ["Deniz"])
        #expect(try model.composer.linkedText() == "[[Deniz Arıkan|Deniz]] Bugün geldi")
    }

    /// The row reads the task analysis many times per draw and it is kept for the same input
    /// only: another day, language order, week start, undo or spelling is read again.
    @Test func theTaskAnalysisIsReadAgainWhenAnythingItReadsChanges() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        var day = try #require(CalendarDate("2026-10-03"))
        let model = QuickEntryModel(store: context.store, today: { day })
        model.languages = [.turkish, .english]
        model.calendar = WeekStartTests.calendar(firstWeekday: 2)
        model.mode = .task
        model.text = "call haftaya"
        let monday = try #require(model.dueDate)
        #expect(monday.weekday == 0)
        model.calendar = WeekStartTests.calendar(firstWeekday: 1)
        #expect(model.dueDate == monday.addingDays(-1))
        day = try #require(CalendarDate("2026-10-10"))
        #expect(model.dueDate == monday.addingDays(6))
        model.text = "call next week"
        model.languages = [.turkish]
        #expect(model.dueDate == nil)
        model.languages = [.english]
        #expect(model.dueDate == monday.addingDays(6))
        model.undoRecognition(try #require(model.taskExpressions.first))
        #expect(model.dueDate == nil && model.submissionText == "call next week")
        // A canonically equal spelling with other bytes moves the ranges the analysis returns.
        model.languages = [.turkish, .english]
        model.text = "Çay yarın"
        #expect(model.taskExpressions.map(\.byteRanges) == [[5..<11]])
        model.text = "C\u{327}ay yarın"
        #expect(model.taskExpressions.map(\.byteRanges) == [[6..<12]])
    }

    /// A name chip and a date chip undo only their own recognition.
    @Test func nameAndExpressionUndosAreIndependent() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.mode = .task
        model.text = "yarın Ece'yi ara"
        try Self.undo("Ece", in: model)
        #expect(model.taskExpressions.map(\.spelling) == ["yarın"] && model.dueDate == CalendarDate("2026-10-04"))
        model.undoRecognition(try #require(model.taskExpressions.first))
        #expect(model.recognizedNames.isEmpty && model.dueDate == nil)
        #expect(await model.submit(time: nil))
        let task = try #require(context.document().bodyLines.tasks.first)
        #expect(task.text == "yarın Ece'yi ara" && task.dueDate == nil)
    }

    @Test func failedWriteBringsTheUndoBackWithTheDraft() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = Self.eventModel(context)
        model.text = "Deniz ile Ece"
        try Self.undo("Deniz", in: model)
        let bytes = Data([0xFF, 0xFE])
        try FileManager.default.createDirectory(
            at: context.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: context.file)
        #expect(try await !model.submit(time: Self.one))
        #expect(model.text == "Deniz ile Ece" && model.suppressedNames == [0..<5])
        #expect(model.recognizedNames.map(\.spelling) == ["Ece"])
        #expect(try Data(contentsOf: context.file) == bytes)
        try FileManager.default.removeItem(at: context.file)
        #expect(try await model.submit(time: Self.one))
        #expect(try context.document().bodyLines.events.map(\.block.text) == ["Deniz ile [[Ece Yalın|Ece]]"])
        #expect(model.suppressedNames.isEmpty)
    }

    /// The composer links what it linked before whenever nothing is undone, in both modes.
    @Test func withoutAnUndoTheComposerLinksWhatTheRecognizerChainDid() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = context.model()
        let entities = context.store.knownEntities
        try #require(entities.count > 5)
        var draws = NameDraws(seed: 20_261_011)
        var linked = 0
        var chips = 0
        for iteration in 0..<1_200 {
            let text = draws.text(pieces: 7)
            model.mode = .event
            model.mode = iteration.isMultiple(of: 2) ? .event : .task
            model.text = ""
            model.text = text
            #expect(model.suppressedNames.isEmpty)
            if model.mode == .task { model.prepareTaskText() }
            // The chain as `dev` ran it: recognize, link certain names and choices, drop leftover `@`.
            let mentions = EntityRecognizer.recognize(
                model.text, entities: entities, usage: context.store.entityUsage,
                context: RecognitionContext(entities: model.pins.map(\.entity)))
            let expected = model.composer.removingUnbound(
                from: try EntityRecognizer.linking(model.text, mentions: mentions, choices: [:]))
            #expect(try model.composer.linkedText() == expected, "\(text.debugDescription)")
            #expect(model.mentions == mentions, "\(text.debugDescription)")
            let bare = mentions.filter { !$0.isExplicit && ($0.isCertain || $0.isAmbiguous) }
            #expect(model.recognizedNames.map(\.spelling) == bare.map(\.spelling), "\(text.debugDescription)")
            linked += mentions.filter(\.isCertain).count
            chips += bare.count
        }
        // The draws have to reach the recognizer often, or the comparison proves nothing.
        #expect(linked > 1_500 && chips > 1_500, "\(linked) \(chips)")
    }

    /// Undoing any one chip leaves exactly that occurrence unlinked; undoing all of them leaves
    /// only `@` mentions linked, and a text without `@` is written exactly as typed.
    @Test func undoingAChipUnlinksExactlyThatOccurrence() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = Self.eventModel(context)
        let entities = context.store.knownEntities
        var draws = NameDraws(seed: 31_337)
        var undone = 0
        for iteration in 0..<1_000 {
            let text = draws.text(pieces: 7)
            model.text = ""
            model.text = text
            let names = model.recognizedNames
            guard !names.isEmpty else { continue }
            let mentions = model.mentions
            if iteration.isMultiple(of: 2) {
                let chosen = names[draws.next(names.count)]
                model.undoRecognition(chosen)
                undone += 1
                let others = mentions.filter { model.composer.globalRange($0.position) != chosen.byteRange }
                #expect(others.count == mentions.count - 1, "\(text.debugDescription)")
                let expected = model.composer.removingUnbound(
                    from: try EntityRecognizer.linking(text, mentions: others, choices: [:]))
                #expect(try model.composer.linkedText() == expected, "\(text.debugDescription)")
                #expect(model.recognizedNames == names.filter { $0 != chosen }, "\(text.debugDescription)")
            } else {
                for name in names { model.undoRecognition(name) }
                undone += names.count
                #expect(model.recognizedNames.isEmpty, "\(text.debugDescription)")
                let explicit = EntityRecognizer.recognize(text, entities: entities).filter(\.isExplicit)
                let expected = model.composer.removingUnbound(
                    from: try EntityRecognizer.linking(text, mentions: explicit, choices: [:]))
                #expect(try model.composer.linkedText() == expected, "\(text.debugDescription)")
                if !text.contains("@") { #expect(try model.composer.linkedText() == text) }
                model.awaitingResolution = true
                #expect(
                    model.pendingAmbiguity == nil || model.pendingAmbiguity?.isExplicit == true,
                    "\(text.debugDescription)")
                model.awaitingResolution = false
            }
        }
        #expect(undone > 1_000, "\(undone)")
    }
}

/// Seeded quick-entry texts built from the sample vault's names among dates, links and plain words.
private struct NameDraws {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    static let pieces = [
        "Deniz", "Deniz'le", "Deniz'i", "Deniz abi", "@Deniz", "(@Deniz)", "deniz", "DENIZ", "Deniz Arıkan",
        "Mert Aksu", "Mert Aksu'yu", "@Mert Aksu", "Mert", "mert aksu", "Ece", "Ece'yi", "Baran'la", "Baran Tunç",
        "Selin", "Selin Korkmaz", "Çınaraltı Kafe", "Çınaraltı Kafe'de", "Liman Ofis", "Liman Ofis'te", "ofis", "Ofis",
        "salon", "Tepe Spor Salonu", "Ev", "ev", "Ev'de", "@Yeni Kişi", "[[Deniz Arıkan]]", "[[Ece Yalın|Ece]]'yi",
        "#Deniz", "deniz@ornek.test", "https://ornek.test/Ece", "`Deniz`", "yarın", "her hafta", "!!", "5 ekim",
        "ile", "ve", "kahve", "toplantı", "ara", ",", ".", "e\u{301}", "👨‍👩‍👧", "İ", "\n",
    ]
    static let gaps = [" ", " ", " ", " ", "", "  ", "\t"]

    mutating func next(_ count: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return Int((state >> 33) % UInt64(count))
    }

    mutating func text(pieces count: Int) -> String {
        var text = ""
        for _ in 0..<(1 + next(count)) {
            text += Self.pieces[next(Self.pieces.count)] + Self.gaps[next(Self.gaps.count)]
        }
        return text
    }
}

#if os(macOS)
    import AppKit
    import SwiftUI

    /// The name chip as VoiceOver meets it, read from the accessibility tree SwiftUI builds.
    @MainActor @Suite(.timeLimit(.minutes(1)))
    struct QuickEntryNameChipAccessibilityTests {
        private let watchdog = HostedTestWatchdog()

        @Test func nameChipSaysWhatWasRecognizedAndItsActionUndoesIt() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let model = context.model()
            model.text = "Deniz ile Mert Aksu"
            let mount = HostedLayout.Mount(
                QuickEntryTaskControls(model: model, showsPicker: .constant(false)),
                size: CGSize(width: 480, height: 120))
            defer { mount.close() }
            await mount.settle()

            let host = try #require(mount.window.contentView)
            // SwiftUI builds its accessibility tree only once an assistive client has asked the
            // process something; the answer to this question does not matter.
            _ = AXUIElementSetAttributeValue(
                AXUIElementCreateApplication(getpid()), "AXManualAccessibility" as CFString, kCFBooleanTrue)
            await mount.settle()
            let label = String(localized: "Tanındı: \("Deniz")")
            guard let chip = Self.element(under: host, labelled: label) else {
                let line = "ATLANDI (ortam erişilebilirlik ağacı vermiyor): \(#function)\n"
                FileHandle.standardError.write(Data(line.utf8))
                return
            }
            let ambiguous = try #require(
                Self.element(under: host, labelled: String(localized: "Tanındı: \("Mert Aksu")")))
            #expect(
                ambiguous.perform(Self.value)?.takeUnretainedValue() as? String
                    == String(localized: "Gönderince hangisi olduğu sorulur"))
            let actions = chip.perform(Self.customActions)?.takeUnretainedValue() as? [NSAccessibilityCustomAction]
            #expect(actions?.map(\.name) == [String(localized: "Tanımayı geri al")])
            _ = chip.perform(Self.press)
            #expect(model.suppressedNames == [0..<5])
            #expect(model.recognizedNames.map(\.spelling) == ["Mert Aksu"])

            await mount.settle()
            #expect(Self.element(under: host, labelled: label) == nil)
        }

        // SwiftUI's nodes answer the accessibility messages without adopting the Swift protocol.
        private static let label = NSSelectorFromString("accessibilityLabel")
        private static let value = NSSelectorFromString("accessibilityValue")
        private static let children = NSSelectorFromString("accessibilityChildren")
        private static let customActions = NSSelectorFromString("accessibilityCustomActions")
        private static let press = NSSelectorFromString("accessibilityPerformPress")

        private static func element(under root: Any, labelled label: String) -> NSObject? {
            element(under: root) { node in
                node.responds(to: Self.label) && node.perform(Self.label)?.takeUnretainedValue() as? String == label
            }
        }

        private static func element(under root: Any, where matches: (NSObject) -> Bool) -> NSObject? {
            guard let node = root as? NSObject else { return nil }
            if matches(node) { return node }
            guard node.responds(to: children),
                let nodes = node.perform(children)?.takeUnretainedValue() as? [Any]
            else { return nil }
            for child in nodes {
                if let match = element(under: child, where: matches) { return match }
            }
            return nil
        }
    }
#endif
