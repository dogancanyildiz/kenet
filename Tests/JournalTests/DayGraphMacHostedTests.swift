#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// The day page's Graph icon on the Mac sits on the pinned manşet strip, outside the content
    /// the page scrolls, and only on a day that links an entity. Read from the accessibility tree
    /// by identifier: CI runs the process in English while the hosted view is Turkish.
    @MainActor @Suite(.serialized, .timeLimit(.minutes(1)))
    struct DayGraphMacHostedTests {
        private let watchdog = HostedTestWatchdog()
        static let identifier = "button.dayGraph"

        @Test func iconSitsOnThePinnedStripOfALinkedDay() async throws {
            let context = try await Self.graphVault()
            defer { context.clean() }
            let mount = HostedLayout.Mount(Self.page(context, day: "2026-10-01"), size: Self.size)
            defer { mount.window.contentView = nil }
            guard
                await HostedControls.isAvailable(
                    mount, until: { HostedControls.node(Self.identifier, in: mount) != nil })
            else { return }
            let icon = try #require(HostedControls.node(Self.identifier, in: mount))
            let scrolled = mount.views(NSScrollView.self).compactMap { scroll in
                scroll.documentView.map { mount.window.convertToScreen($0.convert($0.bounds, to: nil)) }
            }
            #expect(!scrolled.isEmpty, "the day page has no scroll view")
            #expect(
                scrolled.allSatisfy { !$0.intersects(icon.frame.insetBy(dx: 1, dy: 1)) },
                "the icon is part of the content that scrolls: \(icon.frame)")
            // On the manşet's row: the page heading shares the strip with it.
            let heading = HostedControls.nodes(in: mount).first {
                $0.role == "AXHeading" && $0.identifier != SectionHeader.titleIdentifier
            }
            let masthead = try #require(heading, "no manşet heading")
            #expect(icon.frame.minY < masthead.frame.maxY && icon.frame.maxY > masthead.frame.minY)
        }

        @Test func dayWithoutAnEntityLinkHasNoIcon() async throws {
            let context = try await Self.graphVault()
            defer { context.clean() }
            let mount = HostedLayout.Mount(Self.page(context, day: "2026-10-05"), size: Self.size)
            defer { mount.window.contentView = nil }
            let heading = { HostedControls.nodes(in: mount).contains { $0.role == "AXHeading" } }
            guard await HostedControls.isAvailable(mount, until: heading) else { return }
            await mount.settle(rounds: 12)
            #expect(HostedControls.node(Self.identifier, in: mount) == nil)
        }

        static let size = CGSize(width: 720, height: 420)

        /// The graph fixture vault plus a day whose only link resolves to nothing.
        private static func graphVault() async throws -> TaskTestContext {
            let context = try TaskTestContext()
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Fixtures/vaults/graph")
            try FileManager.default.copyItem(at: fixture, to: context.root)
            try "## Events\n- 09:00 [[Olmayan Kayıt]] aradı.\n".write(
                to: context.root.appendingPathComponent("journal/2026-10-05.md"), atomically: true,
                encoding: .utf8)
            await context.start()
            return context
        }

        private static func page(_ context: TaskTestContext, day: String) -> some View {
            let defaults = context.defaults.defaults
            return NavigationStack { DayView(store: context.store, date: CalendarDate(day)!) }
                .environment(NotificationService(center: FakeNotificationCenter(), defaults: defaults))
                .environment(CalendarService(source: DayGraphHostedCalendarSource()))
                .environment(LocationService(source: FakeLocationSource(), defaults: defaults))
                .environment(\.openSearch, {})
                .environment(\.locale, Locale(identifier: "tr_TR"))
                .inkPage()
        }
    }

    @MainActor private final class DayGraphHostedCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.notDetermined
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
