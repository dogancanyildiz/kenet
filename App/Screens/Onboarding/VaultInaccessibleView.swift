import SwiftUI
import UniformTypeIdentifiers

/// Shown instead of the main tabs when the saved vault bookmark cannot be opened.
struct VaultInaccessibleView: View {
    let store: IndexStore
    @State private var choosesFolder = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if store.vaultKind == .icloud, store.isCloudAvailable {
                    // iCloud answers, but the Kenet folder is gone or unreadable.
                    InfoBand(kind: .warning, "iCloud’daki kasaya erişilemiyor.")
                    Text(
                        "iCloud Drive’daki Kenet klasörü bulunamadı veya açılamıyor. Klasörü geri koyup yeniden dene ya da başka bir seçenek seç."
                    )
                    .font(.ink.byline)
                    .foregroundStyle(Color.ink.text)
                } else if store.vaultKind == .icloud {
                    InfoBand(kind: .warning, "iCloud kapalı")
                    Text("iCloud’a erişilemiyor. Hesabını ve iCloud Drive’ı kontrol edip yeniden dene. Kasan korunur.")
                        .font(.ink.byline)
                        .foregroundStyle(Color.ink.text)
                } else {
                    InfoBand(kind: .warning, "Kayıtlı klasöre erişilemiyor.")
                    Text(
                        "Kayıtlı klasör bulunamadı veya açılamıyor. Diski bağlayıp yeniden dene ya da başka bir klasör seç."
                    )
                    .font(.ink.byline)
                    .foregroundStyle(Color.ink.text)
                }
                Button("Yeniden dene") { Task { await store.retryVaultAccess() } }
                    .buttonStyle(InkPrimaryButtonStyle())
                if store.vaultKind == .icloud {
                    Button("Bu cihazda devam et") { Task { await store.continueLocally() } }
                        .buttonStyle(InkTextButtonStyle())
                }
                Button("Başka klasör seç") { choosesFolder = true }
                    .buttonStyle(InkTextButtonStyle())
                if let error = store.errorText {
                    Text(verbatim: error)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.danger)
                }
                if store.isInspectingImport {
                    InkProgress(kind: .indeterminate(label: "Klasör inceleniyor…"))
                }
                if store.isProcessing { VaultIndexingProgress(store: store) }
            }
            .padding(InkSpacing.margin)
            .inkPageColumn()
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .inkPage()
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
