import SwiftUI
import VaultIndex

/// Index counts, skipped paths, rebuild, search-history clear, and third-party licenses.
struct DiagnosticsView: View {
    @Bindable var store: IndexStore
    #if os(macOS)
        /// The Settings tab swaps its content; a push would shift the tab strip's highlight.
        var openLicenses: () -> Void = {}
    #endif
    /// Sync copies left in the vault; reloaded with each index publish.
    @State private var copies: [CopyFile] = []

    var body: some View {
        List {
            #if os(iOS)
                InkPageTitleRow("Tanılama")
            #endif
            Section {
                SectionHeader("İndeks")
                    .inkListRow()
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
                .inkListRow()
                if store.isProcessing {
                    VaultIndexingProgress(store: store)
                        .inkListRow()
                }
                if let notice = store.notice {
                    InfoBand(kind: .info, verbatim: notice)
                        .inkListRow()
                }
                if let error = store.errorText {
                    InfoBand(kind: .error, verbatim: error)
                        .inkListRow()
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
                    .inkListRow()
                }
            }
            Section {
                SectionHeader("Atlanan yollar")
                    .inkListRow()
                if store.skippedPaths.isEmpty {
                    Text("Atlanan yol yok.")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        .inkListRow()
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
                    .inkListRow()
                }
            }
            CopyFilesSection(copies: copies)
            Section {
                licensesLink
            }
        }
        .listStyle(.plain)
        .inkPageNavigationTitle("Tanılama")
        .inkPageScrollColumn()
        .inkPage()
        .task(id: store.lastUpdated) {
            do {
                copies = try await store.computeCopyFiles()
            } catch is CancellationError {
                return
            } catch {
                copies = []
            }
        }
    }

    private var rebuildButton: some View {
        Button("Yeniden üret") { Task { await store.refresh(rebuild: true) } }
            .disabled(store.isProcessing)
    }

    @ViewBuilder private var licensesLink: some View {
        #if os(macOS)
            Button("Üçüncü taraf lisansları", action: openLicenses)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("button.settings.diagnostics.licenses")
                .inkListRow()
        #else
            NavigationLink("Üçüncü taraf lisansları") {
                ThirdPartyLicensesView()
            }
            .accessibilityIdentifier("button.settings.diagnostics.licenses")
            .inkListRow()
        #endif
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
        .inkListRow()
    }
}

/// Day and entity copies a sync service set apart, each with the file it duplicates. The app
/// lists them and changes nothing; no copies, no section.
struct CopyFilesSection: View {
    let copies: [CopyFile]

    var body: some View {
        if !copies.isEmpty {
            Section {
                SectionHeader("Kopya dosyalar")
                    .inkListRow()
                ForEach(copies, id: \.copy) { copy in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: copy.copy)
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.text)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Text("Özgün dosya: \(copy.original)")
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    .inkListRow()
                }
            }
        }
    }
}
