import SwiftUI
import UniformTypeIdentifiers

/// Where a new vault is created, worded for the device's own Files app.
enum OnboardingCopy {
    static func newVaultLocation(for idiom: DeviceIdiom) -> LocalizedStringResource {
        switch idiom {
        case .phone: "Yeni kasa, Dosyalar’da iPhone’umda → Journal → Vault klasöründe oluşturulur."
        case .pad: "Yeni kasa, Dosyalar’da iPad’imde → Kenet → Vault klasöründe oluşturulur."
        case .mac:
            "Yeni kasa, uygulamanın Belgeler klasöründeki Vault içinde oluşturulur. Ayarlar’dan Finder’da gösterebilirsin."
        }
    }
}

struct OnboardingView: View {
    let store: IndexStore
    @State private var choosesFolder = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeadline("Günlüğün, senin dosyaların")
                Text(
                    "Verilerin Markdown dosyalarında kalır. Yeni bir kasa oluşturabilir veya var olan Obsidian klasörünü seçebilirsin."
                )
                .font(.ink.byline)
                .foregroundStyle(Color.ink.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(LocalizedStringKey(OnboardingCopy.newVaultLocation(for: .current).key))
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                Button("Yeni kasa oluştur") { Task { await store.start() } }
                    .buttonStyle(InkPrimaryButtonStyle())
                Button("Var olan klasörü seç") { choosesFolder = true }
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
                // While the chosen vault opens; it stays in Settings → Kasa afterwards.
                if let synced = store.syncedFolder {
                    InfoBand(kind: .info, verbatim: synced.notice())
                }
            }
            .padding(InkSpacing.margin)
            .inkPageColumn()
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .inkPage()
        .accessibilityIdentifier("screen.onboarding")
        .disabled(store.isProcessing || store.isInspectingImport)
        .fileImporter(isPresented: $choosesFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): Task { await store.inspectSelection(url) }
            case .failure(let error): store.report(error)
            }
        }
    }
}

struct VaultIndexingProgress: View {
    let store: IndexStore
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InkProgress(kind: .indeterminate(label: "İndeks güncelleniyor…"))
            if let count = store.indexingFileCount {
                Text("İndekslenecek dosya: \(count)")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .monospacedDigit()
            }
        }
    }
}
