#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing

    @testable import Journal

    /// The real shell (`MacNavigation`) with the sample vault, mounted offscreen: what the three
    /// layouts really install (columns, window minimum, toolbar, title) and what a sidebar row
    /// really does. The window is never ordered on screen.
    @MainActor @Suite(.serialized, .timeLimit(.minutes(1)))
    struct MacShellWiringTests {
        private let watchdog = HostedTestWatchdog()
        @Test func columnsLayoutUsesTheColumnWidthsAndHidesTheToolbarTitle() async throws {
            let shell = try await Shell()
            defer { shell.close() }
            #expect(shell.window.title == String(localized: "Bugün"), "the window is named after the selected row")
            #expect(shell.window.titleVisibility == .hidden, "the toolbar repeats no title")
            let widths = try MacSplitMeasure.columns(in: shell.mount)
            try await MacSplitMeasure.expectSidebar(widths[0], isIdeal: 200, window: 1280)
            #expect(abs(widths[1] - 320) <= 2, "list \(widths[1]) pt")
            #expect(widths[2] >= InkSpacing.macPageWidth, "detail \(widths[2]) pt")
            #expect(shell.searchItems == 1, "toolbar: \(shell.toolbarLabels)")
        }

        @Test func windowDoesNotShrinkBelowItsMinimum() async throws {
            let shell = try await Shell()
            defer { shell.close() }
            let fitted = NSHostingController(rootView: shell.view).sizeThatFits(in: CGSize(width: 500, height: 300))
            #expect(fitted.width == 1000, "width \(fitted.width)")
            #expect(fitted.height == 560, "height \(fitted.height)")
        }

        /// Down the sidebar with the arrow keys: every layout keeps one toolbar search, a board
        /// row really opens its board, and focus stays in the sidebar across the layout swaps
        /// (the test never puts it back itself).
        @Test func sidebarRowsOpenTheirLayoutsWithOneSearchEach() async throws {
            let shell = try await Shell()
            defer { shell.close() }
            let table = try #require(shell.sidebarTable)
            guard HostedFocus.isAvailable(for: table, in: shell.window) else { return }

            var seen: [String: (panes: Int, search: Int)] = [:]
            var titles: [String] = []
            for _ in 0..<17 {
                try await shell.pressDown()
                titles.append(shell.window.title)
                seen[shell.window.title] = (shell.paneCounts.max() ?? 0, shell.searchItems)
            }
            #expect(
                Array(titles.prefix(4)) == [
                    String(localized: "Günlük"), String(localized: "Görevler"), "Kanban",
                    String(localized: "Zaman çizelgesi"),
                ],
                "walked: \(titles)")
            #expect(titles.contains(String(localized: "Özetler")) && titles.contains("Graph"), "walked: \(titles)")
            #expect(seen[String(localized: "Görevler")]?.panes == 3)
            #expect(seen["Kanban"]?.panes == 2, "the board takes the full width")
            #expect(seen[String(localized: "Zaman çizelgesi")]?.panes == 2)
            #expect(seen[String(localized: "Özetler")]?.panes == 2)
            for (title, state) in seen {
                #expect(state.search == 1, "\(title): \(state.search) toolbar search items")
            }
            #expect(shell.window.titleVisibility == .hidden)
        }

        /// A project removed from the vault while its page is open.
        @Test func deletedProjectFallsBackToTasks() async throws {
            let shell = try await Shell()
            defer { shell.close() }
            let table = try #require(shell.sidebarTable)
            guard HostedFocus.isAvailable(for: table, in: shell.window) else { return }
            for _ in 0..<5 { try await shell.pressDown() }
            #expect(shell.window.title == "altyapi", "walked to the first project: \(shell.window.title)")

            let file = shell.context.root.appendingPathComponent("journal/2026-09-15.md")
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(text.contains("#project/altyapi"))
            try text.replacingOccurrences(of: " #project/altyapi", with: "")
                .write(to: file, atomically: true, encoding: .utf8)
            await shell.context.store.refresh()
            await shell.mount.settle(rounds: 16)
            #expect(!shell.context.store.content.projects.contains("altyapi"))
            #expect(shell.window.title == String(localized: "Görevler"), "window: \(shell.window.title)")
        }

        @MainActor
        struct Shell {
            let context: TaskTestContext
            let view: AnyView
            let mount: HostedLayout.Mount

            init() async throws {
                context = try TaskTestContext(sample: true)
                await context.start()
                let defaults = context.defaults.defaults
                view = AnyView(
                    // The key presses below are sent straight to the responder, so the app's own
                    // "was it a key press" question (the current event) is answered here.
                    MacNavigation(store: context.store, selectionCameFromKeyboard: { true })
                        .environment(NotificationService(center: FakeNotificationCenter(), defaults: defaults))
                        .environment(CalendarService(source: IdleShellCalendarSource()))
                        .environment(LocationService(source: FakeLocationSource(), defaults: defaults))
                        .environment(IntentNavigation())
                        .environment(\.openSearch, {})
                        .environment(\.locale, Locale(identifier: "tr_TR")))
                mount = HostedLayout.Mount(view, size: CGSize(width: 1280, height: 800), bridgesToolbar: true)
                await mount.settle(rounds: 20)
            }

            var window: NSWindow { mount.window }
            var paneCounts: [Int] { mount.views(NSSplitView.self).map(\.arrangedSubviews.count) }
            var toolbarLabels: [String] { window.toolbar?.items.map(\.label) ?? [] }
            var searchItems: Int { toolbarLabels.filter { $0 == "Ara" }.count }
            /// The sidebar's list: the table that is as narrow as the sidebar column.
            var sidebarTable: NSTableView? {
                mount.views(NSTableView.self).first {
                    $0.convert($0.bounds, to: nil).width <= InkSpacing.macSidebarMaxWidth + 1
                }
            }

            func pressDown() async throws {
                let table = try #require(sidebarTable)
                let responder = try #require(window.firstResponder as? NSView, "nothing holds the focus")
                #expect(
                    responder === table || responder.isDescendant(of: table),
                    "the arrow key would miss the sidebar (\(window.title))")
                let characters = String(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!)
                let event = try #require(
                    NSEvent.keyEvent(
                        with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function], timestamp: 0,
                        windowNumber: window.windowNumber, context: nil, characters: characters,
                        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 125))
                responder.keyDown(with: event)
                await mount.settle(rounds: 12)
            }

            func close() {
                mount.close()
                context.clean()
            }
        }
    }

    @MainActor
    private final class IdleShellCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.notDetermined
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
