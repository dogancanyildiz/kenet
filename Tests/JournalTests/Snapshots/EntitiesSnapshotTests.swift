#if os(iOS)
    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    import VaultFormat

    @testable import Journal

    /// Kişiler ve Konumlar kök ekranı (kişi listesi, konum listesi, dolu süzgeç, özel tipli
    /// "Tür" menüsü) ve varlık sheet'leri (düzenleme, ad değiştirme, çözülmemiş bağlantı).
    enum EntitiesSnapshotCase: String, CaseIterable, Sendable {
        case peopleLight, peopleDark, peopleAX3, peopleContrast
        case placesLight, placesDark
        case filteredLight, filteredDark
        case customTypesLight, customTypesDark, customTypesAX3
        case editSheetLight, editSheetDark, editSheetAX3
        case renameSheetLight, renameSheetDark, renameSheetAX3
        case unresolvedLight, unresolvedDark, unresolvedAX3

        enum Subject: Sendable {
            case people, places, filtered, customTypes, editSheet, renameSheet, unresolved
        }

        var subject: Subject {
            switch self {
            case .peopleLight, .peopleDark, .peopleAX3, .peopleContrast: .people
            case .placesLight, .placesDark: .places
            case .filteredLight, .filteredDark: .filtered
            case .customTypesLight, .customTypesDark, .customTypesAX3: .customTypes
            case .editSheetLight, .editSheetDark, .editSheetAX3: .editSheet
            case .renameSheetLight, .renameSheetDark, .renameSheetAX3: .renameSheet
            case .unresolvedLight, .unresolvedDark, .unresolvedAX3: .unresolved
            }
        }

        var colorScheme: SnapshotColorScheme {
            switch self {
            case .peopleDark, .placesDark, .filteredDark, .customTypesDark, .editSheetDark,
                .renameSheetDark, .unresolvedDark:
                .dark
            default: .light
            }
        }

        var dynamicType: SnapshotDynamicType {
            switch self {
            case .peopleAX3, .customTypesAX3, .editSheetAX3, .renameSheetAX3, .unresolvedAX3:
                .accessibility3
            default: .medium
            }
        }

        var increaseContrast: Bool { self == .peopleContrast }

        /// The edit sheet is taller than a phone; the two short sheets keep a short canvas.
        var canvas: CGSize {
            switch subject {
            case .people, .places, .filtered, .customTypes: snapshotCanvasSize
            case .editSheet:
                dynamicType == .accessibility3
                    ? CGSize(width: 390, height: 1400) : CGSize(width: 390, height: 1000)
            case .renameSheet, .unresolved:
                dynamicType == .accessibility3
                    ? CGSize(width: 390, height: 800) : CGSize(width: 390, height: 480)
            }
        }
    }

    @MainActor @Suite("Entities snapshots")
    struct EntitiesSnapshotTests {
        private static let personPath = "people/Deniz Arıkan.md"

        @Test(arguments: EntitiesSnapshotCase.allCases)
        func entities(_ snapshotCase: EntitiesSnapshotCase) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            if snapshotCase.subject == .customTypes {
                try Self.writeCustomTypes(in: context.root)
            }
            await context.start()
            #expect(context.store.lastUpdated != nil)
            let store = context.store
            let detail = EntityDetailModel(store: store, path: Self.personPath)
            if snapshotCase.subject == .editSheet || snapshotCase.subject == .renameSheet {
                await detail.load()
                #expect(detail.isLoaded)
            }
            let person = try #require(store.content.entities.first { $0.id == Self.personPath })
            await SnapshotHost.assertView(
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: snapshotCase.increaseContrast,
                named: snapshotCase.rawValue,
                store: store,
                size: snapshotCase.canvas,
                testName: "entities"
            ) {
                Self.hostedView(snapshotCase.subject, store: store, detail: detail, person: person)
                    .environment(IntentNavigation())
                    .environment(\.locale, snapshotLocale)
                    .environment(\.timeZone, snapshotTimeZone)
                    .environment(\.openSearch, {})
            }
        }

        @ViewBuilder private static func hostedView(
            _ subject: EntitiesSnapshotCase.Subject, store: IndexStore, detail: EntityDetailModel,
            person: EntitySummary
        ) -> some View {
            switch subject {
            case .people, .customTypes:
                NavigationStack { EntitiesView(store: store) }
            case .places:
                NavigationStack { EntitiesView(store: store, initialKind: "place", initialOrder: .recent) }
            case .filtered:
                NavigationStack { EntitiesView(store: store, initialSearch: "Mert") }
            case .editSheet:
                // The sheets own their `NavigationStack`.
                EntityEditSheet(store: store, model: detail, entity: person)
            case .renameSheet:
                EntityRenameView(
                    model: EntityRenameModel(detail: detail, name: person.name, qualifier: person.qualifier))
            case .unresolved:
                NavigationStack { UnresolvedEntityView(store: store, target: "Aras Demirkol") }
            }
        }

        /// Two custom types bring the choice count to four, where the tabs give way to the menu.
        private static func writeCustomTypes(in root: URL) throws {
            let json = """
                {
                  "formatVersion": 1,
                  "types": [
                    {
                      "id": "book", "folder": "books",
                      "name": { "tr": "Kitap", "en": "Book" },
                      "plural": { "tr": "Kitaplar", "en": "Books" },
                      "icon": "book", "fields": []
                    },
                    {
                      "id": "album", "folder": "albums",
                      "name": { "tr": "Albüm", "en": "Album" },
                      "plural": { "tr": "Albümler", "en": "Albums" },
                      "icon": "music.note", "fields": []
                    }
                  ]
                }
                """
            let folder = root.appendingPathComponent(".app")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(json.utf8).write(to: folder.appendingPathComponent("types.json"))
        }
    }
#endif
