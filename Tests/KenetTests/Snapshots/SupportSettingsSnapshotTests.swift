#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @testable import Kenet

    enum SupportSettingsSnapshotCase: String, CaseIterable, Sendable {
        case loadedLight
        case unavailableLight
        case thankedLight
        case unverifiedLight
        case supporterLight

        var colorScheme: SnapshotColorScheme { .light }

        var dynamicType: SnapshotDynamicType { .medium }
    }

    /// The support page over a store in memory (``InMemorySupportStorefront``): no App Store.
    @MainActor @Suite("Support settings snapshots", .serialized)
    struct SupportSettingsSnapshotTests {
        static func service(for snapshotCase: SupportSettingsSnapshotCase) async -> SupportService {
            let storefront = InMemorySupportStorefront()
            switch snapshotCase {
            case .loadedLight, .thankedLight: break
            case .supporterLight: storefront.history = [SupportHistoryEntry(productID: SupportTier.large.productID)]
            case .unavailableLight: storefront.catalog = nil
            case .unverifiedLight: storefront.purchaseOutcome = .unverified
            }
            let service = SupportService(storefront: storefront)
            await service.loadProducts()
            await service.refreshBadges()
            switch snapshotCase {
            case .thankedLight, .unverifiedLight: await service.buy(.medium)
            case .loadedLight, .unavailableLight, .supporterLight: break
            }
            return service
        }

        /// Hakkında with both badges on top: supporter (medium) and test team.
        @Test func aboutWithBadges() async throws {
            let context = try TaskTestContext(sample: false)
            defer { context.clean() }
            let service = SupportService(
                storefront: InMemorySupportStorefront(history: [.medium]), testerProbe: { true })
            await service.refreshBadges()

            await SnapshotHost.assertView(
                colorScheme: .light, dynamicType: .medium, increaseContrast: false, named: "badges",
                store: context.store, testName: "about"
            ) {
                NavigationStack {
                    AboutSettingsView()
                }
                .environment(service)
                .environment(\.locale, snapshotLocale)
            }
        }

        @Test(arguments: SupportSettingsSnapshotCase.allCases)
        func support(_ snapshotCase: SupportSettingsSnapshotCase) async throws {
            let context = try TaskTestContext(sample: false)
            defer { context.clean() }
            let service = await Self.service(for: snapshotCase)

            await SnapshotHost.assertView(
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: false,
                named: snapshotCase.rawValue,
                store: context.store,
                testName: "support"
            ) {
                NavigationStack {
                    SupportSettingsView(service: service)
                }
                .environment(\.locale, snapshotLocale)
            }
        }
    }
#endif
