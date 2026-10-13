#if os(iOS)
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

    /// The iOS main shell with the sample vault, hosted in a window whose size classes are
    /// overridden: what the gate really draws for each scene an iPhone reports. The split shell
    /// is the Mac shell compiled for iOS; `NavigationSplitView` behaves differently there, so
    /// this reads the UIKit tree it builds (a split controller, its columns, the sidebar rows).
    @MainActor @Suite(.serialized, .timeLimit(.minutes(2)))
    struct AdaptiveShellHostedTests {
        /// iPhone Duo inner screen, opened flat (about 890 × 626 pt): the Günlük list beside
        /// Today, the sidebar put away behind its button.
        @Test func innerScreenDrawsTheSplitShell() async throws {
            try await Shell.hosted(size: CGSize(width: 890, height: 626), horizontal: .regular, vertical: .regular) {
                shell in
                #expect(shell.tabBar == nil, "the split shell has no tab bar")
                let split = try #require(shell.split, "no split view under the shell")
                #expect(!split.isCollapsed, "a collapsed split is a phone stack")
                #expect(split.style == .tripleColumn, "sidebar, list column and detail")
                #expect(split.displayMode == .oneBesideSecondary, "list beside the page, sidebar put away")
                let list = try #require(shell.onScreen(.supplementary), "list column off screen")
                let page = try #require(shell.onScreen(.secondary), "detail column off screen")
                #expect(list.maxX <= page.minX + 1, "list \(list) beside the page \(page)")
                #expect(page.width >= 445, "the page keeps at least half the screen: \(page)")
                #expect(shell.rowCounts(in: .supplementary).first ?? 0 > 0, "the Günlük list has days")
            }
        }

        /// The sidebar button brings back the Mac sidebar's rows; a row chosen there opens its
        /// section and puts the sidebar away again (two-column tier).
        @Test func sidebarRowOpensItsSectionAndStepsAside() async throws {
            try await Shell.hosted(size: CGSize(width: 890, height: 626), horizontal: .regular, vertical: .regular) {
                shell in
                let split = try #require(shell.split)
                split.show(.primary)
                await shell.settle()
                let sidebar = try #require(shell.onScreen(.primary), "sidebar did not open")
                let rows = try #require(shell.collectionViews(in: .primary).first, "sidebar has no list")
                let projects = try await shell.store.computeProjects()
                #expect(
                    rows.numberOfItems(inSection: 0) == MacSidebar.entries(projects: projects).count,
                    "one row per sidebar entry")
                // iOS 26 floats the sidebar 10 pt in from the edge.
                #expect(sidebar.minX <= 12 && sidebar.width < 445, "sidebar at the leading edge: \(sidebar)")

                // "Görevler": the third row, as on the Mac.
                let tasks = IndexPath(item: 2, section: 0)
                rows.selectItem(at: tasks, animated: false, scrollPosition: [])
                rows.delegate?.collectionView?(rows, didSelectItemAt: tasks)
                await shell.settle()
                #expect(split.displayMode == .oneBesideSecondary, "the sidebar steps aside after a choice")
                #expect(shell.onScreen(.primary) == nil, "sidebar still on screen")
                #expect(
                    shell.navigation.section == .tasks, "the row opened \(String(describing: shell.navigation.section))"
                )
                #expect(shell.onScreen(.supplementary) != nil, "the Görevler list is beside the detail")
                // A root page hides its bar on the phone; here the bar holds the sidebar button.
                #expect(shell.isBarHidden(.supplementary) == false, "the Görevler column lost its sidebar button")
            }
        }

        /// Tent pose: the inner screen upright (about 626 × 890 pt) is regular × regular too.
        @Test func uprightInnerScreenKeepsTheSplitShell() async throws {
            try await Shell.hosted(size: CGSize(width: 626, height: 890), horizontal: .regular, vertical: .regular) {
                shell in
                let split = try #require(shell.split)
                #expect(!split.isCollapsed)
                #expect(shell.tabBar == nil)
            }
        }

        /// Duo cover screen and every iPhone in portrait: compact × regular.
        @Test func coverScreenDrawsTheTabs() async throws {
            try await Shell.hosted(size: CGSize(width: 466, height: 678), horizontal: .compact, vertical: .regular) {
                shell in
                try shell.expectTabs()
            }
        }

        /// iPhone Pro Max in landscape: regular width, compact height. Only the width is regular,
        /// so the phone keeps its tabs.
        @Test func regularWidthAloneKeepsTheTabs() async throws {
            try await Shell.hosted(size: CGSize(width: 956, height: 440), horizontal: .regular, vertical: .compact) {
                shell in
                try shell.expectTabs()
            }
        }

        @MainActor
        struct Shell {
            let host: UIHostingController<AnyView>
            let store: IndexStore
            let navigation: ShellNavigationState

            var split: UISplitViewController? { Self.controllers(of: UISplitViewController.self, under: host).first }
            var tabBar: UITabBarController? { Self.controllers(of: UITabBarController.self, under: host).first }

            func expectTabs() throws {
                let tabs = try #require(tabBar, "no tab bar under the shell")
                #expect(tabs.viewControllers?.count == 5, "five tabs")
                #expect(split == nil || split?.isCollapsed == true, "no side-by-side columns")
            }

            /// The column's frame in the window, or nil when it is not on screen.
            func onScreen(_ column: UISplitViewController.Column) -> CGRect? {
                guard let view = split?.viewController(for: column)?.viewIfLoaded, let window = view.window,
                    !view.isHidden, view.bounds.width > 0
                else { return nil }
                let frame = view.convert(view.bounds, to: window)
                return frame.intersects(window.bounds) && frame.maxX > 1 ? frame : nil
            }

            /// Whether the column's navigation bar is hidden; nil without a navigation controller.
            func isBarHidden(_ column: UISplitViewController.Column) -> Bool? {
                guard let controller = split?.viewController(for: column) else { return nil }
                let navigation =
                    controller as? UINavigationController ?? controller.navigationController
                    ?? Self.controllers(of: UINavigationController.self, under: controller).first
                return navigation?.isNavigationBarHidden
            }

            func collectionViews(in column: UISplitViewController.Column) -> [UICollectionView] {
                views(of: UICollectionView.self, in: column)
            }

            func rowCounts(in column: UISplitViewController.Column) -> [Int] {
                collectionViews(in: column).map { $0.numberOfSections > 0 ? $0.numberOfItems(inSection: 0) : 0 }
            }

            private func views<T: UIView>(of type: T.Type, in column: UISplitViewController.Column) -> [T] {
                guard let root = split?.viewController(for: column)?.viewIfLoaded else { return [] }
                var found: [T] = []
                func walk(_ view: UIView) {
                    if let match = view as? T { found.append(match) }
                    view.subviews.forEach(walk)
                }
                walk(root)
                return found
            }

            /// Lets SwiftUI and the split controller apply pending updates.
            func settle(rounds: Int = 10) async {
                for _ in 0..<rounds {
                    await Task.yield()
                    try? await Task.sleep(for: .milliseconds(30))
                    host.view.setNeedsLayout()
                    host.view.layoutIfNeeded()
                }
            }

            static func controllers<T: UIViewController>(of type: T.Type, under root: UIViewController) -> [T] {
                var found: [T] = []
                func walk(_ controller: UIViewController) {
                    if let match = controller as? T { found.append(match) }
                    controller.children.forEach(walk)
                }
                walk(root)
                return found
            }

            /// Hosts `AdaptiveNavigation` in a window of `size` with the given size classes and
            /// runs `body` once the vault is indexed and the tree has settled.
            static func hosted(
                size: CGSize, horizontal: UIUserInterfaceSizeClass, vertical: UIUserInterfaceSizeClass,
                _ body: @MainActor (Shell) async throws -> Void
            ) async throws {
                let context = try TaskTestContext(sample: true)
                await context.start()
                let defaults = context.defaults.defaults
                let location = LocationService(source: FakeLocationSource(), defaults: defaults)
                let navigation = ShellNavigationState()
                let view = AdaptiveNavigation(store: context.store, navigation: navigation)
                    .environment(NotificationService(center: FakeNotificationCenter(), defaults: defaults))
                    .environment(CalendarService(source: IdleCalendarSource()))
                    .environment(location)
                    .environment(
                        GeofenceService(location: location, center: FakeGeofenceCenter(), defaults: defaults)
                    )
                    .environment(IntentNavigation())
                    .environment(\.openSearch, {})
                    .transaction { $0.animation = nil }
                var failure: (any Error)?
                await SnapshotHostGate.exclusive {
                    let previousAnimations = UIView.areAnimationsEnabled
                    UIView.setAnimationsEnabled(false)
                    defer { UIView.setAnimationsEnabled(previousAnimations) }
                    let host = UIHostingController(rootView: AnyView(view))
                    host.traitOverrides.horizontalSizeClass = horizontal
                    host.traitOverrides.verticalSizeClass = vertical
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
                    let shell = Shell(host: host, store: context.store, navigation: navigation)
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

    @MainActor
    private final class IdleCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.notDetermined
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
