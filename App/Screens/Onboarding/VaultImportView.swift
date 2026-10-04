import SwiftUI

struct VaultImportView: View {
    let store: IndexStore
    @Bindable var model: VaultImportModel
    var body: some View {
        Form {
            Section("Klasör raporu") {
                Text(verbatim: model.report.root.path).font(.caption)
                LabeledContent("Markdown dosyaları") { Text(model.report.markdownCount.formatted()) }
                LabeledContent("Gün dosyaları") { Text(model.report.journalDays.count.formatted()) }
                LabeledContent("Diğer yollardaki gün dosyaları") { Text(model.report.externalDays.count.formatted()) }
                LabeledContent("Kişiler") { Text(model.report.typed["person", default: 0].formatted()) }
                LabeledContent("Konumlar") { Text(model.report.typed["place", default: 0].formatted()) }
                LabeledContent("Hedefler") { Text(model.report.typed["goal", default: 0].formatted()) }
                DisclosureGroup("Bulunan klasörler") {
                    ForEach(model.report.foundFolders, id: \.self) { Text(verbatim: $0) }
                }
                if !model.report.externalDays.isEmpty {
                    DisclosureGroup("Taşınmayacak günlükler") {
                        ForEach(model.report.externalDays, id: \.self) { Text(verbatim: $0) }
                    }
                    Text(
                        "Bu günlükler taşınmaz. Gün görünümünde kullanmak için Obsidian'da journal klasörüne düzenleyebilirsin."
                    ).font(.caption)
                }
                DisclosureGroup("Türü olmayan dosyalar") {
                    ForEach(model.report.candidates, id: \.path) { Text(verbatim: $0.path) }
                }
                if !model.report.skipped.isEmpty {
                    DisclosureGroup("Atlanacak dosyalar") {
                        ForEach(model.report.skipped, id: \.self) { Text(verbatim: $0) }
                    }
                }
            }
            if let result = model.result {
                Section("Hazırlama sonucu") {
                    LabeledContent("Oluşturulan öğeler") { Text(result.created.count.formatted()) }
                    LabeledContent("Tür eklenen dosyalar") { Text(result.typed.count.formatted()) }
                    DisclosureGroup("Atlananlar") { ForEach(result.skipped, id: \.self) { Text(verbatim: $0) } }
                    DisclosureGroup("Tamamlanamayanlar") { ForEach(result.failures, id: \.self) { Text(verbatim: $0) } }
                    Button("Kasayı aç") { Task { await store.finishImport(model) } }.disabled(store.isProcessing)
                }
            } else {
                Section("Hazırlama seçenekleri") {
                    DisclosureGroup("Eksik klasörler ve şablonlar") {
                        ForEach(
                            model.report.missingFolders.map { $0 + "/" } + model.report.missingTemplates, id: \.self
                        ) { Text(verbatim: $0) }
                    }
                    Toggle("Eksik klasörleri ve şablonları oluştur", isOn: $model.options.folders)
                    Toggle("Eksik kasa ayarını oluştur", isOn: $model.options.settings)
                    Toggle("Kişi ve konum dosyalarına tür ekle", isOn: $model.options.types)
                    Text("Mevcut dosyalar taşınmaz; Obsidian ayarları korunur.").font(.caption)
                    if !model.report.canPrepare {
                        Text("Kasa sürümü okunamıyor veya desteklenmiyor. Hazırlama yapılamaz.").foregroundStyle(
                            .secondary)
                    }
                    Button("Uygula") { Task { await model.apply() } }.disabled(!model.report.canPrepare)
                    Button("Atla") { Task { await store.finishImport(model) } }
                }.disabled(model.isApplying || store.isProcessing)
            }
            if model.isApplying { ProgressView("Kasa hazırlanıyor…") }
            if store.isProcessing { VaultIndexingProgress(store: store) }
            if let error = store.errorText { Text(verbatim: error).foregroundStyle(.red) }
        }
        .navigationTitle("Kasa hazırlığı").formStyle(.grouped)
        .interactiveDismissDisabled(model.isApplying || model.result != nil || store.isProcessing)
    }
}
