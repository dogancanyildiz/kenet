import Foundation
import SwiftUI
import Testing
import VaultFormat

@testable import Journal

/// Which kind each shell sheet is (read-only / editing-save / editing-create / cancel-only),
/// measured outside the pictures: a word in the bar is too small a part of a snapshot to fail
/// it. Each test reads the decision value the view really passes to `.inkSheet`, and a source
/// check ties the view to that value.
@MainActor struct ShellSheetKindTests {
    // MARK: - Read-only: "Kapat"

    @Test func settingsAndSearchAreReadOnlySheets() throws {
        let phone = try Self.read("App/Navigation/PhoneNavigation.swift")
        let settings = try Self.call(in: phone, startingAt: ".inkSheet(\n                        \"Ayarlar\"")
        #expect(settings.contains("closeIdentifier: \"button.settings.close\""))
        #expect(Self.kind(ofCall: settings) == .reading)

        let search = try Self.read("App/Screens/Shared/SearchView.swift")
        let searchCall = try Self.call(in: search, startingAt: ".inkSheet(\"Ara\"")
        #expect(searchCall.contains("closeIdentifier: \"button.search.close\""))
        #expect(Self.kind(ofCall: searchCall) == .reading)
        #expect(search.contains("inkSheetDismissAction"))

        let note = try Self.read("App/Screens/Shared/SearchNoteView.swift")
        let noteCall = try Self.call(in: note, startingAt: ".inkSheet(\n                verbatim:")
        #expect(noteCall.contains("closeIdentifier: \"button.search.note.close\""))
        #expect(Self.kind(ofCall: noteCall) == .reading)
        #expect(note.contains("#if os(macOS)"), "Kapat on the note is Mac-only so iPhone stays unchanged")

        let linked = try Self.read("App/Screens/Shared/LinkedTextView.swift")
        #expect(Self.kind(ofCall: try Self.call(in: linked, startingAt: ".inkSheet(verbatim:")) == .reading)
    }

    // MARK: - Editing: "Vazgeç" / "Kaydet" or "Oluştur"

    @Test func textEditorIsAnEditingSaveSheet() throws {
        let source = try Self.read("App/Screens/Shared/SingleLineTextEditor.swift")
        let call = try Self.call(in: source, startingAt: "InkSheetScaffold(")
        #expect(Self.kind(ofCall: call) == .editing)
        #expect(call.contains("confirm: .save"))
        #expect(!call.contains(".create"))
        // "Vazgeç" is drawn disabled while saving instead of being ignored.
        #expect(call.contains("isCancelEnabled: !isSaving"))
        #expect(!source.contains("if !isSaving { dismiss() }"))
        // Assist sits below the field so chips do not cover the typed line.
        let field = try #require(source.range(of: "InkFilterField("))
        let assist = try #require(source.range(of: "assist()"))
        #expect(field.lowerBound < assist.lowerBound)
    }

    @Test func eventTextEditorUsesSharedSingleLineSkeleton() throws {
        let source = try Self.read("App/Screens/Today/EventTextEditor.swift")
        #expect(source.contains("SingleLineTextEditor("))
        #expect(source.contains("MentionAssistStrip("))
        // The clear button is back, as in the sibling task editor.
        #expect(!source.contains("showsClearButton"))
        #expect(!source.contains("InkSheetScaffold("))
    }

    @Test func entityTypeEditorCreatesANewTypeAndSavesAnExistingOne() throws {
        #expect(EntityTypeEditorView.confirmation(isNew: true) == .create)
        #expect(EntityTypeEditorView.confirmation(isNew: false) == .save)
        let source = try Self.read("App/Screens/Settings/EntityTypeEditorView.swift")
        let call = try Self.call(in: source, startingAt: ".inkSheet(")
        #expect(Self.kind(ofCall: call) == .editing)
        #expect(call.contains("confirm: Self.confirmation(isNew: model.original == nil)"))
        #expect(call.contains("isCancelEnabled: !model.isSaving"))
    }

    // MARK: - Cancel-only: vault preparation

