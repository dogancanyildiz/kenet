import SwiftUI
import VaultStore

struct EntityRenameView: View {
    @State var model: EntityRenameModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Ad", text: $model.name)
                TextField("Ayırt edici", text: $model.qualifier)
                if model.needsQualifier {
                    Text("Bu ad kullanılıyor. Farklı bir ad veya ayırt edici yazın.")
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                }
                if let error = model.errorText {
                    Text(verbatim: error).font(.ink.meta).foregroundStyle(.ink.danger)
                }
            }
            .disabled(model.isRenaming)
            .navigationTitle("Adı değiştir")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }.disabled(model.isRenaming)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        Task {
                            await model.save()
                            if model.result != nil { dismiss() }
                        }
                    }.disabled(
                        model.isRenaming || !model.detail.canEdit
                            || model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct EntityRenameSummary: View {
    let result: RenameResult
    var body: some View {
        if result.hasPartialChange {
            Text("Ad değiştirme tamamlanamadı; dosyada kısmi değişiklik kaldı.")
                .font(.ink.meta)
                .foregroundStyle(.ink.secondaryText)
        } else {
            Text("Yeniden adlandırma tamamlandı. Güncellenen dosya: \(result.updatedFiles.count)")
                .font(.ink.meta)
                .foregroundStyle(.ink.secondaryText)
        }
        ForEach(Array(result.failures.enumerated()), id: \.offset) { _, failure in
            VStack(alignment: .leading) {
                Text(verbatim: failure.path)
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                switch failure.reason {
                case .rawField(let key):
                    Text("Ham alan değiştirilmedi: \(key)")
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                case .file(let reason):
                    Text("Dosya güncellenemedi.")
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                    Text(verbatim: reason)
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                case .frontmatterList(let key, let reason):
                    Text(verbatim: RenameFailureCopy.frontmatterList(key: key, reason: reason))
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                case .partialChange(let reason):
                    Text("Özgün dosya geri yazılamadı.")
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                    Text(verbatim: reason)
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                case .index:
                    Text("Varlık kaydedildi, indeks güncellenemedi.")
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                }
            }
        }
    }
}
