#if os(iOS)
    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// The type gallery sheet ("Varlık tipi ekle", with Kitap already in the vault) and the
    /// Kişiler ve Konumlar list's "Yeni tip…" row, under people and under a custom type
    /// ("Yeni kitap").
    enum EntityGallerySnapshotCase: String, CaseIterable, Sendable {
        case galleryLight, galleryDark, galleryAX3
        /// Film picked: the type editor pushed inside the gallery, filled with the film type.
        case galleryEditorLight
        case peopleNewTypeLight
        case customKindLight, customKindDark, customKindAX3

        enum Subject: Sendable { case gallery, galleryEditor, people, customKind }

        var subject: Subject {
            switch self {
            case .galleryLight, .galleryDark, .galleryAX3: .gallery
            case .galleryEditorLight: .galleryEditor
            case .peopleNewTypeLight: .people
            case .customKindLight, .customKindDark, .customKindAX3: .customKind
            }
        }

        var colorScheme: SnapshotColorScheme {
            switch self {
            case .galleryDark, .customKindDark: .dark
            default: .light
            }
        }

        var dynamicType: SnapshotDynamicType {
            switch self {
            case .galleryAX3, .customKindAX3: .accessibility3
            default: .medium
            }
        }

        /// The gallery lists ten two-line rows; its canvas shows the whole sheet.
        var canvas: CGSize {
            switch subject {
            case .gallery:
                dynamicType == .accessibility3
                    ? CGSize(width: 390, height: 2000) : CGSize(width: 390, height: 900)
            case .galleryEditor: CGSize(width: 390, height: 1700)
            case .people, .customKind: snapshotCanvasSize
            }
        }
    }

    @MainActor @Suite("Entity gallery snapshots", .serialized)
    struct EntityGallerySnapshotTests {
        @Test(arguments: EntityGallerySnapshotCase.allCases)
        func gallery(_ snapshotCase: EntityGallerySnapshotCase) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            if snapshotCase.subject != .people {
                try Self.writeBookType(in: context.root)
            }
            await context.start()
            #expect(context.store.lastUpdated != nil)
            let store = context.store
            await SnapshotHost.assertView(
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: false,
                named: snapshotCase.rawValue,
                store: store,
                size: snapshotCase.canvas,
                testName: "entityGallery",
                content: {
                    Self.hostedView(snapshotCase.subject, store: store)
                        .environment(IntentNavigation())
                        .environment(\.locale, snapshotLocale)
                        .environment(\.timeZone, snapshotTimeZone)
                        .environment(\.openSearch, {})
                }
            )
        }

        @ViewBuilder private static func hostedView(
            _ subject: EntityGallerySnapshotCase.Subject, store: IndexStore
        ) -> some View {
            switch subject {
            case .gallery:
                NavigationStack { EntityTypeGalleryView(store: store) { _ in } }
            case .galleryEditor:
                NavigationStack {
                    EntityTypeGalleryView(
                        store: store,
                        opening: EntityTypeGallery.items.first { $0.definition.id == "film" }?.definition
                    ) { _ in }
                }
            case .people:
                NavigationStack { EntitiesView(store: store) }
            case .customKind:
                NavigationStack { EntitiesView(store: store, initialKind: "book") }
            }
        }

        /// The gallery's own Kitap type, so the gallery shows it as added and the list offers
        /// "Yeni kitap".
        private static func writeBookType(in root: URL) throws {
            let book = try #require(EntityTypeGallery.items.first { $0.definition.id == "book" }).definition
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let folder = root.appendingPathComponent(".app")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try encoder.encode(EntityTypesFile(types: [book])).write(to: folder.appendingPathComponent("types.json"))
        }
    }
#endif
