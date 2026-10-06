import SwiftUI
import UniformTypeIdentifiers

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
                #if os(iOS)
                    Text("Yeni kasa, Dosyalar’da iPhone’umda → Journal → Vault klasöründe oluşturulur.")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                #else
                    Text(
                        "Yeni kasa, uygulamanın Belgeler klasöründeki Vault içinde oluşturulur. Ayarlar’dan Finder’da gösterebilirsin."
                    )
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                #endif
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
