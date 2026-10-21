#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

    /// The home-screen chain widget, drawn from `Widgets/Shared` in the app host: small and medium,
    /// open goals first in full ink with done ones receded, "open Kenet" without a snapshot, and
    /// AX3. The widget's container (paper, rounded, system margins) is drawn here by hand.
    enum WidgetViewSnapshotCase: String, CaseIterable, Sendable {
        case smallLight, smallAX3, smallOpenKenet
        case mediumLight, mediumDark, mediumAX3

        var layout: GoalChainLayout {
            switch self {
            case .smallLight, .smallAX3, .smallOpenKenet: .small
            case .mediumLight, .mediumDark, .mediumAX3: .medium
            }
        }

        var colorScheme: SnapshotColorScheme { self == .mediumDark ? .dark : .light }

        var dynamicType: SnapshotDynamicType {
            switch self {
            case .smallAX3, .mediumAX3: .accessibility3
            default: .medium
            }
        }

        var day: WidgetSnapshot.Day? { self == .smallOpenKenet ? nil : WidgetViewSnapshotTests.day }

        /// iPhone 17 widget sizes (points).
        var widgetSize: CGSize {
            layout == .small ? CGSize(width: 170, height: 170) : CGSize(width: 364, height: 170)
        }
    }

    @MainActor @Suite("Widget view snapshots")
    struct WidgetViewSnapshotTests {
        /// Two open goals (a yes/no one with chain days, a number one on its way) and two done ones,
        /// in the order the app writes them.
        nonisolated static let day = WidgetSnapshot.Day(
            date: "2026-09-20",
            goals: WidgetSnapshot.ordered([
                .init(
                    key: "esneme", name: "Esneme", kind: .boolean, target: 1, unit: nil, value: 0,
                    isPending: true, streak: 64, chainDays: 2),
                .init(
                    key: "su", name: "Su", kind: .number, target: 8, unit: "bardak", value: 3,
                    isPending: true, streak: 12, chainDays: 0),
                .init(
                    key: "okuma", name: "Okuma", kind: .boolean, target: 1, unit: nil, value: 1,
                    isPending: false, streak: 5, chainDays: 0),
                .init(
                    key: "yuruyus", name: "Yürüyüş", kind: .boolean, target: 1, unit: nil, value: 1,
                    isPending: false, streak: 30, chainDays: 3),
            ]))

        @Test(arguments: WidgetViewSnapshotCase.allCases)
        func widget(_ snapshotCase: WidgetViewSnapshotCase) async throws {
            let context = try TaskTestContext()
            defer { context.clean() }
            let size = snapshotCase.widgetSize
            await SnapshotHost.assertView(
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: false,
                named: snapshotCase.rawValue,
                store: context.store,
                size: CGSize(width: size.width + 40, height: size.height + 40),
                testName: "widget"
            ) {
                GoalChainWidgetView(
                    day: snapshotCase.day,
                    link: snapshotCase.layout == .medium
                        ? { WidgetSnapshot.link(for: $0, vaultID: "vault").url } : nil,
                    layout: snapshotCase.layout
                )
                .padding(16)
                .frame(width: size.width, height: size.height)
                .background(WidgetTheme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.ink.well)
                .environment(\.locale, snapshotLocale)
            }
        }
    }
#endif
