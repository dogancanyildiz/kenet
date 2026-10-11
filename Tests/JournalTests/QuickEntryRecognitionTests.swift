import DateParsing
import Foundation
import Testing
import VaultFormat

@testable import Journal

/// Undoing a recognized task expression: the words stay in the task and no field is written.
@MainActor
struct QuickEntryRecognitionTests {
    private static func undo(_ spelling: String, in model: QuickEntryModel) throws {
        model.undoRecognition(try #require(model.taskExpressions.first { $0.spelling == spelling }))
    }

    private static func bytes(of range: Range<Int>, in model: QuickEntryModel) -> String {
        String(decoding: Array(model.text.utf8)[range], as: UTF8.self)
    }

    @Test func undoneDateStaysInTheTaskTextAndWritesNoDueDate() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.mode = .task
        model.text = "yarın Deniz'i ara"
        #expect(model.taskExpressions.map(\.spelling) == ["yarın"])
        #expect(model.dueDate == CalendarDate("2026-10-04") && model.submissionText == "Deniz'i ara")
        try Self.undo("yarın", in: model)
        #expect(model.taskExpressions.isEmpty && model.dueDate == nil)
        #expect(model.submissionText == "yarın Deniz'i ara")
        #expect(await model.submit(time: nil))
        let id = try #require(context.document().bodyLines.tasks.first?.block.id)
        #expect(
            try Data(contentsOf: context.file)
                == Data(
                    "---\ntype: journal\ndate: 2026-10-03\n---\n\n## Tasks\n- [ ] yarın Deniz'i ara ^\(id)\n".utf8))
        #expect(try context.row("yarın Deniz'i ara").due == nil)
        #expect(model.text.isEmpty && model.suppressedExpressions.isEmpty)
    }

    @Test(arguments: [
        ("!!", "!! Plan yaz"), ("yarın", "yarın Plan yaz"), ("her hafta", "Plan yaz her hafta"),
    ])
    func eachExpressionIsUndoneOnItsOwn(undone: String, written: String) async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.mode = .task
        model.text = "!! yarın Plan yaz her hafta"
        let all = ["!!", "yarın", "her hafta"]
        #expect(model.taskExpressions.map(\.spelling) == all)
        try Self.undo(undone, in: model)
        #expect(model.taskExpressions.map(\.spelling) == all.filter { $0 != undone })
        #expect(await model.submit(time: nil))
        let task = try #require(context.document().bodyLines.tasks.first)
        #expect(task.text == written)
        #expect((task.priority == nil) == (undone == "!!"))
        #expect((task.recurrence == nil) == (undone == "her hafta"))
        #expect((task.dueDate == nil) == (undone == "yarın"))
    }

    @Test func undoSurvivesAMentionQuestionBetweenTwoSubmits() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.mode = .task
        model.text = "!! yarın Mert Aksu ile görüş her hafta"
        try Self.undo("yarın", in: model)
        #expect(await !model.submit(time: nil))
        // The first submit already took the other expressions out; the undone word moved with it.
        #expect(model.text == "yarın Mert Aksu ile görüş")
        #expect(model.suppressedExpressions.map { Self.bytes(of: $0, in: model) } == ["yarın"])
        #expect(model.dueDate == nil && model.taskPriority == .high)
        model.skip(try #require(model.pendingAmbiguity))
        #expect(await model.submit(time: nil))
        let task = try #require(context.document().bodyLines.tasks.first)
        #expect(task.text == "yarın Mert Aksu ile görüş")
        #expect(task.dueDate == nil && task.priority == .high && task.recurrence?.rule == "every week")
    }

    @Test func editsMoveAnUndoneExpressionAndDeletingItForgetsTheUndo() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = context.model()
        model.mode = .task
        model.text = "Deniz'i yarın ara"
        try Self.undo("yarın", in: model)
        model.text = "Deniz'i yarın ara lütfen"
        #expect(model.dueDate == nil && model.taskExpressions.isEmpty)
        model.text = "Şimdi Deniz'i yarın ara lütfen"
        #expect(model.suppressedExpressions.map { Self.bytes(of: $0, in: model) } == ["yarın"])
        #expect(model.dueDate == nil && model.submissionText == model.text)
        model.text = "Şimdi Deniz'i ara lütfen"
        #expect(model.suppressedExpressions.isEmpty)
        // Typed again, it is a new expression and is recognized.
        model.text = "Şimdi Deniz'i yarın ara lütfen"
        #expect(model.dueDate == CalendarDate("2026-10-04"))
        #expect(model.submissionText == "Şimdi Deniz'i ara lütfen")
    }

    @Test func turkishTextUndoesTheExpressionTheChipNames() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.mode = .task
        model.text = "İğne işini çarşamba öğlen bitir her gün"
        let date = try #require(model.taskExpressions.first { $0.spelling == "çarşamba" })
        #expect(model.taskExpressions.count == 2)
        #expect(date.byteRanges == ["İğne işini ".utf8.count..<"İğne işini çarşamba".utf8.count])
        model.undoRecognition(date)
        #expect(model.dueDate == nil && model.recurrenceExpression?.recurrence.rule == "every day")
        #expect(model.submissionText == "İğne işini çarşamba öğlen bitir")
        #expect(await model.submit(time: nil))
        let task = try #require(context.document().bodyLines.tasks.first)
        #expect(task.text == "İğne işini çarşamba öğlen bitir")
        #expect(task.dueDate == nil && task.recurrence?.rule == "every day")
    }

    /// Taking the recurrence out joins "next" and "week" into one date: one chip, one undo.
    @Test func expressionSplitByAnotherIsOneRecognition() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.languages = [.english, .turkish]
        model.mode = .task
        model.text = "Call next every day week"
        #expect(model.taskExpressions.map(\.spelling) == ["next week", "every day"])
        #expect(model.dueDate != nil && model.submissionText == "Call")
        try Self.undo("next week", in: model)
        #expect(model.taskExpressions.map(\.spelling) == ["every day"])
        #expect(model.dueDate == nil && model.submissionText == "Call next week")
        #expect(await model.submit(time: nil))
        let task = try #require(context.document().bodyLines.tasks.first)
        #expect(task.text == "Call next week" && task.dueDate == nil && task.recurrence?.rule == "every day")
    }

    @Test func failedWriteKeepsTheUndoWithTheDraft() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.mode = .task
        model.text = "yarın ara"
        try Self.undo("yarın", in: model)
        let bytes = Data([0xFF, 0xFE])
        try bytes.write(to: context.file)
        #expect(await !model.submit(time: nil))
        #expect(model.text == "yarın ara" && model.dueDate == nil && model.taskExpressions.isEmpty)
        #expect(try Data(contentsOf: context.file) == bytes)
    }

    @Test func eventModeHasNoTaskExpressionsAndKeepsAnUndoForTheWayBack() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = context.model()
        model.text = "!! yarın ara"
        #expect(model.taskExpressions.isEmpty && model.submissionText == model.text)
        model.mode = .task
        try Self.undo("yarın", in: model)
        model.mode = .event
        model.text = "!! yarın ara, sonra yaz"
        model.mode = .task
        #expect(model.taskExpressions.map(\.spelling) == ["!!"] && model.dueDate == nil)
    }

    @Test func deletingOneOfTwoEqualWordsForgetsTheUndoInsteadOfGuessing() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = context.model()
        model.mode = .task
        model.text = "yarın yarın ara"
        model.undoRecognition(try #require(model.taskExpressions.first))
        #expect(model.taskExpressions.map(\.byteRanges) == [[7..<13]])
        // Typing elsewhere keeps the undo on the first word.
        model.text = "yarın yarın ara!"
        #expect(model.suppressedExpressions == [0..<6])
        // One word went and the text cannot say which: the one that is left is recognized again.
        model.text = "yarın ara!"
        #expect(model.suppressedExpressions.isEmpty)
        #expect(model.taskExpressions.map(\.spelling) == ["yarın"] && model.dueDate == CalendarDate("2026-10-04"))
    }

    /// Two spellings of "é" compare equal as strings; the undo still has to follow the bytes.
    @Test func undoFollowsATextThatOnlyChangesItsUnicodeForm() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = context.model()
        model.mode = .task
        let decomposed = "cafe\u{301} yarın ara"
        let composed = "caf\u{E9} yarın ara"
        #expect(decomposed == composed && decomposed.utf8.count == composed.utf8.count + 1)
        model.text = decomposed
        try Self.undo("yarın", in: model)
        model.text = composed
        #expect(Array(model.text.utf8) == Array(composed.utf8))
        #expect(model.suppressedExpressions.map { Self.bytes(of: $0, in: model) } == ["yarın"])
        model.prepareTaskText()
        #expect(model.text == composed && model.dueDate == nil)
    }

    /// A kept range must still cover the bytes it covered; it may be dropped, never moved onto others.
    @Test func editsNeverMoveAnUndoOntoOtherBytes() {
        var draws = Draws(seed: 7_101)
        var kept = 0
        for _ in 0..<4_000 {
            let old = draws.text(pieces: 7)
            let characters = Array(old)
            let lower = draws.next(characters.count + 1)
            let upper = lower + draws.next(characters.count - lower + 1)
            let inserted = draws.next(3) == 0 ? "" : draws.text(pieces: 2)
            let new = String(characters[..<lower]) + inserted + String(characters[upper...])
            let editStart = String(characters[..<lower]).utf8.count
            let editEnd = String(characters[..<upper]).utf8.count
            let oldBytes = Array(old.utf8)
            let newBytes = Array(new.utf8)
            for range in draws.spans(of: old) {
                let result = QuickEntryModel.following([range], from: old, to: new)
                guard let moved = result.first else { continue }
                kept += 1
                #expect(result.count == 1 && moved.lowerBound >= 0 && moved.upperBound <= newBytes.count)
                guard moved.lowerBound >= 0, moved.upperBound <= newBytes.count else { continue }
                let edit = "\(old.debugDescription) → \(new.debugDescription)"
                #expect(newBytes[moved].elementsEqual(oldBytes[range]), "\(edit)")
                if range.upperBound <= editStart {
                    #expect(moved == range, "\(edit)")
                } else if range.lowerBound >= editEnd {
                    let delta = newBytes.count - oldBytes.count
                    #expect(moved == (range.lowerBound + delta)..<(range.upperBound + delta), "\(edit)")
                }
            }
        }
        // The rule is not "drop everything": most untouched words keep their undo.
        #expect(kept > 4_000)
    }

    /// Whatever is undone stays in the text through submit preparation, under the same undo; with
    /// every recognition undone the task is written exactly as typed.
    @Test func preparationKeepsEveryUndoneWordWhereItIs() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = context.model()
        var draws = Draws(seed: 99)
        var undone = 0
        for iteration in 0..<1_500 {
            let text = draws.text(pieces: 8)
            model.mode = .event
            model.mode = .task
            model.text = ""
            model.text = text
            #expect(model.suppressedExpressions.isEmpty)
            if iteration.isMultiple(of: 2) {
                // Undo until nothing is recognized; undoing one expression can reveal another.
                for _ in 0..<12 {
                    guard let expression = model.taskExpressions.first else { break }
                    model.undoRecognition(expression)
                }
                #expect(model.taskExpressions.isEmpty, "\(text.debugDescription)")
                let ranges = model.suppressedExpressions
                undone += ranges.count
                model.prepareTaskText()
                #expect(model.text == text, "\(text.debugDescription)")
                #expect(model.suppressedExpressions == ranges, "\(text.debugDescription)")
                #expect(model.dueDate == nil && model.taskRecurrence == nil && model.taskPriority == nil)
            } else {
                let expressions = model.taskExpressions
                guard !expressions.isEmpty else { continue }
                model.undoRecognition(expressions[draws.next(expressions.count)])
                let words = model.suppressedExpressions.map { Self.bytes(of: $0, in: model) }
                undone += words.count
                model.prepareTaskText()
                let bytes = Array(model.text.utf8)
                let ranges = model.suppressedExpressions
                #expect(ranges.allSatisfy { $0.upperBound <= bytes.count }, "\(text.debugDescription)")
                guard ranges.allSatisfy({ $0.upperBound <= bytes.count }) else { continue }
                #expect(ranges.map { Self.bytes(of: $0, in: model) } == words, "\(text.debugDescription)")
                #expect(zip(ranges, ranges.dropFirst()).allSatisfy { $0.upperBound <= $1.lowerBound })
            }
        }
        #expect(undone > 1_000)
    }

    /// The model reads expressions through `QuickEntryAnalysis`; with nothing undone it must
    /// hand the store exactly what the parser chain it replaced did.
    @Test func withoutAnUndoTheModelMatchesTheParserChain() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = context.model()
        // The chain below is the Monday week it always was; the process calendar differs by machine.
        model.calendar = WeekStartTests.calendar(firstWeekday: 2)
        var draws = Draws(seed: 20_261_011)
        let today = context.today
        var recognized = (recurrence: 0, priority: 0, date: 0)
        for iteration in 0..<2_000 {
            let text = draws.text(pieces: 8)
            let language: [DateParsing.Language] =
                iteration.isMultiple(of: 2) ? [.turkish, .english] : [.english, .turkish]
            // The chain as `dev` ran it before the analysis: recurrence, then priority, then date.
            let recurrence = RecurrenceExpressionParser.parse(text, language: language)
            let priority = PriorityExpressionParser.parse(recurrence?.remainder ?? text)
            let expressionText = priority?.remainder ?? recurrence?.remainder ?? text
            let date = DateExpressionParser.parse(expressionText, today: today, language: language)
            let explicit = RawDocument(bytes: ("- [ ] " + text).utf8).bodyLines.tasks.first?.priority
            recognized.recurrence += recurrence == nil ? 0 : 1
            recognized.priority += priority == nil ? 0 : 1
            recognized.date += date == nil ? 0 : 1

            model.mode = .event
            model.languages = language
            model.mode = .task
            model.text = text
            #expect(model.submissionText == date?.remainder ?? expressionText, "\(text.debugDescription)")
            #expect(model.dueDate == date?.date && model.dateIsAssumed == (date?.confidence == .assumed))
            #expect(model.recurrenceExpression?.recurrence == recurrence?.recurrence)
            model.prepareTaskText()
            #expect(model.text == date?.remainder ?? expressionText, "\(text.debugDescription)")
            #expect(model.taskRecurrence == recurrence?.recurrence, "\(text.debugDescription)")
            #expect(model.taskPriority == priority.map { explicit ?? $0.priority }, "\(text.debugDescription)")
            #expect(model.dueDate == date?.date && model.dateIsAssumed == (date?.confidence == .assumed))
            #expect(model.suppressedExpressions.isEmpty)
        }
        // The draws have to reach every parser often, or the comparison proves nothing.
        #expect(recognized.recurrence > 300 && recognized.priority > 300 && recognized.date > 800, "\(recognized)")
    }
}

