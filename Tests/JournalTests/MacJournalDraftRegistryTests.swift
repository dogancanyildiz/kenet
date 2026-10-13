#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// On the Mac the journal editor is a pushed page whose `NavigationLink` builds it with every
    /// draw of the day page. The bridge takes an editor's model only once the editor is on
    /// screen: day pages drawn without opening it leave the bridge empty.
    @MainActor struct MacJournalDraftRegistryTests {
        @Test func drawnDayPagesRegisterNoEditorModel() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let defaults = context.defaults.defaults
            let navigation = ShellNavigationState()
            let days = [CalendarDate("2026-09-18")!, CalendarDate("2026-09-19")!, CalendarDate("2026-09-20")!]
            let location = LocationService(source: FakeLocationSource(), defaults: defaults)
            let view = NavigationStack {
                VStack(spacing: 0) {
                    ForEach(days, id: \.self) { day in
                        DayView(store: context.store, date: day).frame(height: 700)
                    }
                }
            }
            .environment(navigation)
            .environment(NotificationService(center: FakeNotificationCenter(), defaults: defaults))
            .environment(CalendarService(source: IdleRegistryCalendarSource()))
            .environment(location)
            .environment(GeofenceService(location: location, center: FakeGeofenceCenter(), defaults: defaults))
            .environment(IntentNavigation())
            .environment(\.openSearch, {})
            let mount = HostedLayout.Mount(view, size: CGSize(width: 1000, height: 2100))
            await mount.settle(rounds: 20)
            // The pages drew their "Günlük yazısı" rows: the link's label is in the tree.
            #expect(mount.views(NSView.self).count > 3, "the pages were drawn")
            for day in days {
                #expect(
                    !navigation.holdsJournalDraft(for: day, store: context.store),
                    "a model for \(day) without an editor")
            }
            mount.close()
        }
    }

    @MainActor
    private final class IdleRegistryCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.notDetermined
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
