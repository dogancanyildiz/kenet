import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
    import AppKit
#endif

/// A page reached from the vault settings: pushed on iPhone, shown in place of the Kasa tab's
/// content on Mac (`MacVaultSettingsPage`).
enum VaultSettingsSubpage: Hashable {
    case vaultImport
    case entityTypes
}

/// Vault location, folder change, import, and entity types.
struct VaultSettingsView: View {
    @Bindable var store: IndexStore
    #if os(macOS)
        /// The Settings tab swaps its content; a push would shift the tab strip's highlight.
        var openSubpage: (VaultSettingsSubpage) -> Void = { _ in }
    #endif
    @Environment(\.vaultPathDisplayOverride) private var pathDisplayOverride
    @State private var choosingFolder = false

    var body: some View {
        List {
            #if os(iOS)
                InkPageTitleRow("Kasa")
            #endif
            Section {
                SectionHeader("Konum")
                    .inkListRow()
                InkCard(padded: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        LabeledContent("Konum türü") {
                            switch store.vaultKind {
                            case .icloud: Text("iCloud")
                            case .local: Text("Bu cihazda")
                            case .selected: Text("Seçilen klasör")
                            }
                        }
                        .frame(minHeight: InkButtonChrome.minimumHeight)
                        .padding(.horizontal, InkSpacing.cardPadding)

                        if store.vaultKind == .local, store.isCloudAvailable {
                            InkCardDivider()
                            Button("iCloud’a taşı") { store.requestCloudMigration() }
                                .buttonStyle(.borderless)
                                .disabled(store.isProcessing || store.isMigratingCloud)
                                .frame(
                                    maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading
                                )
                                .padding(.horizontal, InkSpacing.cardPadding)
                        }
                        if let path = VaultPathDisplay.text(
                            for: store.vaultURL, override: pathDisplayOverride)
                        {
                            InkCardDivider()
                            Text(verbatim: path)
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.text)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .accessibilityLabel(Text(verbatim: path))
                                .frame(
                                    maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading
                                )
                                .padding(.horizontal, InkSpacing.cardPadding)
                            #if os(macOS)
                                if let url = store.vaultURL {
                                    InkCardDivider()
                                    Button("Finder'da göster") {
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    }
                                    .buttonStyle(.borderless)
                                    .frame(
                                        maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight,
                                        alignment: .leading
                                    )
                                    .padding(.horizontal, InkSpacing.cardPadding)
                                }
                            #endif
                        }
                        InkCardDivider()
                        HStack {
                            Button("Klasör seç") { choosingFolder = true }.disabled(
                                store.isInspectingImport || store.importModel != nil)
                            Spacer(minLength: 0)
                        }
                        .buttonStyle(.borderless)
                        .frame(minHeight: InkButtonChrome.minimumHeight)
                        .padding(.horizontal, InkSpacing.cardPadding)

                        if let selection = store.pendingSelection {
                            InkCardDivider()
                            LabeledContent("Klasör seçimi bekliyor…") {
                                Text(verbatim: selection.path)
                                    .font(.ink.meta)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                    .accessibilityLabel(Text(verbatim: selection.path))
                            }
                            .frame(minHeight: InkButtonChrome.minimumHeight)
                            .padding(.horizontal, InkSpacing.cardPadding)
                        }
                        if let model = store.importModel {
                            InkCardDivider()
                            #if os(macOS)
                                Button("Kasa hazırlığı") { openSubpage(.vaultImport) }
                                    .buttonStyle(.borderless)
                                    .frame(
                                        maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight,
                                        alignment: .leading
                                    )
                                    .padding(.horizontal, InkSpacing.cardPadding)
                            #else
                                NavigationLink("Kasa hazırlığı") {
                                    VaultImportView(store: store, model: model, isSheet: false)
                                }
                                .frame(minHeight: InkButtonChrome.minimumHeight)
                                .padding(.horizontal, InkSpacing.cardPadding)
                            #endif
                        }
                    }
                }
                .inkListRow()

                if store.retainedLocalVault {
                    Text("Yerel kasa bu cihazın Belgeler → Vault klasöründe korundu.")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        .inkListRow()
                }
                if let synced = store.syncedFolder {
                    InfoBand(kind: .info, verbatim: synced.notice())
                        .inkListRow()
                }
                if store.unwatchedDirectoryCount > 0 {
                    Text(
                        "İzlenmeyen dizinler: \(store.unwatchedDirectoryCount). Değişiklikler ön planda zamanlayıcıyla denetlenir."
                    )
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
                }
                if store.isInspectingImport {
                    InkProgress(kind: .indeterminate(label: "Klasör inceleniyor…"))
                        .inkListRow()
                }
                if store.isProcessing {
                    VaultIndexingProgress(store: store)
                        .inkListRow()
                }
                if let notice = store.notice {
                    InfoBand(kind: .info, verbatim: notice)
                        .inkListRow()
                }
                if let error = store.errorText {
                    InfoBand(kind: .error, verbatim: error)
                        .inkListRow()
                }
            }
            Section {
                SectionHeader("Varlık tipleri")
                    .inkListRow()
                InkCard(padded: false) {
                    #if os(macOS)
                        Button("Varlık tipleri") { openSubpage(.entityTypes) }
                            .buttonStyle(.borderless)
                            .frame(maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading)
                            .padding(.horizontal, InkSpacing.cardPadding)
                    #else
                        NavigationLink("Varlık tipleri") { EntityTypesSettingsView(store: store) }
                            .frame(minHeight: InkButtonChrome.minimumHeight)
                            .padding(.horizontal, InkSpacing.cardPadding)
                    #endif
                }
                .inkListRow()
                if store.entityTypes.issue != nil {
                    Text(
                        "Varlık tipleri okunamıyor. Yalnız yerleşik tipler kullanılıyor. Kasadaki .app/types.json dosyasını kontrol et."
                    )
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.warning)
                    .inkListRow()
                }
            }
        }
        .listStyle(.plain)
        .inkPageNavigationTitle("Kasa")
        .inkPageScrollColumn()
        .inkPage()
        .task {
            do { try await store.refreshCloudAvailability() } catch { store.report(error) }
        }
        .sheet(
            isPresented: Binding(
                get: { store.showsCloudMigration && !store.isCloudMigrationAutomatic },
                set: { store.showsCloudMigration = $0 })
        ) {
            NavigationStack { VaultCloudMigrationView(store: store) }
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): Task { await store.inspectSelection(url) }
            case .failure(let error): store.report(error)
            }
        }
    }
}
