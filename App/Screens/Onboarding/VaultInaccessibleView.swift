import SwiftUI
import UniformTypeIdentifiers

/// Shown instead of the main tabs when the saved vault bookmark cannot be opened.
struct VaultInaccessibleView: View {
    let store: IndexStore
    @State private var choosesFolder = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle)
                Text("Kayıtlı klasöre erişilemiyor.").font(.title2)
                Text(
                    "Kayıtlı klasör bulunamadı veya açılamıyor. Diski bağlayıp yeniden dene ya da başka bir klasör seç."
                )
                .multilineTextAlignment(.center)
                Button("Yeniden dene") { Task { await store.retryVaultAccess() } }
                    .buttonStyle(.borderedProminent)
                Button("Başka klasör seç") { choosesFolder = true }.buttonStyle(.bordered)
                if let error = store.errorText { Text(verbatim: error).foregroundStyle(.red) }
                if store.isInspectingImport { ProgressView("Klasör inceleniyor…") }
                if store.isProcessing { VaultIndexingProgress(store: store) }
            }
            .padding().frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("screen.vaultInaccessible")
        .disabled(store.isProcessing || store.isInspectingImport)
        .fileImporter(isPresented: $choosesFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): Task { await store.inspectSelection(url) }
            case .failure(let error): store.report(error)
            }
        }
    }
}
