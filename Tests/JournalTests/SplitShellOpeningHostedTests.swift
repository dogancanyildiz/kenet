#if os(iOS)
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

    /// How the split shell opens (`docs/screens.md`, "Bölünmüş kabuk"): the split view is built
    /// only after the shell has measured its width, so it is configured with the columns that
    /// width asks for before its first layout.
    ///
    /// Built before the measurement it opened with the system's own visibility, and its first
    /// layout wrote that back over the shell's request (an upright 13" iPad: "detail only",
    /// landscape: "list and detail"). Only a second layout pass brought the three columns
    /// back, and on some cold starts in the simulator it never came: the sidebar stayed away
    /// although the user had not put it away.
    @MainActor @Suite(.serialized, .timeLimit(.minutes(3)))
    struct SplitShellOpeningHostedTests {
        struct Opening: Sendable, CustomTestStringConvertible {
            let width: CGFloat
            let height: CGFloat
            let section: DesktopSection
            let mode: UISplitViewController.DisplayMode
            let window: String
            var size: CGSize { CGSize(width: width, height: height) }
            var testDescription: String { "\(window), \(section.rawValue)" }
        }

        /// The first split view under the shell already asks for the tier's columns. A section
        /// chosen before the measurement (a notification or Siri route at launch) opens in its
        /// own layout with the same columns.
        @Test(arguments: [
            Opening(width: 1032, height: 1376, section: .today, mode: .twoBesideSecondary, window: "13\" upright"),
            Opening(width: 1376, height: 1032, section: .today, mode: .twoBesideSecondary, window: "13\" landscape"),
            Opening(width: 1032, height: 1376, section: .goals, mode: .twoBesideSecondary, window: "13\" upright"),
            Opening(width: 1032, height: 1376, section: .summaries, mode: .oneBesideSecondary, window: "13\" upright"),
            Opening(width: 834, height: 1210, section: .today, mode: .oneBesideSecondary, window: "11\" upright"),
        ])
        func firstSplitViewAsksForTheTiersColumns(_ opening: Opening) async throws {
            let navigation = ShellNavigationState()
            navigation.section = opening.section
            try await Self.firstSight(size: opening.size, navigation: navigation) { split in
                #expect(
                    split.preferredDisplayMode == opening.mode,
                    "first split view asks for mode \(split.preferredDisplayMode.rawValue)")
            }
        }

        /// Builds the shell in a window of `size` and hands over the first split view under it,
        /// one layout pass at a time, before anything settles.
        private static func firstSight(
            size: CGSize, navigation: ShellNavigationState,
            _ body: @MainActor (UISplitViewController) throws -> Void
        ) async throws {
            let context = try TaskTestContext(sample: true)
            await context.start()
            let defaults = context.defaults.defaults
            let location = LocationService(source: FakeLocationSource(), defaults: defaults)
            let view = AdaptiveNavigation(store: context.store, navigation: navigation)
                .environment(NotificationService(center: FakeNotificationCenter(), defaults: defaults))
                .environment(CalendarService(source: OpeningCalendarSource()))
                .environment(location)
                .environment(GeofenceService(location: location, center: FakeGeofenceCenter(), defaults: defaults))
                .environment(IntentNavigation())
                .environment(\.openSearch, {})
                .transaction { $0.animation = nil }
            var failure: (any Error)?
            await SnapshotHostGate.exclusive {
                let previousAnimations = UIView.areAnimationsEnabled
                UIView.setAnimationsEnabled(false)
                defer { UIView.setAnimationsEnabled(previousAnimations) }
                let host = UIHostingController(rootView: AnyView(view))
                host.traitOverrides.horizontalSizeClass = .regular
                host.traitOverrides.verticalSizeClass = .regular
                host.view.frame = CGRect(origin: .zero, size: size)
                guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
                else {
                    Issue.record("The shell needs a UIWindowScene (run under the Journal test host).")
                    return
                }
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(origin: .zero, size: size)
                window.rootViewController = host
                window.isHidden = false
                defer {
                    window.isHidden = true
                    window.rootViewController = nil
                    window.windowScene = nil
                }
                for _ in 0..<200 {
                    host.view.layoutIfNeeded()
                    if let split = AdaptiveShellHostedTests.Shell.controllers(
                        of: UISplitViewController.self, under: host
                    ).first {
                        do { try body(split) } catch { failure = error }
                        return
                    }
                    await Task.yield()
                }
                Issue.record("no split view under the shell")
            }
            if let failure { throw failure }
        }
    }

    @MainActor
    private final class OpeningCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.notDetermined
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