    @Test func vaultPreparationIsACancelOnlySheet() throws {
        let source = try Self.read("App/Screens/Onboarding/VaultImportView.swift")
        let call = try Self.call(in: source, startingAt: "page.inkSheet(")
        #expect(Self.kind(ofCall: call) == .cancelOnly)
        #expect(call.contains("showsCancel: VaultImportChrome.showsCancel("))
        #expect(call.contains("isCancelEnabled: !isWriting"))
        // One sheet call, so one kind: no "Kaydet", no "Kapat", in any state.
        #expect(source.components(separatedBy: ".inkSheet(").count - 1 == 1)
        // "Uygula" is the page's primary button and is not bound to Return.
        #expect(source.contains("Button(\"Uygula\") { Task { await model.apply() } }"))
        #expect(source.contains(".buttonStyle(InkPrimaryButtonStyle())"))
        #expect(!source.contains("keyboardShortcut"))
        #expect(!source.contains("onConfirm"))
    }

    @Test func vaultPreparationBarAndButtonsFollowTheWrite() {
        // "Vazgeç" until the result is in; then the bar is empty and "Kasayı aç" is the way out.
        #expect(VaultImportChrome.showsCancel(hasResult: false, openFailed: false))
        #expect(!VaultImportChrome.showsCancel(hasResult: true, openFailed: false))
        // Opening the prepared vault failed: "Vazgeç" returns and the sheet can be swiped away.
        #expect(VaultImportChrome.openFailed(hasResult: true, hasError: true))
        #expect(!VaultImportChrome.openFailed(hasResult: false, hasError: true))
        #expect(VaultImportChrome.showsCancel(hasResult: true, openFailed: true))
        #expect(!VaultImportChrome.blocksInteractiveDismiss(hasResult: true, isWriting: false, openFailed: true))
        #expect(VaultImportChrome.blocksInteractiveDismiss(hasResult: true, isWriting: false, openFailed: false))
        #expect(VaultImportChrome.blocksInteractiveDismiss(hasResult: true, isWriting: true, openFailed: true))
        #expect(InkSheetChrome.cancelOnlyButtons(showsCancel: true) == [.cancel])
        #expect(InkSheetChrome.cancelOnlyButtons(showsCancel: false).isEmpty)

        #expect(!VaultImportChrome.isWriting(isApplying: false, isProcessing: false))
        #expect(VaultImportChrome.isWriting(isApplying: true, isProcessing: false))
        #expect(VaultImportChrome.isWriting(isApplying: false, isProcessing: true))

        #expect(VaultImportChrome.canApply(canPrepare: true, isWriting: false))
        #expect(!VaultImportChrome.canApply(canPrepare: false, isWriting: false))
        #expect(!VaultImportChrome.canApply(canPrepare: true, isWriting: true))

        #expect(!VaultImportChrome.blocksInteractiveDismiss(hasResult: false, isWriting: false, openFailed: false))
        #expect(VaultImportChrome.blocksInteractiveDismiss(hasResult: true, isWriting: false, openFailed: false))
        #expect(VaultImportChrome.blocksInteractiveDismiss(hasResult: false, isWriting: true, openFailed: false))
    }

    @Test func vaultPreparationIsOneListAndShowsTheResultUnderTheHeadline() throws {
        let source = try Self.read("App/Screens/Onboarding/VaultImportView.swift")
        #expect(source.components(separatedBy: "List {").count - 1 == 1)
        #expect(source.contains("ScrollViewReader"))
        #expect(source.contains("proxy.scrollTo(Self.topAnchor, anchor: .top)"))
        // Order in the list: manşet, result, folder report.
        let title = try #require(source.range(of: "InkPageTitleRow(\"Kasa hazırlığı\")"))
        let result = try #require(source.range(of: "resultSection(result)"))
        let report = try #require(source.range(of: "\"Klasör raporu\""))
        #expect(title.lowerBound < result.lowerBound)
        #expect(result.lowerBound < report.lowerBound)
        // The write disables the page actions through the same decision as the bar.
        #expect(source.contains(".disabled(isWriting)"))
        #expect(source.contains("VaultImportChrome.canApply("))
        #expect(source.contains("VaultImportChrome.blocksInteractiveDismiss("))
    }

    // MARK: - Component additions

