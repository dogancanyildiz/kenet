import Foundation
import GoalTracking
import Testing
import VaultFormat

@testable import Journal

@MainActor @Suite("Intent actions")
struct IntentActionsTests {
    private let instant = notificationDate("2026-10-04", hour: 12)
    func actions(_ context: TaskTestContext, allowed: Bool = true) -> IntentActions {
        let date = instant
        return IntentActions(store: context.store, now: { date }, permitsStart: { allowed })
    }
    func document(_ context: TaskTestContext) throws -> RawDocument {
        RawDocument(
            bytes: try Data(
                contentsOf: context.root.appendingPathComponent("journal/\(LocalDay.today(at: instant)).md")))
    }

    @Test func coldEventWritesExactBytesAndReturnsVisibleText() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        let result = try await actions(context).addEvent(
            text: "@Deniz ile @Liman Ofis'te", time: try LineClock(hour: 13, minute: 0))
        let document = try document(context)
        let identifier = try #require(document.bodyLines.events.first?.block.id)
        let day = LocalDay.today(at: instant)
        let expected =
            "---\ntype: journal\ndate: \(day)\n---\n\n## Events\n- 13:00 [[Deniz Arıkan|Deniz]] ile [[Liman Ofis]]'te ^\(identifier)\n"
        #expect(document.serialized() == Array(expected.utf8))
        #expect(result.text == String(localized: "Olay eklendi: \("Deniz ile Liman Ofis'te")"))
        #expect(context.store.content.day(on: day).events.last?.text.plainText == "Deniz ile Liman Ofis'te")
    }

    @Test func defaultClockUsesTheSameLocalDay() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        _ = try await actions(context).addEvent(text: "Yazdım")
        let clock = LocalDay.clock(at: instant)
        let event = try #require(document(context).bodyLines.events.first)
        #expect(event.time?.hour == clock.hour)
        #expect(event.time?.minute == clock.minute)
    }

    @Test func taskParsesTurkishDateAndLinksMentions() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        let result = try await actions(context).addTask(text: "yarın @Deniz'i ara")
        let task = try #require(document(context).bodyLines.tasks.first)
        #expect(task.text == "[[Deniz Arıkan|Deniz]]'i ara")
        #expect(task.dueDate == LocalDay.today(at: instant).addingDays(1))
        #expect(result.text == String(localized: "Görev eklendi: \("Deniz'i ara")"))
    }

    @Test func assumedDateIsNotAppliedWithoutConfirmation() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        var asked = 0
        let result = try await actions(context).addTask(text: "oct 5 buy milk") { _ in
            asked += 1
            return false
        }
        let task = try #require(document(context).bodyLines.tasks.first)
        #expect(asked == 1)
        #expect(task.dueDate == nil)
        #expect(task.text == "oct 5 buy milk")
        #expect(result.text == String(localized: "Görev eklendi: \("oct 5 buy milk")"))
        #expect(!String(decoding: try document(context).serialized(), as: UTF8.self).contains("📅"))
    }

    @Test func assumedDateWithoutConfirmChannelKeepsExpression() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        _ = try await actions(context).addTask(text: "oct 5 buy milk")
        let task = try #require(document(context).bodyLines.tasks.first)
        #expect(task.dueDate == nil)
        #expect(task.text == "oct 5 buy milk")
    }

    @Test func assumedDateAppliesOnlyAfterConfirmation() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        var asked = 0
        _ = try await actions(context).addTask(text: "oct 5 buy milk") { date in
            asked += 1
            #expect(date == CalendarDate("2026-10-05"))
            return true
        }
        let task = try #require(document(context).bodyLines.tasks.first)
        #expect(asked == 1)
        #expect(task.dueDate == CalendarDate("2026-10-05"))
        #expect(task.text == "buy milk")
    }

    @Test func exactDateAppliesWithoutAskingConfirmation() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        var asked = 0
        _ = try await actions(context).addTask(text: "tomorrow buy milk") { _ in
            asked += 1
            return true
        }
        let task = try #require(document(context).bodyLines.tasks.first)
        #expect(asked == 0)
        #expect(task.dueDate == LocalDay.today(at: instant).addingDays(1))
        #expect(task.text == "buy milk")
    }

    @Test func explicitTaskDateOverridesExpression() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        let date = CalendarDate("2026-11-05")!
        _ = try await actions(context).addTask(text: "tomorrow @Deniz ile görüş", due: date)
        let task = try #require(document(context).bodyLines.tasks.first)
        #expect(task.dueDate == date)
        #expect(task.text == "[[Deniz Arıkan|Deniz]] ile görüş")
        #expect(String(decoding: try document(context).serialized(), as: UTF8.self).contains("📅 2026-11-05"))
    }

    @Test func ambiguousAndUnknownMentionsStayPlainWithoutCreatingEntities() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let count = context.store.content.entities.count
        let result = try await actions(context).addEvent(text: "@Mert Aksu ve @Yeni Kişi ile görüş")
        let event = try #require(document(context).bodyLines.events.first)
        #expect(event.block.text == "Mert Aksu ve Yeni Kişi ile görüş")
        #expect(context.store.content.entities.count == count)
        #expect(!result.text.contains("@"))
    }

    @Test func lowercaseSuggestionIsNotLinkedAndExistingLinksArePreserved() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        _ = try await actions(context).addEvent(text: "deniz ile [[Liman Ofis]]'te")
        #expect(try document(context).bodyLines.events.first?.block.text == "deniz ile [[Liman Ofis]]'te")
    }

    @Test func booleanAndNumericGoalsPreserveNeighborBytes() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        let actions = actions(context)
        let goals = try await actions.goals()
        let sport = try #require(goals.first { $0.definition.key == "spor" })
        let water = try #require(goals.first { $0.definition.key == "su" })
        let file = context.root.appendingPathComponent("journal/\(LocalDay.today(at: instant)).md")
        let original =
            "---\ntype: journal\ndate: \(LocalDay.today(at: instant))\ncustom: retain\ngoals:\n  untouched: 4 # keep\n---\n\n## Journal\nKeep this paragraph.\n"
        try Data(original.utf8).write(to: file)
        let result = try await actions.markGoal(id: sport.id)
        _ = try await actions.markGoal(id: water.id, amount: 3.5)
        let text = String(decoding: try document(context).serialized(), as: UTF8.self)
        #expect(text.contains("  spor: true"))
        #expect(text.contains("  su: 3.5"))
        #expect(text.contains("  untouched: 4 # keep"))
        #expect(text.contains("custom: retain"))
        #expect(text.hasSuffix("## Journal\nKeep this paragraph.\n"))
        #expect(result.text == String(localized: "Hedef kaydedildi: \("Spor")"))
    }

    @Test(arguments: [Double.nan, Double.infinity, -1])
    func invalidNumericAmountDoesNotWrite(_ amount: Double) async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        let actions = actions(context)
        let goal = try #require(try await actions.goals().first { $0.definition.key == "su" })
        await #expect(throws: IntentActionError.invalidAmount) {
            try await actions.markGoal(id: goal.id, amount: amount)
        }
        #expect(
            !FileManager.default.fileExists(
                atPath: context.root.appendingPathComponent("journal/\(LocalDay.today(at: instant)).md").path))
    }

    @Test func missingAmountAndStaleGoalAreErrors() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        let actions = actions(context)
        let goal = try #require(try await actions.goals().first { $0.definition.key == "su" })
        await #expect(throws: IntentActionError.invalidAmount) { try await actions.markGoal(id: goal.id) }
        await #expect(throws: IntentActionError.goalMissing) { try await actions.markGoal(id: "unknown") }
    }

    @Test func unavailableVaultDoesNotCreateDefaultVault() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let actions = actions(context)
        await #expect(throws: IntentActionError.vaultUnavailable) { try await actions.addEvent(text: "Kayıt") }
        #expect(!FileManager.default.fileExists(atPath: context.root.path))
        #expect(context.store.vaultURL == nil)
    }

    @Test func lockedAppBlocksWritesAndGoalListing() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        let file = context.root.appendingPathComponent("journal/\(LocalDay.today(at: instant)).md")
        let original =
            "---\ntype: journal\ndate: \(LocalDay.today(at: instant))\ncustom: retain\ngoals:\n  untouched: 4 # keep\n---\n\n## Journal\nKeep this paragraph.\n"
        try Data(original.utf8).write(to: file)
        let locked = IntentActions(
            store: context.store, now: { instant }, permitsStart: { true }, isLocked: { true })
        #expect(try await locked.goals().isEmpty)
        await #expect(throws: IntentActionError.appLocked) { try await locked.addEvent(text: "Secret entry") }
        await #expect(throws: IntentActionError.appLocked) { try await locked.addTask(text: "Secret task") }
        await #expect(throws: IntentActionError.appLocked) { try await locked.markGoal(id: "any") }
        #expect(try Data(contentsOf: file) == Data(original.utf8))
        let unlocked = IntentActions(
            store: context.store, now: { instant }, permitsStart: { true }, isLocked: { false })
        let goals = try await unlocked.goals()
        let sport = try #require(goals.first { $0.definition.key == "spor" })
        _ = try await unlocked.markGoal(id: sport.id)
        #expect(String(decoding: try document(context).serialized(), as: UTF8.self).contains("  spor: true"))
    }

    @Test func lockedGoalEntityQueryReturnsEmpty() async throws {
        let previous = IntentActions.shared.isLocked
        IntentActions.shared.isLocked = { true }
        defer { IntentActions.shared.isLocked = previous }
        let query = GoalEntityQuery()
        #expect(try await query.suggestedEntities().isEmpty)
        #expect(try await query.entities(matching: "Spor").isEmpty)
        #expect(try await query.entities(for: ["any-id"]).isEmpty)
    }

    @Test func brokenBookmarkDoesNotFallBackAndLaunchPolicyIsRespected() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        context.defaults.defaults.set(Data("/missing-intent-vault".utf8), forKey: "vaultBookmark")
        await #expect(throws: IntentActionError.vaultUnavailable) { try await actions(context).addTask(text: "Ara") }
        #expect(context.store.vaultURL == nil)
        await #expect(throws: IntentActionError.vaultUnavailable) { try await actions(context, allowed: false).goals() }
    }

    @Test func readOnlyDayFailsWithoutChangingBytes() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let file = context.root.appendingPathComponent("journal/\(LocalDay.today(at: instant)).md")
        let bytes = Data([0xff, 0xfe, 0x00])
        try bytes.write(to: file)
        await #expect(throws: IntentActionError.writeFailed) { try await actions(context).addEvent(text: "Yeni") }
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func whitespaceOrDateOnlyTaskIsRejected() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await #expect(throws: IntentActionError.emptyText) { try await actions(context).addEvent(text: " \n") }
        await #expect(throws: IntentActionError.emptyText) { try await actions(context).addTask(text: "yarın") }
    }

    @Test func openTodayReplacesPreviousNotificationRoute() {
        let navigation = IntentNavigation()
        let center = FakeNotificationCenter()
        let notifications = NotificationService(center: center)
        notifications.activateAutomatically(environment: [:], arguments: [])
        center.response?(.tasks)
        #expect(notifications.navigationRequest != nil)
        navigation.onOpenToday = { notifications.clearNavigationRequest() }
        navigation.openToday()
        let first = navigation.todayRequest
        #expect(first != nil)
        #expect(notifications.navigationRequest == nil)
        navigation.openToday()
        #expect(navigation.todayRequest != first)
    }

    @Test func staleSelectionCannotMarkSameKeyInAnotherVault() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        let actions = actions(context)
        let goal = try #require(try await actions.goals().first { $0.definition.key == "spor" })
        let other = context.directory.appendingPathComponent("Other")
        try FileManager.default.copyItem(at: context.root, to: other)
        await context.store.select(other)
        await #expect(throws: IntentActionError.goalMissing) { try await actions.markGoal(id: goal.id) }
        #expect(
            !FileManager.default.fileExists(
                atPath: other.appendingPathComponent("journal/\(LocalDay.today(at: instant)).md").path))
    }
}
