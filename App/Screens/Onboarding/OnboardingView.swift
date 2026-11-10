import SwiftUI
import UniformTypeIdentifiers

/// Where a new vault is created, worded for the device's own Files app.
enum OnboardingCopy {
    static func newVaultLocation(for idiom: DeviceIdiom) -> LocalizedStringResource {
        switch idiom {
        case .phone: "Yeni kasa, Dosyalar’da iPhone’umda → Kenet → Vault klasöründe oluşturulur."
        case .pad: "Yeni kasa, Dosyalar’da iPad’imde → Kenet → Vault klasöründe oluşturulur."
        case .mac:
            "Yeni kasa, uygulamanın Belgeler klasöründeki Vault içinde oluşturulur. Ayarlar’dan Finder’da gösterebilirsin."
        }
    }
}

struct OnboardingView: View {
    @Bindable var store: IndexStore
    @State private var choosesFolder = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: InkSpacing.section) {
                VStack(alignment: .leading, spacing: InkSpacing.row) {
                    KenetRingsBadge(size: 64, cornerRadius: 20, ringDiameter: 24, ringOffset: 6)
                    PageHeadline("Kenet")
                    Text(
                        "Verilerin Markdown dosyalarında kalır. Yeni bir kasa oluşturabilir veya var olan Obsidian klasörünü seçebilirsin."
                    )
                    .font(.ink.byline)
                    .foregroundStyle(Color.ink.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: InkSpacing.row) {
                    if store.isCloudAvailable {
                        VStack(alignment: .leading, spacing: 8) {
                            Button("iCloud’da sakla") { Task { await store.createCloudVault() } }
                                .buttonStyle(InkPrimaryButtonStyle())
                            Text("iPhone ve Mac aynı klasörü paylaşır.")
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        // Side by side while both words fit one line; stacked otherwise and
                        // always at accessibility text sizes.
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: InkSpacing.row) { secondaryButtons }
                        } else {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: InkSpacing.row) { secondaryButtons }
                                VStack(alignment: .leading, spacing: InkSpacing.row) { secondaryButtons }
                            }
                        }
                    } else {
                        localVaultButton
                            .buttonStyle(InkPrimaryButtonStyle())
                        Button("Var olan klasörü seç") { choosesFolder = true }
                            .buttonStyle(InkSecondaryButtonStyle())
                    }
                    Text(LocalizedStringKey(OnboardingCopy.newVaultLocation(for: .current).key))
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                }
                if let error = store.errorText {
                    InfoBand(kind: .error, verbatim: error)
                }
                if store.isInspectingImport {
                    InkProgress(kind: .indeterminate(label: "Klasör inceleniyor…"))
                }
                if store.isOpeningCloudVault {
                    InkProgress(kind: .indeterminate(label: "iCloud’daki kasa açılıyor…"))
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
        .inkGlow()
        .accessibilityIdentifier("screen.onboarding")
        .task {
            do { try await store.refreshCloudAvailability() } catch { store.report(error) }
        }
        .disabled(store.isProcessing || store.isInspectingImport || store.isOpeningCloudVault)
        .fileImporter(isPresented: $choosesFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): Task { await store.inspectSelection(url) }
            case .failure(let error): store.report(error)
            }
        }
    }

    @ViewBuilder private var secondaryButtons: some View {
        localVaultButton
            .buttonStyle(InkSecondaryButtonStyle())
        Button("Var olan klasörü seç") { choosesFolder = true }
            .buttonStyle(InkSecondaryButtonStyle())
    }

    private var localVaultButton: some View {
        Button("Bu cihazda") { Task { await store.continueLocally() } }
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
