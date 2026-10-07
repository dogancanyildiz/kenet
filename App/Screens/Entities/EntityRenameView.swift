import SwiftUI
import VaultStore

struct EntityRenameView: View {
    @State var model: EntityRenameModel
    @Environment(\.dismiss) private var dismiss

    private var canSave: Bool {
        model.detail.canEdit && !model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                InkPageTitleRow("Adı değiştir")
                InkFilterField("Ad", text: $model.name, identifier: "field.entity.rename.name")
                    .inkListRow()
                InkFilterField("Ayırt edici", text: $model.qualifier, identifier: "field.entity.rename.qualifier")
                    .inkListRow()
                if model.needsQualifier {
                    Text("Bu ad kullanılıyor. Farklı bir ad veya ayırt edici yazın.")
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                        .inkListRow()
                }
                if let error = model.errorText {
                    Text(verbatim: error).font(.ink.meta).foregroundStyle(.ink.danger)
                        .inkListRow()
                }
            }
            .listStyle(.plain)
            .disabled(model.isRenaming)
            .inkSheet(
                "Adı değiştir", isConfirmEnabled: canSave, isBusy: model.isRenaming,
                // "Vazgeç" stays inert while the rename is being written.
                onCancel: { if !model.isRenaming { dismiss() } },
                onConfirm: {
                    Task {
                        await model.save()
                        if model.result != nil { dismiss() }
                    }
                })
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
