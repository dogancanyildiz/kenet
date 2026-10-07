#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    import VaultFormat

    @testable import Journal

    /// Sheet kinds of the shell area in the control patterns: Settings (read-only, "Kapat"),
    /// the one-line text editor and the entity type editor (editing, "Vazgeç" / "Kaydet" or
    /// "Oluştur"), and vault preparation (cancel-only: "Uygula" is the page's primary button;
    /// with the result in, its section sits directly under the manşet and the bar is empty).
    /// The word in the bar is too small to fail a picture: `ShellSheetKindTests` measures the kind.
    enum ShellSheetSnapshotCase: String, CaseIterable, Sendable {
        case settingsSheetLight, settingsSheetDark, settingsSheetAX3
        case textEditorLight, textEditorDark, textEditorAX3
        case entityTypeEditorLight, entityTypeEditorDark, entityTypeEditorAX3
        case vaultImportLight, vaultImportDark, vaultImportAX3
        case vaultImportResultLight, vaultImportResultAX3
        /// The whole page once, so the page actions ("Uygula", "Atla") are in a picture.
        case vaultImportFullLight

        enum Subject: Sendable { case settings, textEditor, entityTypeEditor, vaultImport, vaultImportResult }

        var subject: Subject {
            switch self {
            case .settingsSheetLight, .settingsSheetDark, .settingsSheetAX3: .settings
            case .textEditorLight, .textEditorDark, .textEditorAX3: .textEditor
            case .entityTypeEditorLight, .entityTypeEditorDark, .entityTypeEditorAX3: .entityTypeEditor
            case .vaultImportLight, .vaultImportDark, .vaultImportAX3, .vaultImportFullLight: .vaultImport
            case .vaultImportResultLight, .vaultImportResultAX3: .vaultImportResult
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
            case .settingsSheetAX3, .textEditorAX3, .entityTypeEditorAX3, .vaultImportAX3,
                .vaultImportResultAX3:
                .accessibility3
            default: .medium
            }
        }

        /// The editor and vault cases use the standard phone canvas at every text size: the
        /// bar, the manşet and the top of the form are in the picture, and the bar words are
        /// not diluted by a tall canvas.
        var canvas: CGSize {
            let large = dynamicType == .accessibility3
            if self == .vaultImportFullLight { return CGSize(width: 390, height: 1500) }
            switch subject {
            case .settings: return CGSize(width: 390, height: large ? 1100 : 844)
            case .textEditor: return CGSize(width: 390, height: large ? 700 : 420)
            case .entityTypeEditor, .vaultImport, .vaultImportResult: return snapshotCanvasSize
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
            var importModel: VaultImportModel?
            if snapshotCase.subject == .vaultImport || snapshotCase.subject == .vaultImportResult {
                importModel = try await VaultImportModel(root: context.root)
            }
            if snapshotCase.subject == .vaultImportResult {
                // The real write, into the test's own copy of the fictional vault.
                await importModel?.apply()
                #expect(importModel?.result != nil)
            }
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
                    case .vaultImport, .vaultImportResult:
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