    @Test func disabledCancelIsDrawnDisabled() throws {
        #expect(InkSheetChrome.token(for: .cancel) == .secondaryText)
        #expect(InkSheetChrome.token(for: .cancel, isEnabled: false) == .control)
        #expect(InkSheetChrome.token(for: .confirm, isEnabled: false) == .secondaryText)
        let source = try Self.read("App/Design/Components/InkSheet.swift")
        // Both "Vazgeç" buttons (editing, cancel-only) honor the flag.
        #expect(source.contains(".disabled(!isCancelEnabled)"))
        let item = try Self.section(of: source, startingAt: "struct InkSheetCancelItem:")
        #expect(item.contains(".disabled(!isEnabled)"))
        #expect(item.contains("placement: .cancellationAction"))
        #expect(item.contains("InkSheetChrome.cancelKey"))
        #expect(item.contains("InkSheetButtonStyle(button: .cancel)"))
        #expect(item.contains(".inkSheetShortcut(.cancelAction)"))
        #expect(!item.contains(".defaultAction"), "nothing is bound to Return")
        #expect(item.contains(".sharedBackgroundVisibility(.hidden)"), "no glass capsule")
        let modifier = try Self.section(of: source, startingAt: "struct InkSheetModifier:")
        #expect(modifier.contains("InkSheetChrome.cancelOnlyButtons(showsCancel: showsCancel)"))
    }

    @Test func formFieldsHaveVisibleLabelsAndNoClearButton() throws {
        let field = try Self.read("App/Design/Components/InkFilterField.swift")
        #expect(field.contains("clearIdentifier: String? = nil, showsClearButton: Bool = true"))
        #expect(field.contains("showsClearButton && InkFilterFieldChrome.showsClear(text: text)"))

        let editor = try Self.read("App/Screens/Settings/EntityTypeEditorView.swift")
        #expect(editor.components(separatedBy: "InkFilterField(").count - 1 == 1, "one form field builder")
        #expect(editor.contains("showsClearButton: false"))
        #expect(editor.contains(".accessibilityLabel(Text(label))"))
        #expect(editor.contains(".accessibilityHidden(true)"))
        #expect(editor.components(separatedBy: "labeledField(").count - 1 == 9, "eight fields + the builder")
        #expect(editor.contains("InkDestructiveButtonStyle()"))
        #expect(!editor.contains(".buttonStyle(.borderless)\n    }"), "remove is not a system-red button")

        let types = try Self.read("App/Screens/Settings/EntityTypesSettingsView.swift")
        #expect(
            types.contains(
                "Button(\"Tipi sil\", role: .destructive) { deleting = type }\n"
                    + "                            .buttonStyle(InkDestructiveButtonStyle())"))