/// Seeded quick-entry texts: expressions of every kind among names, links, code and plain words.
private struct Draws {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    static let pieces = [
        "her hafta", "every day", "her salı", "every monday", "her 2 haftada bir", "every 2 weeks", "her ay",
        "every month when done", "her gün tamamlanınca", "yarın", "Yarın", "YARIN", "yarına", "yarın,", "(yarın)",
        "tomorrow", "bugün", "today", "haftaya salı", "haftaya", "next week", "next friday", "gelecek hafta",
        "pazartesi", "salı günü", "cuma", "5 ekim", "5 Ekim 2027", "oct 5", "3 gün sonra", "in 3 days", "2026-10-12",
        "12.10.2026", "12/10", "saat 5", "2.5 kg", "5", "ekim", "!", "!!", "!!!", "!x", "x!", "🔽", "🔼", "⏫",
        "📅 2026-10-09", "⏳ 2026-10-05", "🔁 every week", "@Cuma", "@Deniz", "[[yarın]]", "[[Deniz Kaya|yarın]]",
        "[bağlantı](https://ornek.test/yarin)", "`every week`", "`!!`", "#project/ev", "Deniz'i ara", "Ömer'e yaz",
        "çığ", "ığüşöç", "İ", "e\u{301}", "👨‍👩‍👧", "🇹🇷", ",", ".", "-", "\n",
    ]
    static let gaps = [" ", " ", " ", " ", "", "  ", "\t", " \t "]

