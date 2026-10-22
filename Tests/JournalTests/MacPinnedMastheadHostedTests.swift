#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// Every page a Mac window column shows, in the real shell (`MacNavigation`) with the sample
    /// vault at the window's smallest size. Each page manşet sits outside the content its column
    /// scrolls (a manşet that is the first scrolled child is part of it), and with every column
    /// scrolled down the manşets are still where they were, below the toolbar.
    @MainActor @Suite(.serialized, .timeLimit(.minutes(3)))
    struct MacPinnedMastheadHostedTests {
        private let watchdog = HostedTestWatchdog(seconds: 170)

        /// The pages of the sidebar's rows, with a row picked in their list column where they
        /// have one (the detail page is then a page of its own: day, task, goal, person).
        enum Page: String, CaseIterable, CustomTestStringConvertible {
            case today, day, tasks, project, goals, people, places, summaries, graph
            /// Pages opened from a link or a search result in the detail column.
            case searchNote, unresolvedLink
            var testDescription: String { rawValue }
        }

        @Test(arguments: Page.allCases)
        func manşetsStayAboveTheScrolledContent(_ page: Page) async throws {
            let shell = try await PinnedShell(page)
            defer { shell.close() }
            guard
                await HostedControls.isAvailable(
                    shell.mount, until: { shell.mastheads().count >= page.mastheadCount })
            else { return }
            let before = shell.mastheads()
            #expect(before.count == page.mastheadCount, "\(page): manşets \(before.map(\.label))")
            let documents = shell.scrolledContentFrames()
            for node in before {
                #expect(shell.isVisible(node), "\(page): \(node.label) at \(node.frame) before scrolling")
                let inside = documents.filter { $0.intersects(node.frame.insetBy(dx: 1, dy: 1)) }
                #expect(inside.isEmpty, "\(page): \(node.label) is part of the content that scrolls")
            }

            // The pinned strip keeps the identifiers of its controls (the page's own identifier
            // stays on the page, not on the strip's children).
            for identifier in page.stripIdentifiers {
                #expect(
                    HostedControls.node(identifier, in: shell.mount) != nil,
                    "\(page): no \(identifier) on the manşet row")
            }

            let moved = shell.scrollEveryColumn()
            await shell.mount.settle(rounds: 8)
            #expect(moved >= page.scrolledColumns, "\(page): only \(moved) columns scrolled")

            let after = shell.mastheads()
            for node in before {
                let now = after.first { $0.label == node.label }
                #expect(now != nil, "\(page): \(node.label) left the column")
                if let now {
                    #expect(shell.isVisible(now), "\(page): \(now.label) at \(now.frame), visible \(shell.visible)")
                    #expect(abs(now.frame.minY - node.frame.minY) < 1, "\(page): \(now.label) moved")
                }
            }
        }

        /// The person page scrolled down: its manşet icon (Düzenle) is still on screen and opens
        /// the editor.
        @Test func pinnedEditIconStillOpensTheEditor() async throws {
            let shell = try await PinnedShell(.people)
            defer { shell.close() }
            let id = "button.entity.edit"
            guard
                await HostedControls.isAvailable(
                    shell.mount, until: { HostedControls.node(id, in: shell.mount) != nil })
            else { return }
            #expect(shell.scrollEveryColumn() >= 1)
            await shell.mount.settle(rounds: 8)
            let edit = try #require(HostedControls.node(id, in: shell.mount), "the edit icon left the page")
            #expect(shell.isVisible(edit), "edit icon at \(edit.frame), visible \(shell.visible)")
            let windows = Set(NSApp.windows.map(ObjectIdentifier.init))
            edit.press()
            var opened: [NSWindow] = []
            for _ in 0..<40 where opened.isEmpty {
                await shell.mount.settle(rounds: 1)
                opened = NSApp.windows.filter { !windows.contains(ObjectIdentifier($0)) }
            }
            // SwiftUI presents the sheet of an offscreen window as a window of its own.
            #expect(
                opened.contains { String(describing: type(of: $0)).contains("Sheet") },
                "the press did not open the editor: \(opened)")
            for window in opened { window.orderOut(nil) }
        }
    }

    extension MacPinnedMastheadHostedTests.Page {
        /// Manşets on screen in this layout: the list column's and the detail page's (one for
        /// the full-width pages).
        var mastheadCount: Int {
            switch self {
            // A project has no task picked: the detail column is the empty prompt.
            case .project, .summaries, .graph, .searchNote, .unresolvedLink: 1
            default: 2
            }
        }

        /// Columns long enough to scroll in the smallest window (the sample vault's pages).
        var scrolledColumns: Int {
            switch self {
            case .project, .summaries, .graph, .searchNote, .unresolvedLink: 0
            // The Günlük column and the day page.
            case .day: 2
            default: 1
            }
        }
    }

    extension MacPinnedMastheadHostedTests.Page {
        /// Controls on the pinned strip that carry an identifier of their own. Today shows its
        /// Ayarlar icon because the shell is given an `openSettings` action.
        var stripIdentifiers: [String] {
            switch self {
            case .today: ["button.settings"]
            case .tasks: ["tasks.filter", "tasks.menu"]
            default: []
            }
        }
    }

    @MainActor
    private struct PinnedShell {
        static let size = CGSize(width: InkSpacing.macWindowMinWidth, height: InkSpacing.macWindowMinHeight)

        let context: TaskTestContext
        let mount: HostedLayout.Mount
        private let releaseJournalMark: @MainActor () -> Void

        init(_ page: MacPinnedMastheadHostedTests.Page) async throws {
            context = try TaskTestContext(sample: true)
            await context.start()
            let navigation = try await Self.navigation(page, store: context.store)
            let defaults = context.defaults.defaults
            let store = context.store
            let root: AnyView
            switch page {
            case .searchNote:
                root = AnyView(NavigationStack { SearchNoteView(store: store, file: "notes/Okuma Listesi.md") })
            case .unresolvedLink:
                root = AnyView(NavigationStack { UnresolvedEntityView(store: store, target: "Yazılmamış Ad") })
            default:
                root = AnyView(MacNavigation(store: store, navigation: navigation))
            }
            let view =
                root
                .environment(\.openSettings, { @MainActor @Sendable in })
                .environment(NotificationService(center: FakeNotificationCenter(), defaults: defaults))
                .environment(CalendarService(source: PinnedShellCalendarSource()))
                .environment(LocationService(source: FakeLocationSource(), defaults: defaults))
                .environment(IntentNavigation())
                .environment(\.openSearch, {})
                .environment(\.locale, Locale(identifier: "tr_TR"))
            mount = HostedLayout.Mount(view, size: Self.size, bridgesToolbar: true)
            releaseJournalMark = await HostedJournalWindow.claim(mount.window)
            for _ in 0..<60 {
                await mount.settle(rounds: 1)
                if !context.store.isProcessing { break }
            }
            await mount.settle(rounds: 12)
        }

        private static func navigation(
            _ page: MacPinnedMastheadHostedTests.Page, store: IndexStore
        ) async throws -> ShellNavigationState {
            let navigation = ShellNavigationState()
            switch page {
            case .today:
                navigation.section = .today
            case .day:
                navigation.section = .days
                navigation.selectedDay = "journal/2026-09-25.md"
            case .tasks:
                navigation.section = .tasks
                let projects = try await store.computeProjects()
                let project = try #require(projects.first, "the sample vault has projects")
                let rows = try await store.computeProjectTasks(project)
                let row: TaskRow = try #require(rows.first)
                navigation.selectedTask = row.id
            case .project:
                navigation.section = .tasks
                let projects = try await store.computeProjects()
                let project: String = try #require(projects.first, "the sample vault has projects")
                navigation.selectedProject = project
            case .goals:
                navigation.section = .goals
                let goals = try await store.computeGoalStatuses(today: CalendarDate("2026-10-03")!)
                let goal = try #require(goals.first)
                navigation.selectedGoal = goal.definition.id
            case .people, .places:
                let kind = page == .people ? "person" : "place"
                navigation.section = page == .people ? .people : .places
                navigation.selectedEntityKind = kind
                let entity = try #require(
                    store.content.entities.filter { $0.kind == kind }.max { $0.incomingLinks < $1.incomingLinks })
                navigation.selectedEntity = entity.id
                navigation.selectedSummary = entity
            case .summaries:
                navigation.section = .summaries
            case .graph:
                navigation.section = .graph
            case .searchNote, .unresolvedLink:
                break
            }
            return navigation
        }

        var window: NSWindow { mount.window }

        /// The part of the window the toolbar does not cover, in screen coordinates.
        var visible: CGRect {
            window.convertToScreen(window.contentLayoutRect)
        }

        /// The page manşets: the headings that are not section titles (``PageHeadline`` and
        /// ``SectionHeader`` are the only headings these pages draw).
        func mastheads() -> [HostedControls.Node] {
            HostedControls.nodes(in: mount).filter {
                $0.role == "AXHeading" && $0.identifier != SectionHeader.titleIdentifier
            }
        }

        /// Where each scroll view's content is (its document view), in screen coordinates.
        func scrolledContentFrames() -> [CGRect] {
            mount.views(NSScrollView.self).compactMap { scroll in
                scroll.documentView.map { window.convertToScreen($0.convert($0.bounds, to: nil)) }
            }
        }

        func isVisible(_ node: HostedControls.Node) -> Bool {
            visible.insetBy(dx: -1, dy: -1).contains(node.frame)
        }

        /// Scrolls every vertical scroll view that has more content than room by up to 400 pt
        /// (the sidebar included); returns how many moved.
        func scrollEveryColumn() -> Int {
            var moved = 0
            for scroll in mount.views(NSScrollView.self) {
                let clip = scroll.contentView
                guard let document = scroll.documentView, clip.bounds.width > 100 else { continue }
                // At rest the clip starts above the content by its top inset (the pinned strip).
                let end = document.frame.height - clip.bounds.height
                guard end - clip.bounds.minY > 40 else { continue }
                let target = min(clip.bounds.minY + 400, end)
                clip.scroll(to: NSPoint(x: clip.bounds.minX, y: target))
                scroll.reflectScrolledClipView(clip)
                moved += 1
            }
            return moved
        }

        func close() {
            releaseJournalMark()
            mount.close()
            context.clean()
        }
    }

    @MainActor
    private final class PinnedShellCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.notDetermined
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
