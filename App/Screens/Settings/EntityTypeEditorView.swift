import SwiftUI
import VaultFormat

struct EntityTypeEditorView: View {
    @State var model: EntityTypeEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var deleteConfirmation = DestructiveConfirmation<UUID>()

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                SectionHeader("Tip tanımı")
                    .inkListRow()
                TextField("Tip kimliği (ör. book)", text: $model.id).disabled(model.original != nil)
                    .inkListRow()
                TextField("Klasör (ör. books)", text: $model.folder)
                    .inkListRow()
                TextField("Ad — Türkçe", text: $model.nameTR)
                    .inkListRow()
                TextField("Ad — İngilizce", text: $model.nameEN)
                    .inkListRow()
                TextField("Çoğul ad — Türkçe", text: $model.pluralTR)
                    .inkListRow()
                TextField("Çoğul ad — İngilizce", text: $model.pluralEN)
                    .inkListRow()
                TextField("SF Symbol adı", text: $model.icon)
                    .inkListRow()
                TextField("Şablon yolu (isteğe bağlı)", text: $model.template)
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
                    HStack {
                        TextField("Alan adı", text: $field.key)
                        Picker("Alan türü", selection: $field.kind) {
                            Text("Metin").tag(EntityTypeField.Kind.text)
                            Text("Tarih").tag(EntityTypeField.Kind.date)
                            Text("Sayı").tag(EntityTypeField.Kind.number)
                            Text("Evet/hayır").tag(EntityTypeField.Kind.boolean)
                            Text("Bağlantı").tag(EntityTypeField.Kind.link)
                        }
                        Button("Alanı kaldır", role: .destructive) { deleteConfirmation.request(field.id) }
                    }
                    .inkListRow()
                }
                Button("Alan ekle") { model.fields.append(EntityTypeFieldDraft()) }
                    .inkListRow()
            }
            if let error = model.errorText {
                Text(verbatim: error)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.danger)
                    .inkListRow()
            }
            Button("Kaydet") { Task { if await model.save() { dismiss() } } }.disabled(!model.canSave)
                .inkListRow()
            Text("Kimlik küçük ASCII harfle başlamalı; alan adları benzersiz olmalıdır. Tüm adları doldur.")
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .inkListRow()
        }
        .disabled(model.isSaving)
        .listStyle(.plain)
        .navigationTitle(model.original == nil ? Text("Yeni varlık tipi") : Text("Varlık tipini düzenle"))
        .inkPageColumn()
        .inkPage()
        .destructiveConfirmationDialog(
            "Alanı kaldır?", confirmation: $deleteConfirmation, confirmTitle: "Alanı kaldır"
        ) { fieldID in
            model.fields.removeAll { $0.id == fieldID }
        }
    }
}
