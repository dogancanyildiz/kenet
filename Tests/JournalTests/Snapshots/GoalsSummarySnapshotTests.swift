#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

    /// Hedefler, Özetler, Graph: açık, koyu, AX3, Kontrastı Artır.
    /// Harita MapKit host çökmesi yüzünden bu kümede yok; pin boyutu/yoğunluk `GraphMapTests` ile kilitli.
    enum GoalsSummarySnapshotCase: String, CaseIterable, Sendable {
        case goalsLight, goalsDark, goalsAX3, goalsContrast
        case summariesLight, summariesDark, summariesAX3, summariesContrast
        case graphLight, graphDark, graphAX3, graphContrast

        var screen: SnapshotScreen {
            switch self {
            case .goalsLight, .goalsDark, .goalsAX3, .goalsContrast: .goals
            case .summariesLight, .summariesDark, .summariesAX3, .summariesContrast: .summaries
            case .graphLight, .graphDark, .graphAX3, .graphContrast: .graph
            }
        }

        var colorScheme: SnapshotColorScheme {
            switch self {
            case .goalsDark, .summariesDark, .graphDark: .dark
            default: .light
            }
        }

        var dynamicType: SnapshotDynamicType {
            switch self {
            case .goalsAX3, .summariesAX3, .graphAX3: .accessibility3
            default: .medium
            }
        }

        var increaseContrast: Bool {
            switch self {
            case .goalsContrast, .summariesContrast, .graphContrast: true
            default: false
            }
        }
    }

    @MainActor @Suite("Goals summary snapshots")
    struct GoalsSummarySnapshotTests {
        @Test(arguments: GoalsSummarySnapshotCase.allCases)
        func screen(_ snapshotCase: GoalsSummarySnapshotCase) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            #expect(context.store.lastUpdated != nil)
            await GoalsSummarySnapshotHost.assert(
                snapshotCase, store: context.store, defaults: context.defaults.defaults)
        }
    }

    @MainActor
    enum GoalsSummarySnapshotHost {
        static func assert(
            _ snapshotCase: GoalsSummarySnapshotCase, store: IndexStore, defaults: UserDefaults,
            file: StaticString = #filePath, line: UInt = #line
        ) async {
            let view = SnapshotHost.hostedView(
                screen: snapshotCase.screen, store: store, defaults: defaults
            )
            .environment(\.colorScheme, snapshotCase.colorScheme.colorScheme)
            .environment(\.dynamicTypeSize, snapshotCase.dynamicType.size)
            .environment(\.clockNow, { snapshotNow })
            .transaction { $0.animation = nil }
            .frame(width: snapshotCanvasSize.width, height: snapshotCanvasSize.height)

            let traits = UITraitCollection { mutable in
                mutable.userInterfaceStyle = snapshotCase.colorScheme.userInterfaceStyle
                mutable.preferredContentSizeCategory = snapshotCase.dynamicType.contentSize
                mutable.accessibilityContrast = snapshotCase.increaseContrast ? .high : .normal
                mutable.displayScale = 2
            }

            let previousAnimations = UIView.areAnimationsEnabled
            UIView.setAnimationsEnabled(false)
            defer { UIView.setAnimationsEnabled(previousAnimations) }

            let host = UIHostingController(rootView: view)
            host.overrideUserInterfaceStyle = snapshotCase.colorScheme.userInterfaceStyle
            host.view.frame = CGRect(origin: .zero, size: snapshotCanvasSize)

            let scene =
                UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
                ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            guard let scene else {
                Issue.record("Snapshot host needs a UIWindowScene (run under the Journal test host).")
                return
            }
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: snapshotCanvasSize)
            window.overrideUserInterfaceStyle = snapshotCase.colorScheme.userInterfaceStyle
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            for _ in 0..<40 {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(50))
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                if !store.isProcessing { break }
            }
            try? await Task.sleep(for: .milliseconds(800))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(200))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()

            let record = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))

            assertSnapshot(
                of: host,
                as: .image(
                    on: ViewImageConfig.iPhone13,
                    precision: snapshotPrecision,
                    perceptualPrecision: snapshotPerceptualPrecision,
                    size: snapshotCanvasSize,
                    traits: traits
                ),
                named: snapshotCase.rawValue,
                record: record,
                file: file,
                testName: "screen",
                line: line
            )
            window.isHidden = true
            window.rootViewController = nil
        }
    }
#endif
