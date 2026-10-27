#if os(macOS)
    import AppKit
    import Foundation
    import SwiftUI
    import Testing

    @testable import Journal

    /// The entity page's Bağlar section after a rename, read from the accessibility tree of the
    /// mounted page: the section follows the file to its new path, so a relation written from the
    /// new path shows up. A section still bound to the old path would load nothing after the rename.
    @MainActor @Suite(.timeLimit(.minutes(1)))
    struct EntityRelationsRenameHostedTests {
        private let watchdog = HostedTestWatchdog()

        @Test func relationsSectionFollowsTheRenamedFile() async throws {
            let context = try await EntityRelationsModelTests.context()
            defer { context.clean() }
            let path = EntityRelationsModelTests.person
            let entity = try #require(context.store.content.entities.first { $0.id == path })
            let detail = EntityDetailModel(store: context.store, path: path)
            let defaults = context.defaults.defaults
            let page = NavigationStack { EntityView(store: context.store, entity: entity, model: detail) }
                .environment(NotificationService(center: FakeNotificationCenter(), defaults: defaults))
                .environment(CalendarService(source: DeniedCalendarSource()))
                .environment(LocationService(source: FakeLocationSource(), defaults: defaults))
                .environment(IntentNavigation())
            let mount = HostedLayout.Mount(page, size: CGSize(width: 720, height: 4000))
            defer { mount.close() }
            func shows(_ other: String) -> Bool { HostedControls.node("row.relation." + other, in: mount) != nil }
            guard
                await HostedControls.isAvailable(
                    mount, until: { shows("people/Selin Korkmaz.md") && shows("books/Örnek Kitap.md") })
            else { return }
            #expect(!shows("places/Liman Ofis.md"))

            await waitUntil { detail.canEdit }
            let result = try await detail.rename(to: "Deniz Yeni", qualifier: nil)
            #expect(result.path == "people/Deniz Yeni.md")
            #expect(detail.path == result.path)
            try await context.store.addRelation(from: result.path, to: "/places/Liman Ofis", label: "iş yeri")
            for _ in 0..<60 where !shows("places/Liman Ofis.md") { await mount.settle(rounds: 1) }
            #expect(shows("places/Liman Ofis.md"), "the relation written from the new path is listed")
            #expect(shows("people/Selin Korkmaz.md"), "the relations kept through the rename stay listed")
        }
    }

    @MainActor private final class DeniedCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.denied
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