    mutating func next(_ count: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return Int((state >> 33) % UInt64(count))
    }

    mutating func text(pieces count: Int) -> String {
        var text = next(8) == 0 ? Self.gaps[next(Self.gaps.count)] : ""
        // A priority mark counts only at either end, so the ends get one more often than chance.
        let marks = ["! ", "!! ", "!!", "", "", "", "", ""]
        text += marks[next(marks.count)]
        for _ in 0..<next(count + 1) {
            text += Self.pieces[next(Self.pieces.count)] + Self.gaps[next(Self.gaps.count)]
        }
        return text + marks[next(marks.count)].reversed()
    }

    /// Byte ranges of some whole words of `text`, as an undo would hold them.
    mutating func spans(of text: String) -> [Range<Int>] {
        var spans: [Range<Int>] = []
        var start: Int?
        for (index, byte) in (Array(text.utf8) + [32]).enumerated() {
            if byte == 32 || byte == 9 || byte == 10 {
                if let from = start, next(2) == 0 { spans.append(from..<index) }
                start = nil
            } else if start == nil {
                start = index
            }
        }
        return spans
    }
}

#if os(macOS)
    import AppKit
    import SwiftUI

    /// The chip row as VoiceOver meets it, read from the accessibility tree SwiftUI builds.
    @MainActor @Suite(.timeLimit(.minutes(1)))
    struct QuickEntryChipAccessibilityTests {
        private let watchdog = HostedTestWatchdog()

        @Test func chipNamesTheRecognitionAndItsActionUndoesIt() async throws {
            let context = try TaskTestContext()
            defer { context.clean() }
            let model = context.model()
            model.mode = .task
            model.text = "!! yarın ara her salı"
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
            // The date control was there before the chips; without it the tree was not built at all.
            guard Self.element(under: host, labelled: String(localized: "Görev tarihini değiştir")) != nil else {
                let line = "ATLANDI (ortam erişilebilirlik ağacı vermiyor): \(#function)\n"
                FileHandle.standardError.write(Data(line.utf8))
                return
            }
            let date = try #require(Self.element(under: host, labelled: String(localized: "Tanındı: \("yarın")")))
            let priority = Self.element(
                under: host, labelled: String(localized: "Tanındı: \(String(localized: "Yüksek öncelik"))"))
            #expect(priority != nil)
            // The chip says how the recurrence was understood, with the catalog's weekday name.
            let weekday = Self.element(
                under: host, labelled: String(localized: "Tanındı: \(String(localized: "Salı"))"))
            #expect(weekday != nil)
            let actions = date.perform(Self.customActions)?.takeUnretainedValue() as? [NSAccessibilityCustomAction]
            #expect(actions?.map(\.name) == [String(localized: "Tanımayı geri al")])
            _ = date.perform(Self.press)
            #expect(model.taskExpressions.map(\.spelling) == ["!!", "her salı"])
            #expect(model.dueDate == nil && model.submissionText == "yarın ara")

            await mount.settle()
            #expect(Self.element(under: host, labelled: String(localized: "Tanındı: \("yarın")")) == nil)
        }

        // SwiftUI's nodes answer the accessibility messages without adopting the Swift protocol.
        private static let label = NSSelectorFromString("accessibilityLabel")
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
