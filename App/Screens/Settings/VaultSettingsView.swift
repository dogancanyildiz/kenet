import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
    import AppKit
#endif

/// Vault location, folder change, import, and entity types.
struct VaultSettingsView: View {
    @Bindable var store: IndexStore
    @Environment(\.vaultPathDisplayOverride) private var pathDisplayOverride
    @State private var choosingFolder = false

    var body: some View {
        Form {
            InkPageTitleRow("Kasa")
            Section("Kasa") {
                if let path = VaultPathDisplay.text(
                    for: store.vaultURL, override: pathDisplayOverride)
                {
                    Text(verbatim: path)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .accessibilityLabel(Text(verbatim: path))
                    #if os(macOS)
                        if let url = store.vaultURL {
                            Button("Finder'da göster") {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                            .buttonStyle(.borderless)
                        }
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
                            .accessibilityLabel(Text(verbatim: selection.path))
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
                    InfoBand(kind: .info, verbatim: notice)
                }
                if let error = store.errorText {
                    InfoBand(kind: .error, verbatim: error)
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
        .listRowBackground(Color.ink.paper)
        .inkPageNavigationTitle("Kasa")
        .inkPageColumn()
        .inkPage()
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): Task { await store.inspectSelection(url) }
            case .failure(let error): store.report(error)
            }
        }
    }
}
