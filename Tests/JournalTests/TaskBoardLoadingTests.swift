#if os(macOS)
    import AppKit
    import Foundation
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// A task screen opening with its first answer still on the way draws no empty state: the
    /// list, the board and the timeline would otherwise say "Görev yok." for a vault full of tasks.
    /// Read from the accessibility tree SwiftUI builds for the mounted screen, with the store's task
    /// queries held at the gate.
    @MainActor @Suite(.timeLimit(.minutes(1)))
    struct TaskBoardLoadingTests {
        private let watchdog = HostedTestWatchdog()

        @Test func listShowsNoEmptyStateBeforeItsFirstAnswer() async throws {
            try await expectNoEmptyStateWhileLoading { TasksView(store: $0, tasks: $1) }
        }

        @Test func boardShowsNoEmptyColumnsBeforeItsFirstAnswer() async throws {
            try await expectNoEmptyStateWhileLoading { KanbanView(tasks: $1) }
        }

        /// The answer itself is not read back here: walking the timeline's linked rows makes
        /// SwiftUI's link rotor bridge throw an out-of-range exception inside the test host.
        @Test func timelineShowsNoEmptyStateBeforeItsFirstAnswer() async throws {
            try await expectNoEmptyStateWhileLoading(readsAnswer: false) { TaskTimelineView(tasks: $1) }
        }

        /// A day with only tasks: until its task rows answer, the page does not draw the day as
        /// empty ("nothing written") even though the day itself has answered.
        @Test func dayPageShowsNoEmptyDayBeforeItsTasks() async throws {
            let context = try TaskTestContext()
            defer { context.clean() }
            try FileManager.default.createDirectory(
                at: context.file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("## Tasks\n- [ ] only task 📅 \(context.today) ^only\n".utf8).write(to: context.file)
            await context.start()
            let store = context.store
            #expect(store.content.tasks.count == 1)
            let gate = TaskQueryGate(store: store)
            gate.hold()
            let mount = HostedLayout.Mount(
                Self.environment(NavigationStack { DayView(store: store, date: context.today) }, context: context),
                size: CGSize(width: 720, height: 1600))
            defer { mount.close() }
            let empty = String(localized: "Bu gün henüz bir şey yazılmadı.")
            func texts() -> [String] { HostedAccessibilityTree.texts(under: mount) }
            guard
                await HostedAccessibilityTree.isAvailable(
                    mount, until: { gate.heldCount > 0 && !texts().isEmpty })
            else { return }
            await mount.settle()
            #expect(!texts().contains(empty), "the day is not drawn empty while its tasks are on their way")
            gate.release()
            for _ in 0..<40 where !texts().contains(where: { $0.contains("only task") }) {
                await mount.settle(rounds: 1)
            }
            #expect(texts().contains { $0.contains("only task") } && !texts().contains(empty))
        }

        private func expectNoEmptyStateWhileLoading(
            readsAnswer: Bool = true, _ screen: (IndexStore, TasksModel) -> some View
        ) async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let store = context.store
            let day = try #require(CalendarDate("2026-09-20"))
            let model = TasksModel(store: store, today: { day })
            // An undated task: listed by the list's Tarihsiz section, the board and the timeline.
            model.section = .undated
            let shown = try #require(
                try await store.computeTaskGroups(today: day).undated.first {
                    $0.start == nil && $0.rawStatus == " " && $0.recurrence == nil
                })
            let gate = TaskQueryGate(store: store)
            gate.hold()
            let mount = HostedLayout.Mount(
                Self.environment(NavigationStack { screen(store, model) }, context: context),
                size: CGSize(width: 1200, height: 1600))
            defer { mount.close() }
            let empty = String(localized: "Görev yok.")
            func texts() -> [String] { HostedAccessibilityTree.texts(under: mount) }
            guard
                await HostedAccessibilityTree.isAvailable(
                    mount, until: { gate.heldCount > 0 && !texts().isEmpty })
            else { return }
            await mount.settle()
            #expect(!texts().contains(empty), "nothing says the vault has no tasks while the answer is on its way")

            gate.release()
            guard readsAnswer else { return }
            let row = shown.text.plainText
            func drawn() -> Bool { texts().contains { $0.contains(row) } }
            for _ in 0..<40 where !drawn() { await mount.settle(rounds: 1) }
            #expect(drawn())
        }

        private static func environment(_ view: some View, context: TaskTestContext) -> some View {
            let defaults = context.defaults.defaults
            return
                view
                .environment(NotificationService(center: FakeNotificationCenter(), defaults: defaults))
                .environment(CalendarService(source: StillCalendarSource()))
                .environment(LocationService(source: FakeLocationSource(), defaults: defaults))
                .environment(IntentNavigation())
        }
    }

    @MainActor private final class StillCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.denied
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
