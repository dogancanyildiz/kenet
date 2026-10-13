import SwiftUI
import VaultFormat

/// What the shell has selected and what the user is typing: the section and the row each list
/// column shows in the detail, the phone tabs' stacks, the open sheets and the drafts. One
/// object above the shell, so the iPhone Duo swapping the tab shell for the split shell (or
/// back) keeps the place and the text; on the Mac and on every other iPhone there is one shell
/// and the bridge is simply its state.
@MainActor @Observable
final class ShellNavigationState {
    var section: DesktopSection? = .today
    /// The detail column's stack.
    var detailPath = NavigationPath()
    var selectedDay: String?
    var selectedTask: String?
    var selectedProject: String?
    var selectedGoal: String?
    var selectedEntity: String?
    var selectedSummary: EntitySummary?
    /// Rebuilds the entity page when the list picks a row (also the same row again).
    var entityRouteID = UUID()
    var selectedEntityKind = "person"
    var entityOrder = EntityOrdering.name
    var entitySearch = ""
    /// A notification asked for the unseen people: the list opens that section once per request.
    var unseenReveal: UUID?

    // MARK: Tab shell

    /// The phone tab, read from and written to the section through the one table below
    /// (``DesktopSection/phoneTab``): the shell built next opens where the previous one was. A
    /// tab that already holds the section keeps it (Konumlar stays Konumlar behind Kişiler ve
    /// Konumlar).
    var selectedTab: PhoneTab {
        get { section?.phoneTab ?? .today }
        set { if newValue != section?.phoneTab { section = newValue.desktopSection } }
    }
    /// The tab stacks that take pushes from outside their root (Günlük and Hedefler keep their own).
    var todayPath = NavigationPath()
    var tasksPath = NavigationPath()
    var entitiesPath = NavigationPath()
    /// The Settings sheet, behind the Today manşet's gear in both shells.
    var showingSettings = false

    // MARK: Routes handled

    /// A Siri or notification route is handled by one shell: the shell built after it (the Duo
    /// opened or closed) sees the same request and leaves the selection alone. A new window or
    /// a fresh launch starts with an empty bridge, so its first shell still handles a pending
    /// request.
    private(set) var handledTodayRequest: UUID?
    private(set) var handledNavigationRequest: UUID?

    /// Whether the shell handles this `IntentNavigation.todayRequest`: once per id.
    func claimTodayRequest(_ id: UUID?) -> Bool {
        guard let id, id != handledTodayRequest else { return false }
        handledTodayRequest = id
        return true
    }

    /// Whether the shell handles this `NotificationService.navigationRequest`: once per id.
    func claimNavigationRequest(_ id: UUID?) -> Bool {
        guard let id, id != handledNavigationRequest else { return false }
        handledNavigationRequest = id
        return true
    }

    // MARK: Drafts

    // Memory for the shell's lifetime only; nothing here reaches the disk. The registries are
    // not observed: a page asks for its draft while its body is evaluated. They belong to one
    // vault: another vault selected (``prune(for:)``) drops them, so a draft typed for vault A
    // never shows on vault B's day page.
    @ObservationIgnored private var quickEntryDrafts: [CalendarDate?: QuickEntryModel] = [:]
    @ObservationIgnored private var journalDrafts: [CalendarDate: JournalEditorModel] = [:]
    @ObservationIgnored private var draftsVault: URL?

    /// The quick entry model of a day page (`nil` is Today), made once per day and vault and
    /// kept while the shell swaps. `make` builds the first one.
    func quickEntryDraft(for day: CalendarDate?, store: IndexStore, make: () -> QuickEntryModel)
        -> QuickEntryModel
    {
        prune(for: store)
        if let model = quickEntryDrafts[day] { return model }
        let model = make()
        quickEntryDrafts[day] = model
        return model
    }

    /// Lets go of a day page's quick entry model, if it is still the one kept.
    func releaseQuickEntryDraft(_ model: QuickEntryModel) {
        guard quickEntryDrafts[model.day] === model else { return }
        quickEntryDrafts[model.day] = nil
    }

    func holdsQuickEntryDraft(for day: CalendarDate?, store: IndexStore) -> Bool {
        prune(for: store)
        return quickEntryDrafts[day] != nil
    }

    /// The journal editor that is open: the day page that matches and is on screen presents it,
    /// and presents it again when a new shell rebuilds that page.
    var journalEditor: JournalEditorRoute?

    /// The journal editor model of a day, made once per day and vault and kept while the shell
    /// swaps. `make` builds the first one (the editor's own, once it is on screen).
    func journalDraft(for day: CalendarDate, store: IndexStore, make: () -> JournalEditorModel)
        -> JournalEditorModel
    {
        prune(for: store)
        if let model = journalDrafts[day] { return model }
        let model = make()
        journalDrafts[day] = model
        return model
    }

    /// Lets go of a day's journal editor model, if it is still the one kept.
    func releaseJournalDraft(_ model: JournalEditorModel) {
        guard journalDrafts[model.day] === model else { return }
        journalDrafts[model.day] = nil
    }

    /// The editor of `route` closed (saved, discarded, dismissed): the route and the day's model
    /// go together. A shell swap takes the sheet down without closing the route, and the model
    /// stays for the sheet the next shell opens.
    func closeJournalEditor(_ route: JournalEditorRoute) {
        guard journalEditor == route else { return }
        journalEditor = nil
        journalDrafts[route.day] = nil
    }

    func holdsJournalDraft(for day: CalendarDate, store: IndexStore) -> Bool {
        prune(for: store)
        return journalDrafts[day] != nil
    }

    /// Drops both registries when the store has moved to another vault. The vault opening
    /// (`nil` before, a URL now) is the same session: the drafts typed while it opened stay.
    private func prune(for store: IndexStore) {
        guard let vault = store.vaultURL else { return }
        if let previous = draftsVault, previous != vault {
            quickEntryDrafts = [:]
            journalDrafts = [:]
        }
        draftsVault = vault
    }
}

/// The day page whose journal editor is open. Today's page and a pushed page of the same date
/// are different pages.
struct JournalEditorRoute: Hashable, Sendable {
    let day: CalendarDate
    let isToday: Bool
}

/// The phone tabs, in tab bar order.
enum PhoneTab: Hashable, CaseIterable { case today, days, tasks, entities, goals }

extension DesktopSection {
    /// The phone tab that holds this section. The one table between the two shells: a section
    /// without a tab of its own opens from inside one (Özetler from Günlük, Konumlar, Graph and
    /// Harita from Kişiler ve Konumlar).
    var phoneTab: PhoneTab {
        switch self {
        case .today: .today
        case .days, .summaries: .days
        case .tasks: .tasks
        case .people, .places, .graph, .map: .entities
        case .goals: .goals
        }
    }
}

extension PhoneTab {
    /// The section a tab opens in the split shell: the first one, in sidebar order, it holds.
    var desktopSection: DesktopSection {
        DesktopSection.allCases.first { $0.phoneTab == self } ?? .today
    }
}
