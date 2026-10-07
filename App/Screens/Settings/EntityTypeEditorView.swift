import SwiftUI
import VaultFormat

/// Editing sheet for one entity type: every field is collected in the model and written by the
/// single confirm ("Oluştur" for a new type, "Kaydet" for an existing one). Hosted inside the
/// presenter's `NavigationStack`.
struct EntityTypeEditorView: View {
    @State var model: EntityTypeEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var deleteConfirmation = DestructiveConfirmation<UUID>()

    private var title: LocalizedStringKey {
        model.original == nil ? "Yeni varlık tipi" : "Varlık tipini düzenle"
    }

    var body: some View {
        @Bindable var model = model
        List {
            InkPageTitleRow(title)
            Section {
                SectionHeader("Tip tanımı")
                    .inkListRow()
                InkFilterField("Tip kimliği (ör. book)", text: $model.id).disabled(model.original != nil)
                    .inkListRow()
                InkFilterField("Klasör (ör. books)", text: $model.folder)
                    .inkListRow()
                InkFilterField("Ad — Türkçe", text: $model.nameTR)
                    .inkListRow()
                InkFilterField("Ad — İngilizce", text: $model.nameEN)
                    .inkListRow()
                InkFilterField("Çoğul ad — Türkçe", text: $model.pluralTR)
                    .inkListRow()
                InkFilterField("Çoğul ad — İngilizce", text: $model.pluralEN)
                    .inkListRow()
                InkFilterField("SF Symbol adı", text: $model.icon)
                    .inkListRow()
                InkFilterField("Şablon yolu (isteğe bağlı)", text: $model.template)
                    .inkListRow()
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
                        InkFilterField("Alan adı", text: $field.key)
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
        .inkPageColumn()
        .inkSheet(
            title, confirm: model.original == nil ? .create : .save,
            isConfirmEnabled: model.canSave, isBusy: model.isSaving,
            cancelIdentifier: "button.entityType.cancel", confirmIdentifier: "button.entityType.save",
            onCancel: { if !model.isSaving { dismiss() } },
            onConfirm: { Task { if await model.save() { dismiss() } } }
        )
        .interactiveDismissDisabled(model.isSaving)
        .destructiveConfirmationDialog(
            "Alanı kaldır?", confirmation: $deleteConfirmation, confirmTitle: "Alanı kaldır"
        ) { fieldID in
            model.fields.removeAll { $0.id == fieldID }
        }
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
        Button(role: .destructive) {
            deleteConfirmation.request(id)
        } label: {
            Text("Alanı kaldır").tapTarget()
        }
        .buttonStyle(.borderless)
    }
}
