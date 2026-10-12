#if os(macOS)
    import AppKit
    import Foundation
    import SwiftUI
    import Testing
    import VaultFormat
    import VaultIndex

    @testable import Journal

    /// The entity page's "Açık işler" section, read from the accessibility tree of the mounted
    /// page: the open tasks linking to the entity, in the list's order, as the old filter of the
    /// read model's task rows gave them. Done, cancelled and unlinked tasks stay out.
    @MainActor @Suite(.timeLimit(.minutes(1)))
    struct EntityOpenTasksPageTests {
        private let watchdog = HostedTestWatchdog()

        @Test func pageListsTheOpenTasksLinkingToTheEntity() async throws {
            let context = try EntityPageTestContext()
            defer { context.clean() }
            try Data(
                """
                - [ ] rvwalias [[Deniz Arıkan|Deniz abi]] 📅 2026-09-01
                - [ ] rvwmulti [[Deniz Arıkan]] ve [[Ece Yalın]] 📅 2026-12-01
                - [ ] rvwundated [[Deniz Arıkan]] ⏫
                - [x] rvwdone [[Deniz Arıkan]] ✅ 2026-09-02
                - [-] rvwcancel [[Deniz Arıkan]]
                - [ ] rvwother [[Ece Yalın]]

                """.utf8
            ).write(to: context.root.appendingPathComponent("notes/Review.md"))
            await context.start()
            let rebuilt = try VaultIndex()
            try rebuilt.rebuild(vaultRoot: context.root)
            let expected = TaskRow.legacy(snapshot: try rebuilt.snapshot())
                .filter { !$0.isClosed && $0.linkedFiles.contains(context.path) }.sorted(by: TasksModel.order)
                .map(\.text.plainText)
            #expect(expected.count == 4)

            let entity = try #require(context.store.content.entities.first { $0.id == context.path })
            let defaults = context.defaults.defaults
            let page = NavigationStack { EntityView(store: context.store, entity: entity) }
                .environment(NotificationService(center: FakeNotificationCenter(), defaults: defaults))
                .environment(CalendarService(source: DeniedCalendarSource()))
                .environment(LocationService(source: FakeLocationSource(), defaults: defaults))
                .environment(IntentNavigation())
            let mount = HostedLayout.Mount(page, size: CGSize(width: 720, height: 6000))
            defer { mount.close() }
            func texts() -> [String] { HostedAccessibilityTree.texts(under: mount) }
            func position(_ text: String) -> Int? { texts().firstIndex { $0.contains(text) } }
            guard
                await HostedAccessibilityTree.isAvailable(
                    mount, until: { expected.allSatisfy { position($0) != nil } })
            else { return }

            let positions = expected.compactMap(position)
            #expect(positions.count == expected.count, "every open linked task is listed")
            #expect(positions == positions.sorted(), "in the list's order: \(texts())")
            for absent in ["rvwdone", "rvwcancel", "rvwother"] {
                #expect(position(absent) == nil, "\(absent) is not an open task of the entity")
            }
        }
    }

    @MainActor private final class DeniedCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.denied
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
