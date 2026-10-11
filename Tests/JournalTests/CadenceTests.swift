import Foundation
import Summaries
import Testing
import VaultFormat

@testable import Journal

@MainActor
struct CadenceTests {
    private let today = CalendarDate("2026-10-11")!
    private let zone = TimeZone(secondsFromGMT: 3 * 3600)!

    @Test func vaultListMatchesHandWrittenDays() async throws {
        let context = try TaskTestContext(sample: false)
        defer { context.clean() }
        try FileManager.default.copyItem(at: fixtures().appendingPathComponent("vaults/cadence"), to: context.root)
        await context.start()
        let cadences = try await context.store.personCadences()
        let data = try Data(contentsOf: fixtures().appendingPathComponent("summaries/cadence.json"))
        let document = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let cases = try #require(document?["cases"] as? [[String: Any]])
        let vaultCases = cases.filter { $0["source"] as? String == "vault" }
        #expect(vaultCases.count == 2)
        for fixture in vaultCases {
            let day = try #require((fixture["today"] as? String).flatMap { CalendarDate($0) })
            let groups = UnseenPeople.compute(
                people: context.store.content.entities, content: context.store.content,
                today: day, threshold: 30, cadences: cadences)
            let overdue = try #require(fixture["overdue"] as? [[String: Any]])
            #expect(groups.overdue.map(\.id) == overdue.map { $0["id"] as? String })
            #expect(groups.overdue.map(\.elapsedDays) == overdue.map { $0["elapsedDays"] as? Int })
            #expect(groups.overdue.map(\.overdueDays) == overdue.map { $0["overdueDays"] as? Int })
            #expect(groups.never.map(\.id) == fixture["never"] as? [String])
            #expect(groups.overdue.map(\.id).contains("people/Ada Kaya.md"))
        }
        let ada = try #require(context.store.content.entityTimeline["people/Ada Kaya.md"]?.map(\.date).max())
        #expect(ada == CalendarDate("2026-10-04"))
    }

