import SwiftUI

/// Index counts, skipped paths, rebuild, and search-history clear.
struct DiagnosticsView: View {
    @Bindable var store: IndexStore

    var body: some View {
        Form {
            InkPageTitleRow("Tanılama")
            Section("İndeks") {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        rebuildButton
                        clearHistoryButton
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        rebuildButton
                        clearHistoryButton
                    }
                }
                .buttonStyle(.borderless)
                if store.isProcessing { VaultIndexingProgress(store: store) }
                if let notice = store.notice {
                    InfoBand(kind: .info, verbatim: notice)
                }
                if let error = store.errorText {
                    InfoBand(kind: .error, verbatim: error)
                }
                count("Dosyalar", store.counts.files)
                count("Günler", store.counts.filesByKind["day", default: 0])
                count("Kişiler", store.counts.filesByKind["person", default: 0])
                count("Konumlar", store.counts.filesByKind["place", default: 0])
                count("Hedefler", store.counts.filesByKind["goal", default: 0])
                count("Notlar", store.counts.filesByKind["note", default: 0])
                count("Olaylar", store.counts.events)
                count("Görevler", store.counts.tasks)
                count("Varlıklar", store.counts.entities)
                count("Bağlantılar", store.counts.links)
                count("Çözülmemiş bağlantılar", store.counts.unresolvedLinks)
                if let date = store.lastUpdated {
                    LabeledContent("Son güncelleme") {
                        Text(date, format: .dateTime)
                            .font(.ink.value)
                    }
                }
            }
            Section("Atlanan yollar") {
                if store.skippedPaths.isEmpty {
                    Text("Atlanan yol yok.")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                }
                ForEach(store.skippedPaths, id: \.path) { skipped in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: skipped.path)
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.text)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        if skipped.reason == .symbolicLink {
                            Text("Sembolik bağlantı")
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.secondaryText)
                        } else {
                            Text("Yinelenen normalleştirilmiş yol")
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.secondaryText)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .listRowBackground(Color.ink.paper)
        .inkPageNavigationTitle("Tanılama")
        .inkPageColumn()
        .inkPage()
    }

    private var rebuildButton: some View {
        Button("Yeniden üret") { Task { await store.refresh(rebuild: true) } }
            .disabled(store.isProcessing)
    }

    private var clearHistoryButton: some View {
        Button("Arama geçmişini temizle") {
            SearchModel.clearStoredHistory(for: store.vaultURL)
        }
        .disabled(store.vaultURL == nil)
    }

    private func count(_ label: LocalizedStringKey, _ value: Int) -> some View {
        LabeledContent(label) {
            Text(value, format: .number)
                .font(.ink.value)
                .monospacedDigit()
        }
    }
}
