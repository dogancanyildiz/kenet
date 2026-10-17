import Foundation
import GoalTracking
import Testing
import VaultFormat

@testable import Journal

#if os(iOS)
    import UIKit
#endif

@MainActor
struct DefinitionMenuTests {
    @Test(arguments: ["person", "place", "book"])
    func entityMenu(_ kind: String) {
        let entity = EntitySummary(
            id: "entities/Lale.md", kind: kind, name: "Lale", qualifier: nil, aliases: [], incomingLinks: 0)
        #expect(DefinitionMenu.items(forEntity: entity) == [.edit, .copyLink, .delete])
    }

    @Test func booleanMenuFollowsToday() {
        #expect(DefinitionMenu.items(forGoal: .boolean, markedToday: false) == [.markToday, .edit, .delete])
        #expect(DefinitionMenu.items(forGoal: .boolean, markedToday: true) == [.unmark, .edit, .delete])
    }

    @Test(arguments: [false, true])
    func numberAndMilestoneMenusIgnoreMark(_ marked: Bool) {
        #expect(DefinitionMenu.items(forGoal: .number, markedToday: marked) == [.enterAmount, .edit, .delete])
        #expect(DefinitionMenu.items(forGoal: .milestone, markedToday: marked) == [.edit, .delete])
    }

    @Test func goalMenusKeepDeletionLastAndHaveNoLink() {
        for kind in [GoalKind.boolean, .number, .milestone] {
            for marked in [false, true] {
                let items = DefinitionMenu.items(forGoal: kind, markedToday: marked)
                #expect(items.last == .delete)
                #expect(!items.contains(.copyLink))
                #expect(items.count <= 5)
                #expect(items.map(\.group) == items.map(\.group).sorted())
            }
        }
    }

    @Test(arguments: ["Lale", "Kıyı Kafe", "Lale (iş)", "I\u{307}pek", ""])
    func wikilinkKeepsNameExactly(_ name: String) {
        #expect(DefinitionMenu.link(for: name) == "[[" + name + "]]")
    }

    @Test func rowMarkUsesTodayRatherThanPeriodCompletion() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        let goal = try #require(context.store.content.goals.first { $0.kind == .boolean })
        let day = try #require(CalendarDate(year: 2026, month: 9, day: 27))
        let model = GoalDayModel(store: context.store, day: day)
        await model.load()
        #expect(model.status(for: goal).progress.isComplete)
        #expect(
            DefinitionMenu.items(forGoal: goal.kind, markedToday: model.isMarkedToday(goal)).first
                == .markToday)
        #expect(await model.toggle(goal))
        #expect(
            DefinitionMenu.items(forGoal: goal.kind, markedToday: model.isMarkedToday(goal)).first
                == .unmark)
        #expect(await model.toggle(goal))
        #expect(model.value(for: goal) == nil)
    }

    @Test(arguments: [false, true])
    func rowDeletionConfirmsCapturedPathAndKeepsJournal(_ goal: Bool) async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        let path = goal ? "goals/Spor.md" : context.path
        let journal = context.root.appendingPathComponent("journal/2026-09-27.md")
        let before = try Data(contentsOf: journal)
        let model = DefinitionDeletionModel()
        model.request(path: path)
        model.confirmation.cancel()
        #expect(FileManager.default.fileExists(atPath: context.root.appendingPathComponent(path).path))
        model.request(path: path)
        let confirmedPath = model.confirmation.confirm()
        let confirmed = try #require(confirmedPath)
        #expect(confirmed == path)
        #expect(await model.delete(store: context.store, path: confirmed, goal: goal))
        #expect(!FileManager.default.fileExists(atPath: context.root.appendingPathComponent(path).path))
        #expect(context.store.content.entities.allSatisfy { $0.id != path })
        #expect(context.store.content.goals.allSatisfy { $0.id != path })
        #expect(try Data(contentsOf: journal) == before)
        // Another row's delete starts with a new model, including after a successful delete.
        let next = DefinitionDeletionModel()
        let nextPath = goal ? context.path : "goals/Spor.md"
        next.request(path: nextPath)
        let nextConfirmed = next.confirmation.confirm()
        #expect(nextConfirmed == nextPath)
        #expect(await next.delete(store: context.store, path: nextPath, goal: !goal))
    }

    #if os(iOS)
        @Test func copyLinkWritesPasteboard() {
            let previous = UIPasteboard.general.items
            defer { UIPasteboard.general.items = previous }
            DefinitionMenu.copyLink(for: "Kıyı Kafe")
            #expect(UIPasteboard.general.string == "[[Kıyı Kafe]]")
        }
    #endif
}
