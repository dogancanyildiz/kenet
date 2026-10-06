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
                    Text("Bu ad kullanılıyor. Farklı bir ad veya ayırt edici yazın.").foregroundStyle(.secondary)
                }
                if let error = model.errorText { Text(verbatim: error).foregroundStyle(.ink.danger) }
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
        } else {
            Text("Yeniden adlandırma tamamlandı. Güncellenen dosya: \(result.updatedFiles.count)")
        }
        ForEach(Array(result.failures.enumerated()), id: \.offset) { _, failure in
            VStack(alignment: .leading) {
                Text(verbatim: failure.path)
                switch failure.reason {
                case .rawField(let key): Text("Ham alan değiştirilmedi: \(key)")
                case .file(let reason):
                    Text("Dosya güncellenemedi.")
                    Text(verbatim: reason).font(.caption)
                case .frontmatterList(let key, let reason):
                    Text(verbatim: RenameFailureCopy.frontmatterList(key: key, reason: reason))
                case .partialChange(let reason):
                    Text("Özgün dosya geri yazılamadı.")
                    Text(verbatim: reason).font(.caption)
                case .index:
                    Text("Varlık kaydedildi, indeks güncellenemedi.")
                }
            }.foregroundStyle(.secondary)
        }
    }
}
