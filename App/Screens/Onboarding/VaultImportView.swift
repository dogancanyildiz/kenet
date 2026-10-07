import SwiftUI

struct VaultImportView: View {
    let store: IndexStore
    @Bindable var model: VaultImportModel
    var body: some View {
        Form {
            Section {
                SectionHeader(title: String(localized: "Klasör raporu"))
                Text(verbatim: model.report.root.path)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.text)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                labeled("Markdown dosyaları", model.report.markdownCount)
                labeled("Gün dosyaları", model.report.journalDays.count)
                labeled("Diğer yollardaki gün dosyaları", model.report.externalDays.count)
                labeled("Kişiler", model.report.typed["person", default: 0])
                labeled("Konumlar", model.report.typed["place", default: 0])
                labeled("Hedefler", model.report.typed["goal", default: 0])
                DisclosureGroup("Bulunan klasörler") {
                    ForEach(model.report.foundFolders, id: \.self) { path in
                        Text(verbatim: path)
                            .font(.ink.meta)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                if !model.report.caseVariantFolders.isEmpty {
                    DisclosureGroup("Harf farkı olan klasörler") {
                        ForEach(model.report.caseVariantFolders, id: \.self) { Text(verbatim: $0 + "/") }
                    }
                    Text(
                        "Bu klasör adları tam olarak journal, people, places, goals, notes veya templates olmalı. Obsidian'da yeniden adlandır; aksi halde o klasöre yazma reddedilir."
                    )
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                }
                if !model.report.externalDays.isEmpty {
                    DisclosureGroup("Taşınmayacak günlükler") {
                        ForEach(model.report.externalDays, id: \.self) { path in
                            Text(verbatim: path)
                                .font(.ink.meta)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                    Text(
                        "Bu günlükler taşınmaz. Gün görünümünde kullanmak için Obsidian'da journal klasörüne düzenleyebilirsin."
                    )
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                }
                DisclosureGroup("Türü olmayan dosyalar") {
                    ForEach(model.report.candidates, id: \.path) { candidate in
                        Text(verbatim: candidate.path)
                            .font(.ink.meta)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                if !model.report.skipped.isEmpty {
                    DisclosureGroup("Atlanacak dosyalar") {
                        ForEach(model.report.skipped, id: \.self) { path in
                            Text(verbatim: path)
                                .font(.ink.meta)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            if let result = model.result {
                Section {
                    SectionHeader(title: String(localized: "Hazırlama sonucu"))
                    labeled("Oluşturulan öğeler", result.created.count)
                    labeled("Tür eklenen dosyalar", result.typed.count)
                    DisclosureGroup("Atlananlar") {
                        ForEach(result.skipped, id: \.self) { path in
                            Text(verbatim: path)
                                .font(.ink.meta)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                    DisclosureGroup("Tamamlanamayanlar") {
                        ForEach(result.failures, id: \.self) { path in
                            Text(verbatim: path)
                                .font(.ink.meta)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                    Button("Kasayı aç") { Task { await store.finishImport(model) } }
                        .buttonStyle(InkPrimaryButtonStyle())
                        .disabled(store.isProcessing)
                }
            } else {
                Section {
                    SectionHeader(title: String(localized: "Hazırlama seçenekleri"))
                    DisclosureGroup("Eksik klasörler ve şablonlar") {
                        ForEach(
                            model.report.missingFolders.map { $0 + "/" } + model.report.missingTemplates, id: \.self
                        ) { Text(verbatim: $0) }
                    }
                    Toggle("Eksik klasörleri ve şablonları oluştur", isOn: $model.options.folders)
                    Toggle("Eksik kasa ayarını oluştur", isOn: $model.options.settings)
                    Toggle("Kişi ve konum dosyalarına tür ekle", isOn: $model.options.types)
                    Text("Mevcut dosyalar taşınmaz; Obsidian ayarları korunur.")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                    if !model.report.canPrepare {
                        Text("Kasa sürümü okunamıyor veya desteklenmiyor. Hazırlama yapılamaz.")
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                    }
                    Button("Uygula") { Task { await model.apply() } }
                        .buttonStyle(InkPrimaryButtonStyle())
                        .disabled(!model.report.canPrepare)
                    Button("Atla") { Task { await store.finishImport(model) } }
                        .buttonStyle(InkTextButtonStyle())
                }.disabled(model.isApplying || store.isProcessing)
            }
            if model.isApplying {
                InkProgress(kind: .indeterminate(label: "Kasa hazırlanıyor…"))
            }
            if store.isProcessing { VaultIndexingProgress(store: store) }
            if let error = store.errorText {
                Text(verbatim: error)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.danger)
            }
        }
        .navigationTitle("Kasa hazırlığı")
        .formStyle(.grouped)
        .listRowBackground(Color.ink.paper)
        .inkPageColumn()
        .inkPage()
        .interactiveDismissDisabled(model.isApplying || model.result != nil || store.isProcessing)
    }

    private func labeled(_ title: LocalizedStringKey, _ value: Int) -> some View {
        LabeledContent(title) {
            Text(value, format: .number)
                .font(.ink.value)
                .monospacedDigit()
        }
    }
}