        let text = try Self.read("App/Screens/Shared/SingleLineTextEditor.swift")
        #expect(text.contains("Text(placeholder)"))
        #expect(text.contains(".accessibilityHidden(true)"))
        #expect(!text.contains("showsClearButton"))
    }

    @Test func geofenceTabsCarryTheGoalName() throws {
        let tabs = try Self.read("App/Design/Components/InkTabs.swift")
        #expect(tabs.contains("identifier: String? = nil,\n        accessibilityLabelPrefix: String? = nil"))
        #expect(tabs.contains(".modifier(InkTabLabelPrefix(prefix: accessibilityLabelPrefix))"))
        let prefix = try Self.section(of: tabs, startingAt: "struct InkTabLabelPrefix:")
        #expect(prefix.contains("content.accessibilityLabel { word in"))
        #expect(prefix.contains("Text(verbatim: prefix)"))
        let settings = try Self.read("App/Screens/Settings/GeofenceSettingsView.swift")
        #expect(settings.contains("accessibilityLabelPrefix: target.goal.name"))
    }

    // MARK: - Dirty draft

    @Test func entityTypeDraftIsDirtyOnlyAfterAChange() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = EntityTypeEditorModel(store: context.store)
        let opened = EntityTypeDraftSnapshot(model)
        #expect(!EntityTypeDraftSnapshot(model).isDirty(since: opened), "a fresh sheet closes without asking")

        model.nameTR = "Albüm"
        #expect(EntityTypeDraftSnapshot(model).isDirty(since: opened))
        model.nameTR = ""
        #expect(!EntityTypeDraftSnapshot(model).isDirty(since: opened), "typed and undone")

        model.fields.append(EntityTypeFieldDraft())
        #expect(EntityTypeDraftSnapshot(model).isDirty(since: opened), "an added empty field")
        model.fields.removeAll()
        #expect(!EntityTypeDraftSnapshot(model).isDirty(since: opened))

        for change: (EntityTypeEditorModel) -> Void in [
            { $0.id = "a" }, { $0.folder = "a" }, { $0.nameEN = "a" }, { $0.pluralTR = "a" },
            { $0.pluralEN = "a" }, { $0.icon = "book" }, { $0.template = "a" },
        ] {
            let fresh = EntityTypeEditorModel(store: context.store)
            let before = EntityTypeDraftSnapshot(fresh)
            change(fresh)
            #expect(EntityTypeDraftSnapshot(fresh).isDirty(since: before))
        }
    }

    @Test func entityTypeDraftSeesFieldNameAndKindChanges() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let definition = EntityTypeDefinition(
            id: "book", folder: "books", name: .init(tr: "Kitap", en: "Book"),
            plural: .init(tr: "Kitaplar", en: "Books"), icon: "book",
            fields: [EntityTypeField(key: "yazar", kind: .text)], template: nil)
        let model = EntityTypeEditorModel(store: context.store, original: definition)
        let opened = EntityTypeDraftSnapshot(model)
        #expect(!EntityTypeDraftSnapshot(model).isDirty(since: opened), "an existing type opens clean")
        model.fields[0].kind = .date
        #expect(EntityTypeDraftSnapshot(model).isDirty(since: opened))
        model.fields[0].kind = .text
        model.fields[0].key = "yazarlar"
        #expect(EntityTypeDraftSnapshot(model).isDirty(since: opened))
        // A removed and re-added field with the same content is the same draft.
        model.fields = [EntityTypeFieldDraft(key: "yazar", kind: .text)]
        #expect(!EntityTypeDraftSnapshot(model).isDirty(since: opened))
    }

    @Test func entityTypeEditorAsksBeforeDiscardingADirtyDraft() throws {
        let source = try Self.read("App/Screens/Settings/EntityTypeEditorView.swift")
        #expect(source.contains("EntityTypeDraftSnapshot(model).isDirty(since: opened)"))
        #expect(source.contains("onCancel: { if isDirty { discardPrompt = true } else { dismiss() } }"))
        #expect(source.contains(".interactiveDismissDisabled(model.isSaving || isDirty)"))
        #expect(source.contains("Button(\"Değişiklikleri at\", role: .destructive) { dismiss() }"))
        #expect(source.contains("Button(\"Düzenlemeye devam et\", role: .cancel) {}"))
        let catalog = try Self.read("App/Resources/Localizable.xcstrings")
        let data = try #require(catalog.data(using: .utf8))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: Any])
        for key in ["Değişiklikleri at", "Düzenlemeye devam et", "Tip kimliği", "Klasör", "ör. %@"] {
            #expect(strings[key] != nil, "\(key) missing from the String Catalog")
        }
    }

    // MARK: - Support

    enum Kind: Equatable { case reading, editing, cancelOnly }

    /// The kind of an `.inkSheet(` / `InkSheetScaffold(` call, from the argument labels that
    /// select the overload: `onConfirm:` is editing, `closeIdentifier:` / `onClose:` is
    /// read-only, `cancelIdentifier:` without `onConfirm:` is cancel-only.
    private static func kind(ofCall call: String) -> Kind? {
        if call.contains("onConfirm:") { return .editing }
        if call.contains("closeIdentifier:") || call.contains("onClose:") { return .reading }
        if call.contains("cancelIdentifier:") { return .cancelOnly }
        return nil
    }

    /// Text of one call: from `marker` to its balancing closing parenthesis.
    private static func call(in source: String, startingAt marker: String) throws -> String {
        let start = try #require(source.range(of: marker), "\(marker) not found")
        let open = try #require(source[start.lowerBound...].firstIndex(of: "("))
        var depth = 0
        var index = open
        while index < source.endIndex {
            if source[index] == "(" { depth += 1 }
            if source[index] == ")" {
                depth -= 1
                if depth == 0 { return String(source[start.lowerBound...index]) }
            }
            index = source.index(after: index)
        }
        return String(source[start.lowerBound...])
    }

    private static func section(
        of source: String, startingAt marker: String, until terminator: String = "\n}\n"
    ) throws -> String {
        let start = try #require(source.range(of: marker), "\(marker) not found")
        let rest = source[start.lowerBound...]
        let end = rest.range(of: terminator)?.upperBound ?? rest.endIndex
        return String(rest[..<end])
    }

    private static func read(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
