import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
    import AppKit
#endif

/// Vault location, folder change, import, and entity types.
struct VaultSettingsView: View {
    @Bindable var store: IndexStore
    @State private var choosingFolder = false

    var body: some View {
        Form {
            Section("Kasa") {
                if let url = store.vaultURL {
                    Text(verbatim: url.path)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.text)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .accessibilityHint(Text(verbatim: url.path))
                    #if os(macOS)
                        Button("Finder'da göster") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        .buttonStyle(.borderless)
                    #endif
                }
                HStack {
                    Button("Klasör seç") { choosingFolder = true }.disabled(
                        store.isInspectingImport || store.importModel != nil)
                    Spacer(minLength: 0)
                }.buttonStyle(.borderless)
                if let selection = store.pendingSelection {
                    LabeledContent("Klasör seçimi bekliyor…") {
                        Text(verbatim: selection.path)
                            .font(.ink.meta)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                if store.unwatchedDirectoryCount > 0 {
                    Text(
                        "İzlenmeyen dizinler: \(store.unwatchedDirectoryCount). Değişiklikler ön planda zamanlayıcıyla denetlenir."
                    )
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                }
                if store.isInspectingImport {
                    InkProgress(kind: .indeterminate(label: "Klasör inceleniyor…"))
                }
                if let model = store.importModel {
                    NavigationLink("Kasa hazırlığı") { VaultImportView(store: store, model: model) }
                }
                if store.isProcessing { VaultIndexingProgress(store: store) }
                if let notice = store.notice {
                    Text(verbatim: notice)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                }
                if let error = store.errorText {
                    Text(verbatim: error)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.danger)
                }
            }
            Section("Varlık tipleri") {
                NavigationLink("Varlık tipleri") { EntityTypesSettingsView(store: store) }
                if store.entityTypes.issue != nil {
                    Text(
                        "Varlık tipleri okunamıyor. Yalnız yerleşik tipler kullanılıyor. Kasadaki .app/types.json dosyasını kontrol et."
                    )
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.warning)
                }
            }
        }
        .formStyle(.grouped)
        .inkPage()
        .inkPageColumn()
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): Task { await store.inspectSelection(url) }
            case .failure(let error): store.report(error)
            }
        }
    }
}
