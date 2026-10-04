import SwiftUI
import UniformTypeIdentifiers

/// Settings for the file-backed vault and its disposable index.
struct DiagnosticsView: View {
    @Bindable var store: IndexStore
    @State private var choosingFolder = false

    var body: some View {
        Form {
            AppLockSettingsView()
            Section("Varlık tipleri") {
                NavigationLink("Varlık tipleri") { EntityTypesSettingsView(store: store) }
                if store.entityTypes.issue != nil {
                    Text(
                        "Varlık tipleri okunamıyor. Yalnız yerleşik tipler kullanılıyor. Kasadaki .app/types.json dosyasını kontrol et."
                    )
                    .foregroundStyle(.orange)
                }
            }
            PeopleInsightsSettingsView()
            CalendarSettingsView()
            LocationSettingsView()
            #if os(iOS)
                Section("Bildirimler") {
                    NavigationLink("Bildirimler", destination: NotificationSettingsView())
                }
            #endif
            Section("Kasa") {
                if let url = store.vaultURL {
                    Text(verbatim: url.path).textSelection(.enabled)
                }
                HStack {
                    Button("Klasör seç") { choosingFolder = true }.disabled(
                        store.isInspectingImport || store.importModel != nil)
                    Button("Yeniden üret") { Task { await store.refresh(rebuild: true) } }
                        .disabled(store.isProcessing)
                }

                if let selection = store.pendingSelection {
                    LabeledContent("Klasör seçimi bekliyor…") { Text(verbatim: selection.path) }
                }
                if store.unwatchedDirectoryCount > 0 {
                    Text(
                        "İzlenmeyen dizinler: \(store.unwatchedDirectoryCount). Değişiklikler ön planda zamanlayıcıyla denetlenir."
                    )
                    .foregroundStyle(.secondary)
                }
                if store.isInspectingImport { ProgressView("Klasör inceleniyor…") }
                if let model = store.importModel {
                    NavigationLink("Kasa hazırlığı") { VaultImportView(store: store, model: model) }
                }
                if store.isProcessing { VaultIndexingProgress(store: store) }
                if let notice = store.notice { Text(verbatim: notice).foregroundStyle(.secondary) }
                if let error = store.errorText { Text(verbatim: error).foregroundStyle(.red) }
            }
            Section("İndeks") {
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
                    LabeledContent("Son güncelleme") { Text(date, format: .dateTime) }
                }
            }
            Section("Atlanan yollar") {
                if store.skippedPaths.isEmpty { Text("Atlanan yol yok.") }
                ForEach(store.skippedPaths, id: \.path) { skipped in
                    VStack(alignment: .leading) {
                        Text(verbatim: skipped.path)
                        if skipped.reason == .symbolicLink {
                            Text("Sembolik bağlantı")
                        } else {
                            Text("Yinelenen normalleştirilmiş yol")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): Task { await store.inspectSelection(url) }
            case .failure(let error): store.report(error)
            }
        }
    }

    private func count(_ label: LocalizedStringKey, _ value: Int) -> some View {
        LabeledContent(label) { Text(value, format: .number) }
    }
}