    /// With no cadence field anywhere the list is the one `dev` computed: same people, same order.
    @Test func withoutCadenceFieldsTheListIsTheDevList() async throws {
        for vault in ["sample", "cadence"] {
            let context = try TaskTestContext(sample: false)
            defer { context.clean() }
            try FileManager.default.copyItem(
                at: fixtures().appendingPathComponent("vaults/\(vault)"), to: context.root)
            await context.start()
            var content = context.store.content
            // Names and ids sort in opposite directions; two share a name.
            for (id, name) in [("people/A.md", "Zeren"), ("people/Z.md", "Aras"), ("people/M.md", "Aras")] {
                content.entities.append(
                    EntitySummary(id: id, kind: "person", name: name, qualifier: nil, aliases: [], incomingLinks: 0))
            }
            let indexed = try await context.store.personCadences()
            if vault == "sample" { #expect(indexed.isEmpty) }
            for day in ["2026-10-03", "2026-10-11", "2027-03-01"] {
                let today = try #require(CalendarDate(day))
                for threshold in [-5, 0, 1, 9, 30, 365, 9999] {
                    let expected = devList(
                        people: content.entities, content: content, today: today, threshold: threshold)
                    var lists = [
                        UnseenPeople.compute(
                            people: content.entities, content: content, today: today, threshold: threshold)
                    ]
                    if vault == "sample" {
                        lists.append(
                            UnseenPeople.compute(
                                people: content.entities, content: content, today: today, threshold: threshold,
                                cadences: indexed))
                    }
                    for list in lists {
                        let label = Comment(rawValue: "\(vault) \(day) \(threshold)")
                        #expect(list.overdue.map(\.id) == expected.overdue.map(\.id), label)
                        #expect(list.overdue.map(\.elapsedDays) == expected.overdue.map(\.elapsed), label)
                        #expect(list.overdue.map(\.lastDay) == expected.overdue.map(\.last), label)
                        #expect(list.never.map(\.id) == expected.never, label)
                        #expect(list.never.allSatisfy { $0.elapsedDays == nil && $0.lastDay == nil }, label)
                    }
                }
            }
        }
    }

    @Test func repeatedEntityDoesNotTrap() {
        let person = EntitySummary(
            id: "people/A.md", kind: "person", name: "Aras", qualifier: nil, aliases: [], incomingLinks: 0)
        let list = UnseenPeople.compute(
            people: [person, person], content: VaultReadModel(), today: today, threshold: 30)
        #expect(list.never.map(\.id) == ["people/A.md", "people/A.md"])
    }

    @Test func draftWritesNothingUntilItDiffersFromTheFile() {
        var draft = CadenceDraft(days: nil)
        #expect(draft.choice == .none && draft.outcome == .unchanged && !draft.isDirty)
        draft.choice = .days(30)
        #expect(draft.outcome == .set(30) && draft.isDirty)
        draft.choice = .custom
        #expect(draft.outcome == .invalid && !draft.isDirty)
        for text in ["0", "-3", "7.5", "abc", "12a", "99999999999999999999", "٣٠", "030"] {
            draft.customText = text
            #expect(draft.outcome == .invalid && draft.isDirty, Comment(rawValue: text))
        }
        draft.customText = " 45 "
        #expect(draft.outcome == .set(45))
        draft.rebase(onto: 45)
        #expect(draft == CadenceDraft(days: 45))
        #expect(draft.choice == .custom && draft.customText == "45" && draft.outcome == .unchanged)
        draft.choice = .none
        #expect(draft.outcome == .clear && draft.isDirty)
        draft.choice = .days(14)
        draft.rebase(onto: 90)
        #expect(draft.choice == .days(14) && draft.outcome == .set(14))
        draft.rebase(onto: 14)
        #expect(draft == CadenceDraft(days: 14) && !draft.isDirty)
        let preset = CadenceDraft(days: 30)
        #expect(preset.choice == .days(30) && preset.customText.isEmpty)
    }

    @Test func editorWritesAndClearsOnlyTheCadenceField() async throws {
        let context = try TaskTestContext(sample: false)
        defer { context.clean() }
        await context.start()
        let path = "people/Ada Kaya.md"
        let file = context.root.appendingPathComponent(path)
        let input = try Data(contentsOf: writeCase("cadence-days-add", "input.md"))
        let expected = try Data(contentsOf: writeCase("cadence-days-add", "expected.md"))
        try input.write(to: file)
        await context.store.refresh(rebuild: true)
        let model = EntityDetailModel(store: context.store, path: path)
        await model.load()
        #expect(model.personCadence == .none)
        #expect(await model.set(PersonCadence.dayKey, to: .integer(30)) == false)
        #expect(await model.addField(key: PersonCadence.pauseKey, text: "true") == false)
        #expect(await model.remove(PersonCadence.snoozeKey) == false)
        #expect(try Data(contentsOf: file) == input)
        #expect(await model.setCadenceDays(30))
        #expect(try Data(contentsOf: file) == expected)
        #expect(model.personCadence.days == 30)
        #expect(model.fields.map(\.key) == ["tanışma"])
        #expect(await model.setCadenceDays(0) == false)
        #expect(await model.setCadenceDays(-7) == false)
        #expect(try Data(contentsOf: file) == expected)
        #expect(await model.clearCadenceDays())
        #expect(try Data(contentsOf: file) == input)
        #expect(model.personCadence == .none)
    }

    /// `cadence_days: aylık` is ignored and kept; only a chosen number replaces that one line.
    @Test func ignoredSpellingStaysUntilANumberIsChosen() async throws {
        let context = try TaskTestContext(sample: false)
        defer { context.clean() }
        await context.start()
        let path = "people/Ada Kaya.md"
        let file = context.root.appendingPathComponent(path)
        let input = try Data(contentsOf: writeCase("cadence-days-replace-text", "input.md"))
        try input.write(to: file)
        await context.store.refresh(rebuild: true)
        let model = EntityDetailModel(store: context.store, path: path)
        await model.load()
        #expect(model.personCadence == .none)
        #expect(model.fields.map(\.key) == ["tanışma"])
        var draft = CadenceDraft(days: model.personCadence.days)
        #expect(draft.choice == .none && draft.outcome == .unchanged)
        #expect(try await context.store.personCadences()[path] == nil)
        #expect(try Data(contentsOf: file) == input)
        draft.choice = .days(30)
        guard case .set(let days) = draft.outcome else {
            Issue.record("Expected a day count")
            return
        }
        #expect(await model.setCadenceDays(days))
        #expect(try Data(contentsOf: file) == Data(contentsOf: writeCase("cadence-days-replace-text", "expected.md")))
    }

    @Test func commandsWriteOneFieldAndKeepEveryOtherByte() async throws {
        let context = try TaskTestContext(sample: false)
        defer { context.clean() }
        await context.start()
        let path = "people/Ada Kaya.md"
        let file = context.root.appendingPathComponent(path)
        func place(_ name: String) async throws -> Data {
            try Data(contentsOf: writeCase(name, "input.md")).write(to: file)
            await context.store.refresh(rebuild: true)
            return try Data(contentsOf: writeCase(name, "expected.md"))
        }
        let store = context.store

        var expected = try await place("cadence-snooze-crlf-bom")
        let lateOctober = CalendarDate("2026-10-25")!
        #expect(await UnseenCadenceCommand.snoozeWeek.apply(path: path, today: lateOctober, store: store) == nil)
        #expect(try Data(contentsOf: file) == expected)

        // An earlier snooze is replaced in place; its spacing and trailing comment stay.
        expected = try await place("cadence-snooze-replace")
        #expect(await UnseenCadenceCommand.snoozeMonth.apply(path: path, today: today, store: store) == nil)
        #expect(try Data(contentsOf: file) == expected)
        #expect(await UnseenCadenceCommand.snoozeMonth.apply(path: path, today: today, store: store) == nil)
        #expect(try Data(contentsOf: file) == expected)

        expected = try await place("cadence-paused-add")
        #expect(await UnseenCadenceCommand.pause.apply(path: path, today: today, store: store) == nil)
        #expect(try Data(contentsOf: file) == expected)
        #expect(try await store.personCadences()[path]?.isPaused == true)

        expected = try await place("cadence-paused-replace-text")
        #expect(await UnseenCadenceCommand.pause.apply(path: path, today: today, store: store) == nil)
        #expect(try Data(contentsOf: file) == expected)

        expected = try await place("cadence-paused-remove")
        #expect(await UnseenCadenceCommand.resume(path: path, store: store) == nil)
        #expect(try Data(contentsOf: file) == expected)
        #expect(await UnseenCadenceCommand.resume(path: path, store: store) == nil)
        #expect(try Data(contentsOf: file) == expected)

        expected = try await place("cadence-snooze-remove-middle")
        let model = EntityDetailModel(store: store, path: path)
        await model.load()
        #expect(model.personCadence.isPaused)
        #expect(await model.resumeCadence())
        #expect(try Data(contentsOf: file) == expected)
        let kept = PersonCadence(days: 30, snoozedUntil: CalendarDate("2026-10-01"), isPaused: false)
        #expect(model.personCadence == kept)
    }

    /// A block Obsidian cannot read the same way is never written; a file with no block gets one.
    @Test func unreadableBlockIsRefusedAndMissingBlockIsAdded() async throws {
        let context = try TaskTestContext(sample: false)
        defer { context.clean() }
        await context.start()
        let path = "people/Ada Kaya.md"
        let file = context.root.appendingPathComponent(path)
        let twice = Data("---\ntype: person\nname: Ada Kaya\ncadence_days: 7\ncadence_days: 30\n---\nNot.\n".utf8)
        try twice.write(to: file)
        await context.store.refresh(rebuild: true)
        for command in UnseenCadenceCommand.allCases {
            #expect(await command.apply(path: path, today: today, store: context.store) != nil)
        }
        #expect(await UnseenCadenceCommand.resume(path: path, store: context.store) != nil)
        let model = EntityDetailModel(store: context.store, path: path)
        await model.load()
        #expect(model.unreadableFrontmatter)
        #expect(await model.setCadenceDays(30) == false)
        #expect(await model.clearCadenceDays() == false)
        #expect(try Data(contentsOf: file) == twice)

        try Data("Not.\r\n".utf8).write(to: file)
        await context.store.refresh(rebuild: true)
        #expect(await UnseenCadenceCommand.pause.apply(path: path, today: today, store: context.store) == nil)
        let written = try Data(contentsOf: file)
        #expect(written.suffix(6) == Data("Not.\r\n".utf8))
        let document = try await context.store.document(at: path)
        if case .parsed(let frontmatter) = document.frontmatter {
            #expect(frontmatter.fields.map(\.key) == [PersonCadence.pauseKey])
        } else {
            Issue.record("Expected a new block")
        }
    }

    /// Rhythm belongs to people. Elsewhere the three keys are fields like any other.
    @Test func cadenceKeysAreOrdinaryFieldsOutsidePeople() async throws {
        let context = try TaskTestContext(sample: false)
        defer { context.clean() }
        await context.start()
        let path = "places/Kıyı.md"
        let file = context.root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = Data(
            "---\ntype: place\nname: Kıyı\ncadence_days: 30\ncadence_snoozed_until: 2026-11-01\ncadence_paused: true\n---\n"
                .utf8)
        try bytes.write(to: file)
        await context.store.refresh(rebuild: true)
        #expect(try await context.store.personCadences()[path] == nil)
        let model = EntityDetailModel(store: context.store, path: path)
        await model.load()
        #expect(model.personCadence == .none)
        #expect(model.fields.map(\.key) == PersonCadence.keys)
        #expect(await model.setCadenceDays(7) == false)
        #expect(await model.clearCadenceDays() == false)
        #expect(await model.resumeCadence() == false)
        #expect(try Data(contentsOf: file) == bytes)
        #expect(await model.remove(PersonCadence.pauseKey))
        #expect(model.fields.map(\.key) == [PersonCadence.dayKey, PersonCadence.snoozeKey])
    }

    @Test func snoozeDayFollowsTheCalendarAndTheUsersZone() throws {
        func day(_ text: String) -> CalendarDate { CalendarDate(text)! }
        #expect(UnseenCadenceCommand.snoozeWeek.until(from: day("2026-12-28")) == day("2027-01-04"))
        #expect(UnseenCadenceCommand.snoozeMonth.until(from: day("2026-01-31")) == day("2026-02-28"))
        #expect(UnseenCadenceCommand.snoozeMonth.until(from: day("2028-01-31")) == day("2028-02-29"))
        #expect(UnseenCadenceCommand.snoozeMonth.until(from: day("2026-12-31")) == day("2027-01-31"))
        #expect(UnseenCadenceCommand.snoozeMonth.until(from: day("2026-10-11")) == day("2026-11-11"))
        #expect(UnseenCadenceCommand.pause.until(from: today) == nil)

        // One instant, two calendar days: each user snoozes from the day they are living.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let instant = try #require(
            utc.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 11, minute: 30)))
        let auckland = try #require(TimeZone(identifier: "Pacific/Auckland"))
        let honolulu = try #require(TimeZone(identifier: "Pacific/Honolulu"))
        let east = LocalDay.today(at: instant, timeZone: auckland)
        let west = LocalDay.today(at: instant, timeZone: honolulu)
        #expect(east == day("2026-10-12") && west == day("2026-10-11"))
        #expect(UnseenCadenceCommand.snoozeWeek.until(from: east) == day("2026-10-19"))
        #expect(UnseenCadenceCommand.snoozeWeek.until(from: west) == day("2026-10-18"))

        // The stored day is shown as that day in every zone.
        let cadence = PersonCadence(days: nil, snoozedUntil: day("2026-11-01"), isPaused: false)
        let english = Locale(identifier: "en_US")
        let lines = [auckland, honolulu, zone].map {
            CadenceStatusPresentation(cadence: cadence, today: today, locale: english, timeZone: $0).snooze
        }
        #expect(lines == Array(repeating: "Snoozed until Nov 1", count: 3))
    }

    @Test func menuSelectionAndStatusLinesFollowLocale() {
        #expect(CadenceMenuValue.selection(for: nil) == .none)
        #expect(CadenceMenuValue.selection(for: 14) == .days(14))
        #expect(CadenceMenuValue.selection(for: 45) == .custom)
        let cadence = PersonCadence(
            days: 30, snoozedUntil: CalendarDate("2026-11-01"), isPaused: true)
        let turkishLocale = Locale(identifier: "tr_TR")
        let englishLocale = Locale(identifier: "en_US")
        let turkish = CadenceStatusPresentation(cadence: cadence, today: today, locale: turkishLocale, timeZone: zone)
        #expect(turkish.rhythm == "Ritim: 30 günde bir")
        #expect(turkish.snooze == "1 Kas tarihine kadar ertelendi")
        #expect(turkish.paused == "Duraklatıldı")
        #expect(turkish.showsResume)
        let english = CadenceStatusPresentation(cadence: cadence, today: today, locale: englishLocale, timeZone: zone)
        #expect(english.rhythm == "Cadence: every 30 days")
        #expect(english.snooze == "Snoozed until Nov 1")
        #expect(english.paused == "Paused")
        let daily = PersonCadence(days: 1, snoozedUntil: nil, isPaused: false)
        #expect(
            CadenceStatusPresentation(cadence: daily, today: today, locale: englishLocale, timeZone: zone).rhythm
                == "Cadence: every day")
        #expect(
            CadenceStatusPresentation(cadence: daily, today: today, locale: turkishLocale, timeZone: zone).rhythm
                == "Ritim: 1 günde bir")
        let expired = PersonCadence(
            days: nil, snoozedUntil: CalendarDate("2026-10-11"), isPaused: false)
        let after = CadenceStatusPresentation(
            cadence: expired, today: CalendarDate("2026-10-12")!, locale: englishLocale, timeZone: zone)
        #expect(after.snooze == nil && after.showsResume == false && after.rhythm == nil)
        let inclusive = CadenceStatusPresentation(cadence: expired, today: today, locale: englishLocale, timeZone: zone)
        #expect(inclusive.snooze != nil)
    }

    /// The list as `dev` computed it before cadence existed, kept here as the yardstick.
    private func devList(
        people: [EntitySummary], content: VaultReadModel, today: CalendarDate, threshold: Int
    ) -> (overdue: [(id: String, elapsed: Int?, last: CalendarDate?)], never: [String]) {
        var overdue: [(id: String, elapsed: Int?, last: CalendarDate?)] = []
        var never: [(id: String, name: String)] = []
        for entity in people where entity.kind == "person" {
            let last = content.entityTimeline[entity.id]?.map(\.date).filter { $0 <= today }.max()
            if let last {
                let elapsed = today.ordinal - last.ordinal
                if elapsed >= PeopleInsightsPreference.normalized(threshold) {
                    overdue.append((entity.id, elapsed, last))
                }
            } else {
                never.append((entity.id, entity.name))
            }
        }
        overdue.sort {
            if $0.elapsed != $1.elapsed { return $0.elapsed! > $1.elapsed! }
            return $0.id < $1.id
        }
        never.sort { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
        return (overdue, never.map(\.id))
    }

    private func fixtures() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures")
    }

    private func writeCase(_ name: String, _ file: String) -> URL {
        fixtures().appendingPathComponent("write/\(name)/\(file)")
    }
}
