import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    let store: IndexStore
    @State private var choosesFolder = false
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "book.closed").font(.largeTitle)
                Text("Günlüğün, senin dosyaların").font(.title2)
                Text(
                    "Verilerin Markdown dosyalarında kalır. Yeni bir kasa oluşturabilir veya var olan Obsidian klasörünü seçebilirsin."
                )
                .multilineTextAlignment(.center)
                // Matches `VaultLocation.createDefaultVault` (`Documents/Vault`).
                #if os(iOS)
                    Text("Yeni kasa, Dosyalar’da iPhone’umda → Journal → Vault klasöründe oluşturulur.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                #else
                    Text(
                        "Yeni kasa, uygulamanın Belgeler klasöründeki Vault içinde oluşturulur. Ayarlar’dan Finder’da gösterebilirsin."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                #endif
                Button("Yeni kasa oluştur") { Task { await store.start() } }.buttonStyle(.borderedProminent)
                Button("Var olan klasörü seç") { choosesFolder = true }.buttonStyle(.bordered)
                if let error = store.errorText { Text(verbatim: error).foregroundStyle(.red) }
                if store.isInspectingImport { ProgressView("Klasör inceleniyor…") }
                if store.isProcessing { VaultIndexingProgress(store: store) }
            }
            .padding().frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        VStack {
            ProgressView("İndeks güncelleniyor…")
            if let count = store.indexingFileCount { Text("İndekslenecek dosya: \(count)").font(.caption) }
        }
    }
}
