import SwiftUI
import VaultFormat

/// Everything the editor can change, as a value: the draft is dirty when it differs from the
/// one the sheet opened with.
struct EntityTypeDraftSnapshot: Equatable {
    struct Field: Equatable {
        var key: String
        var kind: EntityTypeField.Kind
    }

    var id: String
    var folder: String
    var nameTR: String
    var nameEN: String
    var pluralTR: String
    var pluralEN: String
    var icon: String
    var template: String
    var fields: [Field]

    @MainActor init(_ model: EntityTypeEditorModel) {
        id = model.id
        folder = model.folder
        nameTR = model.nameTR
        nameEN = model.nameEN
        pluralTR = model.pluralTR
        pluralEN = model.pluralEN
        icon = model.icon
        template = model.template
        fields = model.fields.map { Field(key: $0.key, kind: $0.kind) }
    }

    /// Dirty: any text, the field list, a field's name or kind differs from `opened`.
    func isDirty(since opened: EntityTypeDraftSnapshot) -> Bool { self != opened }
}

/// Editing sheet for one entity type: every field is collected in the model and written by the
/// single confirm ("Oluştur" for a new type, "Kaydet" for an existing one). Hosted inside the
/// presenter's `NavigationStack`. A changed draft cannot be swiped away, and "Vazgeç" asks
/// before discarding it.
struct EntityTypeEditorView: View {
    @State private var model: EntityTypeEditorModel
    @State private var opened: EntityTypeDraftSnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var deleteConfirmation = DestructiveConfirmation<UUID>()
    @State private var discardPrompt = false

    init(model: EntityTypeEditorModel) {
        _model = State(initialValue: model)
        _opened = State(initialValue: EntityTypeDraftSnapshot(model))
    }

    private var title: LocalizedStringKey {
        model.original == nil ? "Yeni varlık tipi" : "Varlık tipini düzenle"
    }

    /// "Oluştur" opens a new type, "Kaydet" changes an existing one.
    static func confirmation(isNew: Bool) -> InkSheetConfirmation { isNew ? .create : .save }

    private var isDirty: Bool { EntityTypeDraftSnapshot(model).isDirty(since: opened) }

    var body: some View {
        @Bindable var model = model
        List {
            InkPageTitleRow(title)
            Section {
                SectionHeader("Tip tanımı")
                    .inkListRow()
                labeledField("Tip kimliği", example: "book", text: $model.id)
                    .disabled(model.original != nil)
                labeledField("Klasör", example: "books", text: $model.folder)
                labeledField("Ad — Türkçe", example: "Kitap", text: $model.nameTR)
                labeledField("Ad — İngilizce", example: "Book", text: $model.nameEN)
                labeledField("Çoğul ad — Türkçe", example: "Kitaplar", text: $model.pluralTR)
                labeledField("Çoğul ad — İngilizce", example: "Books", text: $model.pluralEN)
                labeledField("SF Symbol adı", example: "book", text: $model.icon)
                labeledField(
                    "Şablon yolu (isteğe bağlı)", example: "templates/book.md", text: $model.template)
                Text("Kimlik değişmez. Klasör değişikliği mevcut varlıkları taşımaz.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
            }
            Section {
                SectionHeader("Alanlar")
                    .inkListRow()
                ForEach($model.fields) { $field in
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Alan adı")
                        formField("Alan adı", example: "yazar", text: $field.key)
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                fieldKindMenu($field.kind)
                                Spacer(minLength: 0)
                                removeFieldButton(field.id)
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                fieldKindMenu($field.kind)
                                removeFieldButton(field.id)
                            }
                        }
                    }
                    .inkListRow()
                }
                Button("Alan ekle") { model.fields.append(EntityTypeFieldDraft()) }
                    .buttonStyle(.borderless)
                    .inkListRow()
            }
            if let error = model.errorText {
                Text(verbatim: error)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.danger)
                    .inkListRow()
            }
            Text("Kimlik küçük ASCII harfle başlamalı; alan adları benzersiz olmalıdır. Tüm adları doldur.")
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .inkListRow()
        }
        .disabled(model.isSaving)
        .listStyle(.plain)
        .inkPageScrollColumn()
        .inkSheet(
            title, confirm: Self.confirmation(isNew: model.original == nil),
            isConfirmEnabled: model.canSave, isBusy: model.isSaving, isCancelEnabled: !model.isSaving,
            cancelIdentifier: "button.entityType.cancel", confirmIdentifier: "button.entityType.save",
            onCancel: { if isDirty { discardPrompt = true } else { dismiss() } },
            onConfirm: { Task { if await model.save() { dismiss() } } }
        )
        .interactiveDismissDisabled(model.isSaving || isDirty)
        .destructiveConfirmationDialog(
            "Alanı kaldır?", confirmation: $deleteConfirmation, confirmTitle: "Alanı kaldır"
        ) { fieldID in
            model.fields.removeAll { $0.id == fieldID }
        }
        .confirmationDialog("Kaydedilmemiş değişiklikler", isPresented: $discardPrompt) {
            Button("Değişiklikleri at", role: .destructive) { dismiss() }
            Button("Düzenlemeye devam et", role: .cancel) {}
        }
    }

    /// A form field: visible label above, an example value as the placeholder, no clear button.
    private func labeledField(
        _ label: LocalizedStringKey, example: String, text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel(label)
            formField(label, example: example, text: text)
        }
        .inkListRow()
    }

    /// The visible label; VoiceOver reads it as the field's own label instead.
    private func fieldLabel(_ label: LocalizedStringKey) -> some View {
        Text(label)
            .font(.ink.meta)
            .foregroundStyle(Color.ink.secondaryText)
            .accessibilityHidden(true)
    }

    private func formField(
        _ label: LocalizedStringKey, example: String, text: Binding<String>
    ) -> some View {
        InkFilterField("ör. \(example)", text: text, showsClearButton: false)
            .accessibilityLabel(Text(label))
    }

    private func fieldKindMenu(_ kind: Binding<EntityTypeField.Kind>) -> some View {
        InkLabeledMenu(
            "Alan türü", selection: kind,
            options: [
                InkMenuOption("Metin", value: EntityTypeField.Kind.text),
                InkMenuOption("Tarih", value: EntityTypeField.Kind.date),
                InkMenuOption("Sayı", value: EntityTypeField.Kind.number),
                InkMenuOption("Evet/hayır", value: EntityTypeField.Kind.boolean),
                InkMenuOption("Bağlantı", value: EntityTypeField.Kind.link),
            ], expands: false)
    }

    private func removeFieldButton(_ id: UUID) -> some View {
        Button("Alanı kaldır", role: .destructive) { deleteConfirmation.request(id) }
            .buttonStyle(InkDestructiveButtonStyle())
    }
}
