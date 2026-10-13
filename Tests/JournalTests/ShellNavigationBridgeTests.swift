import Foundation
import Testing
import VaultFormat

@testable import Journal

/// The bridge between the two shells (`ShellNavigationState`): the tab and the section are one
/// selection, a Siri or notification route is handled once, and the drafts are kept per day.
@MainActor struct ShellNavigationBridgeTests {
    // MARK: - Tab and section

    /// Choosing a tab opens the section it holds, and the section reads back as that tab.
    @Test func choosingATabOpensItsSection() {
        let bridge = ShellNavigationState()
        #expect(bridge.selectedTab == .today)
        bridge.selectedTab = .tasks
        #expect(bridge.section == .tasks)
        bridge.selectedTab = .entities
        #expect(bridge.section == .people)
        bridge.selectedTab = .goals
        #expect(bridge.section == .goals)
        bridge.selectedTab = .days
        #expect(bridge.section == .days)
        #expect(bridge.selectedTab == .days)
    }

    /// A section chosen in the split shell shows as the tab that holds it, and choosing that
    /// same tab again keeps the section (Konumlar does not fall back to Kişiler).
    @Test func sectionWithoutATabKeepsItselfBehindItsTab() {
        let bridge = ShellNavigationState()
        bridge.section = .places
        #expect(bridge.selectedTab == .entities)
        bridge.selectedTab = .entities
        #expect(bridge.section == .places)
        bridge.section = .summaries
        #expect(bridge.selectedTab == .days)
        bridge.selectedTab = .days
        #expect(bridge.section == .summaries)
        bridge.selectedTab = .today
        #expect(bridge.section == .today)
    }

    /// No section (the sidebar deselected) reads as the Today tab.
    @Test func noSectionReadsAsToday() {
        let bridge = ShellNavigationState()
        bridge.section = nil
        #expect(bridge.selectedTab == .today)
        bridge.selectedTab = .today
        #expect(bridge.section == .today)
    }

    // MARK: - Routes handled once

    /// The first shell handles a request; a shell built later sees the same id and does not.
    @Test func aRouteIsHandledOncePerRequest() {
        let bridge = ShellNavigationState()
        #expect(!bridge.claimTodayRequest(nil), "no request to handle")
        let first = UUID()
        #expect(bridge.claimTodayRequest(first))
        #expect(!bridge.claimTodayRequest(first), "the next shell leaves a handled request alone")
        let second = UUID()
        #expect(bridge.claimTodayRequest(second), "a new request is handled")
        #expect(!bridge.claimTodayRequest(second))

        #expect(!bridge.claimNavigationRequest(nil))
        let notification = UUID()
        #expect(bridge.claimNavigationRequest(notification))
        #expect(!bridge.claimNavigationRequest(notification))
        #expect(bridge.claimNavigationRequest(UUID()))
    }

    /// The two kinds of request are counted apart: a notification id does not stand for Siri's.
    @Test func todayAndNotificationRequestsAreClaimedApart() {
        let bridge = ShellNavigationState()
        let id = UUID()
        #expect(bridge.claimTodayRequest(id))
        #expect(bridge.claimNavigationRequest(id))
    }

    // MARK: - Drafts

    /// A day page gets the same quick entry model back for its day (`nil` is Today), and another
    /// day its own; the model is made once.
    @Test func quickEntryDraftIsKeptPerDay() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let bridge = ShellNavigationState()
        var made = 0
        let make = {
            made += 1
            return QuickEntryModel(store: context.store)
        }
        let today = bridge.quickEntryDraft(for: nil, store: context.store, make: make)
        today.text = "Duo taslağı"
        #expect(bridge.quickEntryDraft(for: nil, store: context.store, make: make) === today)
        #expect(bridge.quickEntryDraft(for: nil, store: context.store, make: make).text == "Duo taslağı")
        #expect(made == 1, "the model is made once")

