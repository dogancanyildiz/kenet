#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    import VaultFormat

    @testable import Journal

    enum ContactImportSnapshotCase: String, CaseIterable, Sendable {
        case summaryLight, summaryDark, summaryAX3
        case resultLight, resultDark, resultAX3

        var isResult: Bool {
            switch self {
            case .resultLight, .resultDark, .resultAX3: return true
            default: return false
            }
        }

        var colorScheme: SnapshotColorScheme {
            switch self {
            case .summaryDark, .resultDark: return .dark
            default: return .light
            }
        }

        var dynamicType: SnapshotDynamicType {
            switch self {
            case .summaryAX3, .resultAX3: return .accessibility3
            default: return .medium
            }
        }

        var canvas: CGSize {
            let large = dynamicType == .accessibility3
            return CGSize(width: 390, height: large ? 960 : 720)
        }
    }

    @MainActor @Suite("Contact import snapshots", .serialized)
    struct ContactImportSnapshotTests {
        @Test(arguments: ContactImportSnapshotCase.allCases)
        func contactImport(_ snapshotCase: ContactImportSnapshotCase) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()

            let model = ContactImportModel(
                existing: [ExistingEntityInfo(name: "Deniz Arıkan")],
                creator: { item in
                    if item.name == "Ece Yalın" { throw CocoaError(.fileWriteNoPermission) }
                }
            )

            model.prepare(candidates: [
                ContactName(name: "Baran Kaya", nickname: "Baro"),
                ContactName(name: "Selin Korkmaz"),
                ContactName(name: "Ece Yalın"),
                ContactName(name: "Deniz Arıkan"),
                ContactName(name: ""),
            ])

            if snapshotCase.isResult {
                await model.importContacts()
                #expect(model.result != nil)
            }

            await SnapshotHost.assertView(
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: false,
                named: snapshotCase.rawValue,
                store: context.store,
                size: snapshotCase.canvas,
                testName: "contactImport"
            ) {
                NavigationStack {
                    ContactImportView(model: model, onDismiss: {})
                }
                .environment(\.locale, snapshotLocale)
            }
        }
    }
#endif
