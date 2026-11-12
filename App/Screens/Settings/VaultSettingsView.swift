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
                                .buttonStyle(InkTextButtonStyle())
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
                        Button("Klasör seç") { choosingFolder = true }
                            .buttonStyle(InkTextButtonStyle())
                            .disabled(store.isInspectingImport || store.importModel != nil)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
            // Drawing (Mac Kasa): the counts, then the index with its secondary rebuild and the
            // pages the vault holds, each a row with its value and "›".
            Section {
                VaultCountsCard(counts: store.counts)
                    .inkListRow()
                // One list row per control, the card drawn across the rows (InkCardSegment): a
                // List row with a link and a button in it runs the link for a tap on either.
                VaultIndexRow(store: store)
                    .inkListRow(cardSegment: .first)
                entityTypesRow
                    .inkListRow(cardSegment: store.importModel == nil ? .last : .middle)
                if let model = store.importModel {
                    importRow(model)
                        .inkListRow(cardSegment: .last)
                }
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

    /// "Varlık tipleri · 3 özel tip ›" (drawing: Mac Kasa).
    private var customTypesValue: Text {
        Text("\(store.entityTypes.types.count) özel tip")
    }

    @ViewBuilder private var entityTypesRow: some View {
        #if os(macOS)
            Button {
                openSubpage(.entityTypes)
            } label: {
                InkDisclosureRowLabel("Varlık tipleri", value: customTypesValue)
            }
            .inkDisclosureRow("Varlık tipleri", value: customTypesValue)
        #else
            NavigationLink {
                EntityTypesSettingsView(store: store)
            } label: {
                InkDisclosureRowLabel("Varlık tipleri", value: customTypesValue)
            }
            .inkDisclosureRow("Varlık tipleri", value: customTypesValue)
        #endif
    }

    @ViewBuilder private func importRow(_ model: VaultImportModel) -> some View {
        #if os(macOS)
            Button {
                openSubpage(.vaultImport)
            } label: {
                InkDisclosureRowLabel("Kasa hazırlığı")
            }
            .inkDisclosureRow("Kasa hazırlığı")
        #else
            NavigationLink {
                VaultImportView(store: store, model: model, isSheet: false)
            } label: {
                InkDisclosureRowLabel("Kasa hazırlığı")
            }
            .inkDisclosureRow("Kasa hazırlığı")
        #endif
    }
}

/// The vault's four counts side by side (drawing: Mac Kasa "1.284 dosya · 412 gün · 38 kişi ·
/// 21 konum"). At large text sizes they wrap to two rows of two.
struct VaultCountsCard: View {
    let counts: IndexCounts

    var body: some View {
        InkCard {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: InkSpacing.row) { cells }
                Grid(alignment: .leading, horizontalSpacing: InkSpacing.row, verticalSpacing: InkSpacing.row) {
                    GridRow {
                        cell(counts.files, "dosya")
                        cell(counts.filesByKind["day", default: 0], "gün")
                    }
                    GridRow {
                        cell(counts.filesByKind["person", default: 0], "kişi")
                        cell(counts.filesByKind["place", default: 0], "konum")
                    }
                }
            }
        }
    }

    @ViewBuilder private var cells: some View {
        cell(counts.files, "dosya")
        cell(counts.filesByKind["day", default: 0], "gün")
        cell(counts.filesByKind["person", default: 0], "kişi")
        cell(counts.filesByKind["place", default: 0], "konum")
    }

    private func cell(_ value: Int, _ unit: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number)
                .font(.ink.sectionTitle.monospacedDigit())
                .foregroundStyle(Color.ink.text)
            Text(unit)
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The index row: "İndeks", when it was last updated, and the secondary rebuild button (drawing:
/// Mac Kasa; the rebuild reads the files and never writes them).
struct VaultIndexRow: View {
    @Bindable var store: IndexStore

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: InkSpacing.row) {
                labels
                Spacer(minLength: 8)
                rebuild
            }
            VStack(alignment: .leading, spacing: 8) {
                labels
                rebuild
            }
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading)
        .padding(.horizontal, InkSpacing.cardPadding)
        .padding(.vertical, 6)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("İndeks")
                .foregroundStyle(Color.ink.text)
            Group {
                if let date = store.lastUpdated {
                    Text(
                        "Son güncelleme \(Text(date, format: .dateTime.day().month(.abbreviated).hour().minute())) · dosyalara dokunmaz"
                    )
                } else {
                    Text("Dosyalara dokunmaz")
                }
            }
            .font(.ink.meta)
            .foregroundStyle(Color.ink.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var rebuild: some View {
        Button {
            Task { await store.refresh(rebuild: true) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .accessibilityHidden(true)
                Text("İndeksi yeniden kur")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.ink.meta.weight(.semibold))
        }
        .buttonStyle(InkSecondaryButtonStyle())
        .disabled(store.isProcessing)
    }
}