        let day = CalendarDate("2026-10-01")!
        let past = bridge.quickEntryDraft(for: day, store: context.store) {
            QuickEntryModel(store: context.store, day: day)
        }
        #expect(past !== today)
        #expect(bridge.quickEntryDraft(for: day, store: context.store, make: make) === past)
        #expect(made == 1)
    }

    /// Letting a model go frees its day; a model that is not the one kept changes nothing.
    @Test func quickEntryDraftIsReleasedOnlyWhileItIsTheOneKept() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let bridge = ShellNavigationState()
        let day = CalendarDate("2026-10-01")!
        let make = { QuickEntryModel(store: context.store, day: day) }
        let kept = bridge.quickEntryDraft(for: day, store: context.store, make: make)
        bridge.releaseQuickEntryDraft(make())
        #expect(
            bridge.quickEntryDraft(for: day, store: context.store, make: make) === kept, "a stranger changes nothing")
        bridge.releaseQuickEntryDraft(kept)
        #expect(bridge.quickEntryDraft(for: day, store: context.store, make: make) !== kept, "released: a new one")
    }

    /// The journal editor model is kept per day, made once by the editor on screen, and let go
    /// when its editor closes.
    @Test func journalDraftIsKeptPerDayUntilReleased() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let bridge = ShellNavigationState()
        let day = CalendarDate("2026-10-01")!
        var made = 0
        let make = {
            made += 1
            return JournalEditorModel(store: context.store, day: day)
        }
        let draft = bridge.journalDraft(for: day, store: context.store, make: make)
        draft.text = "Köprü taslağı"
        #expect(bridge.journalDraft(for: day, store: context.store, make: make) === draft)
        #expect(bridge.journalDraft(for: day, store: context.store, make: make).text == "Köprü taslağı")
        #expect(made == 1, "the model is made once")
        let other = CalendarDate("2026-10-02")!
        #expect(
            bridge.journalDraft(for: other, store: context.store) {
                JournalEditorModel(store: context.store, day: other)
            }
                !== draft)
        bridge.releaseJournalDraft(JournalEditorModel(store: context.store, day: day))
        #expect(bridge.journalDraft(for: day, store: context.store, make: make) === draft, "a stranger changes nothing")
        #expect(bridge.holdsJournalDraft(for: day, store: context.store))
        bridge.releaseJournalDraft(draft)
        #expect(!bridge.holdsJournalDraft(for: day, store: context.store))
        #expect(bridge.journalDraft(for: day, store: context.store, make: make) !== draft)
    }

    /// Closing the editor's route lets the day's model go with it; another page's route, or a
    /// route already closed, changes nothing.
    @Test func closingTheRouteReleasesTheDaysDraft() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let bridge = ShellNavigationState()
        let day = CalendarDate("2026-10-01")!
        let route = JournalEditorRoute(day: day, isToday: false)
        bridge.journalEditor = route
        let draft = bridge.journalDraft(for: day, store: context.store) {
            JournalEditorModel(store: context.store, day: day)
        }
        draft.text = "Kirli"
        bridge.closeJournalEditor(JournalEditorRoute(day: day, isToday: true))
        #expect(bridge.journalEditor == route, "another page's route is not this one")
        #expect(bridge.holdsJournalDraft(for: day, store: context.store))
        bridge.closeJournalEditor(route)
        #expect(bridge.journalEditor == nil)
        #expect(!bridge.holdsJournalDraft(for: day, store: context.store), "the model went with the route")
        bridge.closeJournalEditor(route)
        #expect(bridge.journalEditor == nil)
    }

    /// Drafts belong to the vault they were typed for: a journal left dirty and Today's quick
    /// entry text in vault A are not what vault B's pages get. The vault opening (none before,
    /// one now) is the same session and keeps what was typed while it opened.
    @Test func anotherVaultDropsTheDrafts() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let bridge = ShellNavigationState()
        let quick = bridge.quickEntryDraft(for: nil, store: context.store) { QuickEntryModel(store: context.store) }
        quick.text = "Hızlı giriş A"
        #expect(context.store.vaultURL == nil, "typed before the vault opened")
        await context.start()
        #expect(context.store.vaultURL != nil)
        #expect(
            bridge.quickEntryDraft(for: nil, store: context.store) { QuickEntryModel(store: context.store) } === quick,
            "the vault opening keeps the draft")

        let day = context.today
        let journal = bridge.journalDraft(for: day, store: context.store) {
            JournalEditorModel(store: context.store, day: day)
        }
        await journal.load()
        #expect(journal.isLoaded)
        journal.text = "A metni"
        #expect(journal.isDirty)

        let other = context.directory.appendingPathComponent("Other")
        try FileManager.default.copyItem(at: context.root, to: other)
        await context.store.select(other)
        #expect(context.store.vaultURL?.standardizedFileURL.path == other.standardizedFileURL.path)

        #expect(!bridge.holdsJournalDraft(for: day, store: context.store), "vault A's journal draft is gone")
        #expect(!bridge.holdsQuickEntryDraft(for: nil, store: context.store), "vault A's quick entry draft is gone")
        let journalB = bridge.journalDraft(for: day, store: context.store) {
            JournalEditorModel(store: context.store, day: day)
        }
        #expect(journalB !== journal)
        #expect(!journalB.isLoaded && journalB.text.isEmpty, "a fresh model reads vault B")
        let quickB = bridge.quickEntryDraft(for: nil, store: context.store) { QuickEntryModel(store: context.store) }
        #expect(quickB !== quick)
        #expect(quickB.text.isEmpty, "vault A's text is not typed into vault B")
        #expect(
            bridge.journalDraft(for: day, store: context.store) { JournalEditorModel(store: context.store, day: day) }
                === journalB, "the same vault keeps its drafts")
    }

    /// Today's page and a pushed page of the same date present their own editor.
    @Test func journalEditorRouteTellsTodayFromAPushedPage() {
        let day = CalendarDate("2026-10-01")!
        #expect(JournalEditorRoute(day: day, isToday: true) != JournalEditorRoute(day: day, isToday: false))
        #expect(JournalEditorRoute(day: day, isToday: true) == JournalEditorRoute(day: day, isToday: true))
    }
}
