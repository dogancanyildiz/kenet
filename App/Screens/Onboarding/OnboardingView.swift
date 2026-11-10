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
    var body: some View {
        // Welcome on top, the choices at the foot of the screen (Şafak çizimi); the page scrolls
        // when large text needs more than one screen.
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: InkSpacing.section) {
                    welcome
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: InkSpacing.row) {
                        choices
                        status
                    }
                    // Mac's wide column keeps the choices button-sized, centered.
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                }
                .padding(InkSpacing.margin)
                .frame(minHeight: proxy.size.height, alignment: .top)
                .inkPageColumn()
                .frame(maxWidth: .infinity)
            }
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

    private var welcome: some View {
        VStack(alignment: .leading, spacing: InkSpacing.row) {
            KenetRingsBadge(size: 64, cornerRadius: 20, ringDiameter: 24, ringOffset: 6)
            PageHeadline("Kenet")
            Text(
                "Günlerin **senin klasöründe**, düz Markdown dosyaları olarak kalır. Başka uygulamayla da açarsın."
            )
            .font(.body)
            .foregroundStyle(Color.ink.text)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One filled capsule for the main choice, a full-width secondary under it and the folder
    /// choice as a text link (Şafak çizimi).
    @ViewBuilder private var choices: some View {
        if store.isCloudAvailable {
            VStack(spacing: 8) {
                Button {
                    Task { await store.createCloudVault() }
                } label: {
                    choiceLabel("iCloud’da sakla", systemImage: "icloud")
                }
                .buttonStyle(InkPrimaryButtonStyle())
                Text("iPhone ve Mac aynı klasörü paylaşır.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            localVaultButton
                .buttonStyle(InkSecondaryButtonStyle())
        } else {
            localVaultButton
                .buttonStyle(InkPrimaryButtonStyle())
        }
        Button {
            choosesFolder = true
        } label: {
            Label("Var olan klasörü seç", systemImage: "folder")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.ink.accent)
                .frame(maxWidth: .infinity, minHeight: TapTarget.minimumLength)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Text(LocalizedStringKey(OnboardingCopy.newVaultLocation(for: .current).key))
            .font(.ink.meta)
            .foregroundStyle(Color.ink.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder private var status: some View {
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

    private func choiceLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
    }

    private var localVaultSymbol: String {
        switch DeviceIdiom.current {
        case .phone: "iphone"
        case .pad: "ipad"
        case .mac: "laptopcomputer"
        }
    }

    private var localVaultButton: some View {
        Button {
            Task { await store.continueLocally() }
        } label: {
            choiceLabel("Bu cihazda", systemImage: localVaultSymbol)
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
