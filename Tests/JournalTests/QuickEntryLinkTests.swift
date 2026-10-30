import AppIntents
import Foundation
import Testing

@testable import Journal

@MainActor @Suite("Quick entry links", .serialized)
struct QuickEntryLinkTests {
    @Test func writeRoundTrips() throws {
        #expect(WidgetLink.write.url.absoluteString == "kenet-widget://write")
        #expect(WidgetLink(url: WidgetLink.write.url) == .write)
        #expect(WidgetKinds.all.contains(WidgetKinds.quickEntry))
        #expect(Set(WidgetKinds.all).count == WidgetKinds.all.count)
    }

    @Test(arguments: [
        "https://write", "kenet-widget://unknown", "kenet-widget://write/path",
        "kenet-widget://write?goal=x", "kenet-widget://write#fragment",
        "kenet-widget://user@write", "kenet-widget://write:42",
    ])
    func malformedWriteIsRejected(_ value: String) throws {
        #expect(WidgetLink(url: try #require(URL(string: value))) == nil)
    }

    @Test func writeOpensTodayAndRequestsFocusEveryTime() async throws {
        let context = try TaskTestContext(sample: false)
        defer { context.clean() }
        let navigation = IntentNavigation()
        var opens = 0
        navigation.onOpenToday = { opens += 1 }
        let handler = WidgetLinkHandler(
            actions: IntentActions(store: context.store, permitsStart: { false }), navigation: navigation)
        #expect(await handler.open(WidgetLink.write.url))
        let first = try #require(navigation.focusRequest)
        #expect(navigation.todayRequest != nil)
        #expect(opens == 1)
        #expect(await handler.open(WidgetLink.write.url))
        #expect(navigation.focusRequest != first)
        #expect(opens == 2)
    }

    @Test func lockedWriteWaitsForUnlock() async throws {
        let context = try TaskTestContext(sample: false)
        defer { context.clean() }
        let navigation = IntentNavigation()
        var locked = true
        let actions = IntentActions(store: context.store, permitsStart: { false }, isLocked: { locked })
        let handler = WidgetLinkHandler(actions: actions, navigation: navigation)
        #expect(await handler.open(WidgetLink.write.url))
        #expect(navigation.pendingFocus)
        #expect(navigation.focusRequest == nil)
        #expect(navigation.todayRequest == nil)
        await handler.unlocked()
        #expect(navigation.pendingFocus)
        locked = false
        await handler.unlocked()
        #expect(!navigation.pendingFocus)
        let request = try #require(navigation.focusRequest)
        #expect(navigation.todayRequest != nil)
        await handler.unlocked()
        #expect(navigation.focusRequest == request)
    }

    @Test func intentRequestsTheSameComposerAndDefersWhileLocked() async throws {
        let actions = IntentActions.shared
        let oldLock = actions.isLocked
        defer { actions.isLocked = oldLock }
        let navigation = IntentNavigation.shared
        let previous = navigation.focusRequest
        actions.isLocked = { true }
        _ = try await OpenQuickEntryIntent().perform()
        #expect(navigation.pendingFocus)
        #expect(navigation.focusRequest == previous)
        actions.isLocked = { false }
        navigation.unlocked()
        let unlocked = try #require(navigation.focusRequest)
        #expect(!navigation.pendingFocus)
        _ = try await OpenQuickEntryIntent().perform()
        #expect(navigation.focusRequest != unlocked)
        #expect(OpenQuickEntryIntent.openAppWhenRun)
    }

    @Test func publishingReloadsTheQuickEntryKind() async throws {
        let harness = try WidgetSnapshotTests.Harness()
        defer { harness.context.clean() }
        await harness.start()
        #expect(harness.timelines.reloads.contains("QuickEntryWidget"))
        #expect(harness.timelines.reloads.contains("GoalChainWidget"))
    }

    @Test func ordinaryTodayDoesNotRequestWriting() async throws {
        let context = try TaskTestContext(sample: false)
        defer { context.clean() }
        let navigation = IntentNavigation()
        let handler = WidgetLinkHandler(
            actions: IntentActions(store: context.store, permitsStart: { false }), navigation: navigation)
        #expect(await handler.open(WidgetLink.today.url))
        #expect(navigation.todayRequest != nil)
        #expect(navigation.focusRequest == nil)
        #expect(!(await handler.open(try #require(URL(string: "https://example.invalid/write")))))
    }
}
