#if os(iOS)
    import SwiftUI
    import Testing
    import UIKit
    import VaultFormat

    @testable import Journal

    /// The iPhone Duo opened and closed: `AdaptiveNavigation` with the sample vault in one window
    /// whose size classes change between D0-4's canvases (`ShellCanvas`), so the tab shell is
    /// torn down for the split shell and built again. The bridge (`ShellNavigationState`) keeps
    /// the selection, the text being typed and the routes already handled across the swap.
    @MainActor @Suite(.serialized, .timeLimit(.minutes(3)))
    struct DuoShellBridgeHostedTests {
        /// (a) The tab chosen on the cover screen is the section the inner screen opens, and the
        /// tab the cover screen comes back to.
        @Test func selectedTabSurvivesTheFold() async throws {
            try await DuoShell.hosted { shell in
                try shell.expectTabs(selected: 0)
                shell.navigation.selectedTab = .tasks
                await shell.settle()
                try shell.expectTabs(selected: 2)

                await shell.fold(to: .duoInner())
                #expect(shell.tabBar == nil, "the inner screen has no tab bar")
                let split = try #require(shell.split, "the inner screen draws the split shell")
                #expect(!split.isCollapsed)
                #expect(shell.navigation.section == .tasks, "Görevler stays selected")
                #expect(shell.onScreen(.supplementary) != nil, "the Görevler list is beside the detail")

                await shell.fold(to: .duoOuter)
                try shell.expectTabs(selected: 2)
            }
        }

        /// (b) Text typed into Today's quick entry on the cover screen is in the inner screen's
        /// bar, and back on the cover screen's.
        @Test func quickEntryDraftSurvivesTheFold() async throws {
            try await DuoShell.hosted { shell in
                let draft = shell.navigation.quickEntryDraft(for: nil, store: shell.store) {
                    Issue.record("Today's bar did not take its model from the bridge")
                    return QuickEntryModel(store: shell.store)
                }
                draft.text = "Duo taslağı"
                await shell.settle()
                #expect(
                    shell.textFieldTexts.contains("Duo taslağı"), "the field shows the draft: \(shell.textFieldTexts)")

                await shell.fold(to: .duoInner())
                #expect(shell.split != nil)
                #expect(
                    shell.textFieldTexts.contains("Duo taslağı"), "inner screen lost the draft: \(shell.textFieldTexts)"
                )

                await shell.fold(to: .duoOuter)
                #expect(shell.tabBar != nil)
                #expect(
                    shell.textFieldTexts.contains("Duo taslağı"), "cover screen lost the draft: \(shell.textFieldTexts)"
                )
                #expect(draft.text == "Duo taslağı")
            }
        }

        /// (c) The journal editor open on Today with unsaved text: the inner screen's Today page
        /// opens it again with the same text, and the cover screen's after that. Nothing reaches
        /// the disk on the way.
        @Test func journalDraftSurvivesTheFold() async throws {
            try await DuoShell.hosted { shell in
                let today = LocalDay.today()
                shell.navigation.journalEditor = JournalEditorRoute(day: today, isToday: true)
                await shell.settle(until: { shell.journalText != nil })
                let draft = shell.editorDraft(for: today)
                await shell.settle(until: { draft.isLoaded })
                #expect(draft.isLoaded, "the editor loaded the day")
                draft.text = "Köprü taslağı"
                await shell.settle()
                #expect(shell.journalText == "Köprü taslağı", "the editor shows the draft")

                await shell.fold(to: .duoInner())
                await shell.settle(until: { shell.journalText == "Köprü taslağı" })
                #expect(shell.journalText == "Köprü taslağı", "the inner screen reopened the editor with the draft")
                #expect(shell.editorDraft(for: today) === draft, "one model")

                await shell.fold(to: .duoOuter)
                await shell.settle(until: { shell.journalText == "Köprü taslağı" })
                #expect(shell.journalText == "Köprü taslağı", "the cover screen reopened the editor with the draft")
                #expect(draft.isDirty, "the fold wrote the draft to the disk")
                let file = shell.store.vaultURL?.appendingPathComponent("journal/\(today).md")
                let written = file.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
                #expect(!written.contains("Köprü taslağı"), "the draft stays in memory")

                // The sheet going away is the page closing its route: the model goes with it.
                shell.presenter?.presentedViewController?.dismiss(animated: false)
                await shell.settle(until: { shell.navigation.journalEditor == nil })
                #expect(shell.navigation.journalEditor == nil, "the dismissed sheet closed the route")
                #expect(
                    !shell.navigation.holdsJournalDraft(for: today, store: shell.store),
                    "the route closing let the model go")
            }
        }

        /// (c') The editor open and still clean when the Duo opens: what is typed on the inner
        /// screen is in the cover screen's editor after the next fold. The old editor going away
        /// must not take the model the new one already holds out of the bridge.
        @Test func journalTypedAfterTheFoldSurvivesTheNextFold() async throws {
            try await DuoShell.hosted { shell in
                let today = LocalDay.today()
                shell.navigation.journalEditor = JournalEditorRoute(day: today, isToday: true)
                await shell.settle(until: { shell.journalText != nil })
                let opened = shell.editorDraft(for: today)
                await shell.settle(until: { opened.isLoaded })
                #expect(!opened.isDirty, "nothing typed yet")

                await shell.fold(to: .duoInner())
                await shell.settle(until: { shell.journalText != nil })
                let draft = shell.editorDraft(for: today)
                #expect(draft === opened, "the inner screen's editor took the model that was open")
                draft.text = "İç ekranda yazıldı"
                await shell.settle(until: { shell.journalText == "İç ekranda yazıldı" })
                #expect(shell.journalText == "İç ekranda yazıldı", "the inner screen's editor shows the model")
                #expect(shell.navigation.holdsJournalDraft(for: today, store: shell.store), "the bridge lost the model")

                await shell.fold(to: .duoOuter)
                await shell.settle(until: { shell.journalText == "İç ekranda yazıldı" })
                #expect(shell.journalText == "İç ekranda yazıldı", "the cover screen's editor lost the text")
                #expect(shell.editorDraft(for: today) === draft)
            }
        }

        /// The same past day live in two tabs: the page on screen presents the editor, and
        /// opening it from the other tab, once it is on screen, presents it there.
        @Test func onlyThePageOnScreenPresentsTheEditor() async throws {
            let day = CalendarDate("2026-09-20")!
            let tabs = TabBox()
            try await DuoShell.hosted(
                root: { navigation, store in AnyView(TwoTabsOfOneDay(store: store, day: day, tabs: tabs)) },
                { shell in
                    let route = JournalEditorRoute(day: day, isToday: false)
                    let bar = try #require(shell.tabBar)
                    shell.navigation.journalEditor = route
                    await shell.settle(until: { shell.journalText != nil })
                    #expect(shell.journalText != nil, "the first tab's page opened the editor")

                    shell.navigation.closeJournalEditor(route)
                    await shell.settle(until: { shell.journalText == nil })
                    #expect(shell.journalText == nil, "the editor closed")

                    tabs.selected = 1
                    await shell.settle()
                    #expect(bar.selectedIndex == 1)
                    shell.navigation.journalEditor = route
                    await shell.settle(until: { shell.journalText != nil })
                    #expect(shell.journalText != nil, "the second tab's page did not open the editor")

                    shell.navigation.closeJournalEditor(route)
                    await shell.settle(until: { shell.journalText == nil })
                    tabs.selected = 0
                    await shell.settle()
                    shell.navigation.journalEditor = route
                    await shell.settle(until: { shell.journalText != nil })
                    #expect(shell.journalText != nil, "back on the first tab, its page did not open the editor")
                })
        }

        /// (d) A Siri request routed by the cover screen is not routed again by the inner screen
        /// (which would throw the user back to Today), nor a notification's by the cover screen.
        @Test func handledRouteIsNotRepeatedByTheNextShell() async throws {
            try await DuoShell.hosted { shell in
                shell.navigation.selectedTab = .goals
                shell.intent.openToday()
                await shell.settle()
                try shell.expectTabs(selected: 0)
                shell.navigation.selectedTab = .goals
                await shell.settle()

                await shell.fold(to: .duoInner())
                #expect(shell.split != nil)
                #expect(shell.navigation.section == .goals, "the inner screen routed Siri's request again")

                shell.notifications.open(.tasks)
                await shell.settle()
                #expect(shell.navigation.section == .tasks, "a new notification request is routed")
                shell.navigation.section = .goals
                await shell.settle()

                await shell.fold(to: .duoOuter)
                try shell.expectTabs(selected: 4)
                #expect(shell.navigation.section == .goals, "the cover screen routed the notification again")
            }
        }

        /// A request from before the shell was built (the app launched from a notification) is
        /// still routed by the first shell.
        @Test func theFirstShellRoutesAPendingRequest() async throws {
            try await DuoShell.hosted(
                before: { $0.notifications.open(.tasks) },
                { shell in
                    try shell.expectTabs(selected: 2)
                    #expect(shell.navigation.section == .tasks)
                })
        }

        @MainActor
        struct DuoShell {
            let host: UIHostingController<AnyView>
            let window: UIWindow
            let store: IndexStore
            let navigation: ShellNavigationState
            let intent: IntentNavigation
            let notifications: NotificationService

            var split: UISplitViewController? { controllers(of: UISplitViewController.self).first }
            var tabBar: UITabBarController? { controllers(of: UITabBarController.self).first }

            func expectTabs(selected index: Int) throws {
                let tabs = try #require(tabBar, "no tab bar under the shell")
                #expect(tabs.viewControllers?.count == 5, "five tabs")
                #expect(tabs.selectedIndex == index, "tab \(tabs.selectedIndex) is selected")
            }

            /// The column's frame in the window, or nil when it is not on screen.
            func onScreen(_ column: UISplitViewController.Column) -> CGRect? {
                guard let view = split?.viewController(for: column)?.viewIfLoaded, let window = view.window,
                    !view.isHidden, view.bounds.width > 0
                else { return nil }
                let frame = view.convert(view.bounds, to: window)
                return frame.intersects(window.bounds) && frame.maxX > 1 ? frame : nil
            }

            /// Every text field under the shell, as its text: the quick entry bars among them.
            var textFieldTexts: [String] {
                views(of: UITextField.self, under: host.view).compactMap(\.text)
            }

            /// The text of the editor in the sheet the shell presents, or nil without one.
            var journalText: String? {
                guard let presented = presenter?.presentedViewController else { return nil }
                return views(of: UITextView.self, under: presented.view).first?.text
            }

            /// The controller that presents the sheet, or nil without one.
            var presenter: UIViewController? {
                controllers(of: UIViewController.self).first { $0.presentedViewController != nil }
            }

            /// The day's editor model, which the editor on screen put into the bridge.
            func editorDraft(for day: CalendarDate) -> JournalEditorModel {
                navigation.journalDraft(for: day, store: store) {
                    Issue.record("no editor registered its model for \(day)")
                    return JournalEditorModel(store: store, day: day)
                }
            }

            /// The Duo folded or opened: the window takes the canvas's size and size classes.
            func fold(to canvas: ShellCanvas) async {
                window.frame = CGRect(origin: .zero, size: canvas.size)
                host.view.frame = window.bounds
                canvas.applySizeClasses(to: host)
                await settle(rounds: 20)
            }

            /// Lets SwiftUI, the split controller and the presentations apply pending updates.
            func settle(rounds: Int = 10) async {
                for _ in 0..<rounds {
                    await Task.yield()
                    // Frame pump: SwiftUI and UIKit draw on a later run-loop turn and report no event to await.
                    try? await Task.sleep(for: .milliseconds(30))
                    host.view.setNeedsLayout()
                    host.view.layoutIfNeeded()
                }
            }

            /// Settles until `condition` holds, for at most about three seconds.
            func settle(until condition: () -> Bool) async {
                for _ in 0..<100 where !condition() {
                    await settle(rounds: 1)
                }
            }

            private func controllers<T: UIViewController>(of type: T.Type) -> [T] {
                var found: [T] = []
                func walk(_ controller: UIViewController) {
                    if let match = controller as? T { found.append(match) }
                    controller.children.forEach(walk)
                    if let presented = controller.presentedViewController { walk(presented) }
                }
                walk(host)
                return found
            }

            private func views<T: UIView>(of type: T.Type, under root: UIView) -> [T] {
                var found: [T] = []
                func walk(_ view: UIView) {
                    if let match = view as? T { found.append(match) }
                    view.subviews.forEach(walk)
                }
                walk(root)
                return found
            }

            /// Hosts `AdaptiveNavigation` (or `root`, with the bridge in its environment) on the
            /// Duo cover screen canvas and runs `body` once the vault is indexed and the tree has
            /// settled. `before` runs against the services before the shell exists.
            static func hosted(
                before: @MainActor (DuoShell) -> Void = { _ in },
                root: (@MainActor (ShellNavigationState, IndexStore) -> AnyView)? = nil,
                _ body: @MainActor (DuoShell) async throws -> Void
            ) async throws {
                let context = try TaskTestContext(sample: true)
                await context.start()
                let defaults = context.defaults.defaults
                let location = LocationService(source: FakeLocationSource(), defaults: defaults)
                let navigation = ShellNavigationState()
                let intent = IntentNavigation()
                let notifications = NotificationService(center: FakeNotificationCenter(), defaults: defaults)
                let shellView =
                    root?(navigation, context.store).environment(navigation)
                    ?? AnyView(AdaptiveNavigation(store: context.store, navigation: navigation)).environment(navigation)
                let view =
                    shellView
                    .environment(notifications)
                    .environment(CalendarService(source: IdleDuoCalendarSource()))
                    .environment(location)
                    .environment(
                        GeofenceService(location: location, center: FakeGeofenceCenter(), defaults: defaults)
                    )
                    .environment(intent)
                    .environment(\.openSearch, {})
                    .transaction { $0.animation = nil }
                var failure: (any Error)?
                await SnapshotHostGate.exclusive {
                    let previousAnimations = UIView.areAnimationsEnabled
                    UIView.setAnimationsEnabled(false)
                    defer { UIView.setAnimationsEnabled(previousAnimations) }
                    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
                    else {
                        Issue.record("The shell needs a UIWindowScene (run under the Journal test host).")
                        return
                    }
                    let canvas = ShellCanvas.duoOuter
                    let host = UIHostingController(rootView: AnyView(view))
                    canvas.applySizeClasses(to: host)
                    host.view.frame = CGRect(origin: .zero, size: canvas.size)
                    let window = UIWindow(windowScene: scene)
                    window.frame = CGRect(origin: .zero, size: canvas.size)
                    let shell = DuoShell(
                        host: host, window: window, store: context.store, navigation: navigation, intent: intent,
                        notifications: notifications)
                    before(shell)
                    window.rootViewController = host
                    window.isHidden = false
                    defer {
                        window.isHidden = true
                        window.rootViewController = nil
                        window.windowScene = nil
                    }
                    var idle = 0
                    for _ in 0..<80 where idle < 6 {
                        await shell.settle(rounds: 1)
                        idle = context.store.isProcessing ? 0 : idle + 1
                    }
                    do { try await body(shell) } catch { failure = error }
                }
                if let failure { throw failure }
            }
        }
    }

    /// Two tabs that both show the same past day's page, as Today → "O gün" and Kişiler → a
    /// person → the day do on the phone.
    private struct TwoTabsOfOneDay: View {
        let store: IndexStore
        let day: CalendarDate
        let tabs: TabBox

        var body: some View {
            @Bindable var tabs = tabs
            TabView(selection: $tabs.selected) {
                Tab("A", systemImage: "a.circle", value: 0) {
                    NavigationStack { DayView(store: store, date: day) }
                }
                Tab("B", systemImage: "b.circle", value: 1) {
                    NavigationStack { DayView(store: store, date: day) }
                }
            }
        }
    }

    @MainActor @Observable
    private final class TabBox {
        var selected = 0
    }

    @MainActor
    private final class IdleDuoCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.notDetermined
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
