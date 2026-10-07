#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

    /// Denetim kalıbı bileşenleri: manşet satırı (0 / 1 / 3 simge), sekme, etiketli menü,
    /// süzgeç alanı, vurgu renkli anahtar ve iki sheet türü (düzenleyen, yalnız okunan).
    enum ComponentSnapshotCase: String, CaseIterable, Sendable {
        case patternsLight, patternsDark, patternsAX3, patternsContrast
        case sheetEditingLight, sheetEditingDark, sheetEditingAX3, sheetEditingContrast
        case sheetBusyLight
        case sheetReadingLight, sheetReadingDark, sheetReadingAX3, sheetReadingContrast

        enum Subject: Sendable {
            case patterns
            case sheet(ComponentGallerySheet.Kind)
        }

        var subject: Subject {
            switch self {
            case .patternsLight, .patternsDark, .patternsAX3, .patternsContrast: .patterns
            case .sheetEditingLight, .sheetEditingDark, .sheetEditingAX3, .sheetEditingContrast:
                .sheet(.editing)
            case .sheetBusyLight: .sheet(.busy)
            case .sheetReadingLight, .sheetReadingDark, .sheetReadingAX3, .sheetReadingContrast:
                .sheet(.reading)
            }
        }

        var colorScheme: SnapshotColorScheme {
            switch self {
            case .patternsDark, .sheetEditingDark, .sheetReadingDark: .dark
            default: .light
            }
        }

        var dynamicType: SnapshotDynamicType {
            switch self {
            case .patternsAX3, .sheetEditingAX3, .sheetReadingAX3: .accessibility3
            default: .medium
            }
        }

        var increaseContrast: Bool {
            switch self {
            case .patternsContrast, .sheetEditingContrast, .sheetReadingContrast: true
            default: false
            }
        }

        /// The pattern page is taller than a phone at AX3; sheets keep a short canvas.
        var canvas: CGSize {
            switch subject {
            case .patterns:
                dynamicType == .accessibility3
                    ? CGSize(width: 390, height: 1500) : CGSize(width: 390, height: 844)
            case .sheet:
                dynamicType == .accessibility3
                    ? CGSize(width: 390, height: 700) : CGSize(width: 390, height: 420)
            }
        }
    }

    @MainActor @Suite("Component snapshots")
    struct ComponentSnapshotTests {
        @Test(arguments: ComponentSnapshotCase.allCases)
        func component(_ snapshotCase: ComponentSnapshotCase) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            await SnapshotHost.assertView(
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: snapshotCase.increaseContrast,
                named: snapshotCase.rawValue,
                store: context.store,
                size: snapshotCase.canvas,
                testName: "component"
            ) {
                Self.hostedView(snapshotCase.subject)
                    .environment(\.locale, snapshotLocale)
                    .environment(\.openSearch, {})
            }
        }

        @ViewBuilder private static func hostedView(_ subject: ComponentSnapshotCase.Subject)
            -> some View
        {
            switch subject {
            case .patterns:
                ScrollView {
                    ComponentGalleryPatterns()
                        .padding(InkSpacing.margin)
                }
                .inkPage()
            case .sheet(let kind):
                NavigationStack { ComponentGallerySheet(kind: kind) }
            }
        }
    }
#endif
