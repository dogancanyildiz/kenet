import SwiftUI

struct VaultImportView: View {
    let store: IndexStore
    @Bindable var model: VaultImportModel
    var body: some View {
        List {
            Section {
                SectionHeader(title: String(localized: "Klasör raporu"))
                    .inkListRow()
                Text(verbatim: model.report.root.path)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.text)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .inkListRow()
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
                .inkListRow()
                if !model.report.caseVariantFolders.isEmpty {
                    DisclosureGroup("Harf farkı olan klasörler") {
                        ForEach(model.report.caseVariantFolders, id: \.self) { Text(verbatim: $0 + "/") }
                    }
                    .inkListRow()
                    Text(
                        "Bu klasör adları tam olarak journal, people, places, goals, notes veya templates olmalı. Obsidian'da yeniden adlandır; aksi halde o klasöre yazma reddedilir."
                    )
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
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
                    .inkListRow()
                    Text(
                        "Bu günlükler taşınmaz. Gün görünümünde kullanmak için Obsidian'da journal klasörüne düzenleyebilirsin."
                    )
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
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
                .inkListRow()
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
                    .inkListRow()
                }
            }
            if let result = model.result {
                Section {
                    SectionHeader(title: String(localized: "Hazırlama sonucu"))
                        .inkListRow()
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
                    .inkListRow()
                    DisclosureGroup("Tamamlanamayanlar") {
                        ForEach(result.failures, id: \.self) { path in
                            Text(verbatim: path)
                                .font(.ink.meta)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                    .inkListRow()
                    Button("Kasayı aç") { Task { await store.finishImport(model) } }
                        .buttonStyle(InkPrimaryButtonStyle())
                        .disabled(store.isProcessing)
                        .inkListRow()
                }
            } else {
                Section {
                    SectionHeader(title: String(localized: "Hazırlama seçenekleri"))
                        .inkListRow()
                    DisclosureGroup("Eksik klasörler ve şablonlar") {
                        ForEach(
                            model.report.missingFolders.map { $0 + "/" } + model.report.missingTemplates, id: \.self
                        ) { Text(verbatim: $0) }
                    }
                    .inkListRow()
                    Toggle("Eksik klasörleri ve şablonları oluştur", isOn: $model.options.folders)
                        .inkListRow()
                    Toggle("Eksik kasa ayarını oluştur", isOn: $model.options.settings)
                        .inkListRow()
                    Toggle("Kişi ve konum dosyalarına tür ekle", isOn: $model.options.types)
                        .inkListRow()
                    Text("Mevcut dosyalar taşınmaz; Obsidian ayarları korunur.")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        .inkListRow()
                    if !model.report.canPrepare {
                        Text("Kasa sürümü okunamıyor veya desteklenmiyor. Hazırlama yapılamaz.")
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                            .inkListRow()
                    }
                    Button("Uygula") { Task { await model.apply() } }
                        .buttonStyle(InkPrimaryButtonStyle())
                        .disabled(!model.report.canPrepare)
                        .inkListRow()
                    Button("Atla") { Task { await store.finishImport(model) } }
                        .buttonStyle(InkTextButtonStyle())
                        .inkListRow()
                }.disabled(model.isApplying || store.isProcessing)
            }
            if model.isApplying {
                InkProgress(kind: .indeterminate(label: "Kasa hazırlanıyor…"))
                    .inkListRow()
            }
            if store.isProcessing {
                VaultIndexingProgress(store: store)
                    .inkListRow()
            }
            if let error = store.errorText {
                Text(verbatim: error)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.danger)
                    .inkListRow()
            }
        }
        .navigationTitle("Kasa hazırlığı")
        .listStyle(.plain)
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
        .inkListRow()
    }
}
