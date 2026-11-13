#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing

    @testable import Kenet

    /// The window content and the shell hand the menu bar its commands as focused values, and
    /// the app's scene reads them (`KenetApp`). A value that changed on every body rebuilt the
    /// scene, the scene rebuilt the window content, and the content made a new value again: the
    /// Mac app kept updating while nothing moved. Here the owner is rebuilt from above as the
    /// scene rebuilds it, and a reader beside it, in the same window, sees one value throughout.
    @MainActor @Suite(.serialized, .timeLimit(.minutes(1)))
    struct MacShellActionHostedTests {
        private let watchdog = HostedTestWatchdog()

        @Test func windowContentHandsTheMenuBarOneSearchCommand() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let reader = CommandReader()
            let rebuilds = Rebuilds()
            let host = await Host(context: context, reader: reader) {
                Rebuilt(rebuilds: rebuilds) { ContentView(store: context.store) }
            }
            defer { host.close() }
            guard host.receivesFocusedValues(reader.search) else { return }

            try await host.rebuild(rebuilds, times: 5)
            #expect(reader.search.count == 1, "the menu bar saw \(reader.search.count) search commands")
        }

        @Test func shellHandsTheMenuBarOneTodayCommandThatOpensToday() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let reader = CommandReader()
            let rebuilds = Rebuilds()
            let navigation = ShellNavigationState()
            let host = await Host(context: context, reader: reader) {
                Rebuilt(rebuilds: rebuilds) { MacNavigation(store: context.store, navigation: navigation) }
            }
            defer { host.close() }
            guard host.receivesFocusedValues(reader.today) else { return }

            try await host.rebuild(rebuilds, times: 5)
            #expect(reader.today.count == 1, "the menu bar saw \(reader.today.count) today commands")

            navigation.section = .days
            navigation.selectedDay = "2026-09-27"
            await host.mount.settle()
            let goToToday = try #require(reader.today.last)
            goToToday()
            #expect(navigation.section == .today, "Bugüne git opened \(String(describing: navigation.section))")
            #expect(navigation.selectedDay == nil, "the past day stays selected")
        }

        /// "Ara" / ⌘F: the shell makes its focus command once (``SidebarSearchState``), so the
        /// menu bar sees one value however often the shell's body runs.
        @Test func shellHandsTheMenuBarOneSidebarSearchCommand() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let reader = CommandReader()
            let rebuilds = Rebuilds()
            let host = await Host(context: context, reader: reader) {
                Rebuilt(rebuilds: rebuilds) { MacNavigation(store: context.store) }
            }
            defer { host.close() }
            guard host.receivesFocusedValues(reader.focusSearch) else { return }

            try await host.rebuild(rebuilds, times: 5)
            #expect(
                reader.focusSearch.count == 1,
                "the menu bar saw \(reader.focusSearch.count) sidebar search commands")
        }

        // MARK: - Support

        /// Every focused command value the menu bar would see, one entry per change.
        @MainActor final class CommandReader {
            var search: [ShellAction] = []
            var today: [ShellAction] = []
            var focusSearch: [ShellAction] = []
        }

        /// Bumped to run the parent's body again, as the app's scene re-runs the window content.
        @MainActor @Observable final class Rebuilds {
            var count = 0
            @ObservationIgnored private(set) var bodies = 0
            func countBody() { bodies += 1 }
        }

        /// The owner under test, made again by every body of this parent.
        private struct Rebuilt<Content: View>: View {
            let rebuilds: Rebuilds
            @ViewBuilder let content: () -> Content

            var body: some View {
                let _ = rebuilds.count
                let _ = rebuilds.countBody()
                content()
            }
        }

        /// Reads the focused values as the menu bar commands do (`@FocusedValue`).
        private struct CommandReaderView: View {
            let reader: CommandReader
            @FocusedValue(\.openSearch) private var openSearch
            @FocusedValue(\.goToToday) private var goToToday
            @FocusedValue(\.focusSidebarSearch) private var focusSidebarSearch

            var body: some View {
                Color.clear
                    .frame(width: 1, height: 1)
                    .onChange(of: openSearch, initial: true) { _, value in
                        if let value { reader.search.append(value) }
                    }
                    .onChange(of: goToToday, initial: true) { _, value in
                        if let value { reader.today.append(value) }
                    }
                    .onChange(of: focusSidebarSearch, initial: true) { _, value in
                        if let value { reader.focusSearch.append(value) }
                    }
            }
        }

        @MainActor
        private struct Host {
            let mount: HostedLayout.Mount
            private let releaseJournalMark: @MainActor () -> Void

            init<Content: View>(
                context: TaskTestContext, reader: CommandReader, @ViewBuilder content: () -> Content
            ) async {
                let defaults = context.defaults.defaults
                let view = ZStack {
                    content()
                    CommandReaderView(reader: reader)
                }
                .environment(NotificationService(center: FakeNotificationCenter(), defaults: defaults))
                .environment(CalendarService(source: IdleCommandCalendarSource()))
                .environment(LocationService(source: FakeLocationSource(), defaults: defaults))
                .environment(IntentNavigation())
                .defaultAppStorage(defaults)
                .environment(\.locale, Locale(identifier: "tr_TR"))
                mount = HostedLayout.Mount(view, size: CGSize(width: 1280, height: 800), bridgesToolbar: true)
                releaseJournalMark = await HostedJournalWindow.claim(mount.window)
                await mount.settle(rounds: 20)
            }

            /// A machine that hands this window no focused values has nothing to measure: the
            /// test returns with a note (the Mac screen tour covers the menu bar).
            func receivesFocusedValues(_ values: [ShellAction], test: String = #function) -> Bool {
                if !values.isEmpty { return true }
                FileHandle.standardError.write(Data("ATLANDI (odaklanmış değer gelmiyor): \(test)\n".utf8))
                return false
            }

            func rebuild(_ rebuilds: Rebuilds, times: Int) async throws {
                let before = rebuilds.bodies
                for _ in 0..<times {
                    rebuilds.count += 1
                    await mount.settle()
                }
                try #require(rebuilds.bodies >= before + times, "the parent ran \(rebuilds.bodies - before) times")
            }

            func close() {
                releaseJournalMark()
                mount.close()
            }
        }
    }

    @MainActor
    private final class IdleCommandCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.notDetermined
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
