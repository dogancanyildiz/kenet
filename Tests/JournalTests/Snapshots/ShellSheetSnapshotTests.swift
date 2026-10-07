#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    import VaultFormat

    @testable import Journal

    /// Sheet kinds of the shell area in the control patterns: Settings (read-only, "Kapat"),
    /// the one-line text editor and the entity type editor (editing, "Vazgeç" / "Kaydet" or
    /// "Oluştur"), and vault preparation (editing, three accent toggles).
    enum ShellSheetSnapshotCase: String, CaseIterable, Sendable {
        case settingsSheetLight, settingsSheetDark, settingsSheetAX3
        case textEditorLight, textEditorDark, textEditorAX3
        case entityTypeEditorLight, entityTypeEditorDark, entityTypeEditorAX3
        case vaultImportLight, vaultImportDark, vaultImportAX3

        enum Subject: Sendable { case settings, textEditor, entityTypeEditor, vaultImport }

        var subject: Subject {
            switch self {
            case .settingsSheetLight, .settingsSheetDark, .settingsSheetAX3: .settings
            case .textEditorLight, .textEditorDark, .textEditorAX3: .textEditor
            case .entityTypeEditorLight, .entityTypeEditorDark, .entityTypeEditorAX3: .entityTypeEditor
            case .vaultImportLight, .vaultImportDark, .vaultImportAX3: .vaultImport
            }
        }

        var colorScheme: SnapshotColorScheme {
            switch self {
            case .settingsSheetDark, .textEditorDark, .entityTypeEditorDark, .vaultImportDark: .dark
            default: .light
            }
        }

        var dynamicType: SnapshotDynamicType {
            switch self {
            case .settingsSheetAX3, .textEditorAX3, .entityTypeEditorAX3, .vaultImportAX3: .accessibility3
            default: .medium
            }
        }

        /// Long forms get a tall canvas so every row is in the picture.
        var canvas: CGSize {
            let large = dynamicType == .accessibility3
            switch subject {
            case .settings: return CGSize(width: 390, height: large ? 1100 : 844)
            case .textEditor: return CGSize(width: 390, height: large ? 700 : 420)
            case .entityTypeEditor: return CGSize(width: 390, height: large ? 2600 : 1300)
            case .vaultImport: return CGSize(width: 390, height: large ? 2800 : 1300)
            }
        }
    }

    @MainActor @Suite("Shell sheet snapshots", .serialized)
    struct ShellSheetSnapshotTests {
        @Test(arguments: ShellSheetSnapshotCase.allCases)
        func shellSheet(_ snapshotCase: ShellSheetSnapshotCase) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            let importModel: VaultImportModel? =
                snapshotCase.subject == .vaultImport ? try await VaultImportModel(root: context.root) : nil
            let typeModel = Self.bookTypeModel(store: context.store)
            await SnapshotHost.assertView(
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: false,
                named: snapshotCase.rawValue,
                store: context.store,
                size: snapshotCase.canvas,
                testName: "shellSheet"
            ) {
                NavigationStack {
                    switch snapshotCase.subject {
                    case .settings:
                        PhoneSettingsView(store: context.store)
                            .inkSheet("Ayarlar", closeIdentifier: "button.settings.close")
                    case .textEditor:
                        SingleLineTextEditor(
                            text: .constant("Deniz ile sahilde yürüyüş"), placeholder: "Olay metni",
                            canSave: true, isDisabled: false, isSaving: false, errorText: nil,
                            load: {}, save: { false })
                    case .entityTypeEditor:
                        EntityTypeEditorView(model: typeModel)
                    case .vaultImport:
                        if let importModel {
                            VaultImportView(store: context.store, model: importModel)
                        }
                    }
                }
                .environment(\.locale, snapshotLocale)
                .environment(\.openSearch, {})
                .environment(\.vaultPathDisplayOverride, VaultPathDisplay.snapshotExample)
            }
        }

        /// A new, fictional "book" type with two fields.
        private static func bookTypeModel(store: IndexStore) -> EntityTypeEditorModel {
            let model = EntityTypeEditorModel(store: store)
            model.id = "book"
            model.folder = "books"
            model.nameTR = "Kitap"
            model.nameEN = "Book"
            model.pluralTR = "Kitaplar"
            model.pluralEN = "Books"
            model.icon = "book"
            model.fields = [
                EntityTypeFieldDraft(key: "yazar", kind: .text),
                EntityTypeFieldDraft(key: "bitti", kind: .date),
            ]
            return model
        }
    }
#endif
