import SwiftUI
import VaultFormat

struct EntityTypeEditorView: View {
    @State var model: EntityTypeEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var deleteConfirmation = DestructiveConfirmation<UUID>()

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Tip tanımı") {
                TextField("Tip kimliği (ör. book)", text: $model.id).disabled(model.original != nil)
                TextField("Klasör (ör. books)", text: $model.folder)
                TextField("Ad — Türkçe", text: $model.nameTR)
                TextField("Ad — İngilizce", text: $model.nameEN)
                TextField("Çoğul ad — Türkçe", text: $model.pluralTR)
                TextField("Çoğul ad — İngilizce", text: $model.pluralEN)
                TextField("SF Symbol adı", text: $model.icon)
                TextField("Şablon yolu (isteğe bağlı)", text: $model.template)
                Text("Kimlik değişmez. Klasör değişikliği mevcut varlıkları taşımaz.").font(.caption)
            }
            Section("Alanlar") {
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
                }
                Button("Alan ekle") { model.fields.append(EntityTypeFieldDraft()) }
            }
            if let error = model.errorText {
                Text(verbatim: error)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.danger)
            }
            Button("Kaydet") { Task { if await model.save() { dismiss() } } }.disabled(!model.canSave)
            Text("Kimlik küçük ASCII harfle başlamalı; alan adları benzersiz olmalıdır. Tüm adları doldur.")
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
        }
        .disabled(model.isSaving)
        .formStyle(.grouped)
        .navigationTitle(model.original == nil ? Text("Yeni varlık tipi") : Text("Varlık tipini düzenle"))
        .inkPage()
        .inkPageColumn()
        .destructiveConfirmationDialog(
            "Alanı kaldır?", confirmation: $deleteConfirmation, confirmTitle: "Alanı kaldır"
        ) { fieldID in
            model.fields.removeAll { $0.id == fieldID }
        }
    }
}
