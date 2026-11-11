import SwiftUI
import VaultIndex

/// Index counts, skipped paths, rebuild, search-history clear, and third-party licenses.
struct DiagnosticsView: View {
    @Bindable var store: IndexStore
    #if os(macOS)
        /// The Settings tab swaps its content; a push would shift the tab strip's highlight.
        var openLicenses: () -> Void = {}
    #endif
    @Environment(\.scenePhase) private var scenePhase
    /// Sync copies left in the vault; reloaded with each index publish.
    @State private var copies: [CopyFile] = []
    /// Files with unresolved iCloud versions and the versions merges saved under `conflicts/`.
    @State private var conflictedFiles: [ConflictedFile] = []
    @State private var conflictCopies: [CopyFile] = []
    /// Counts returns to the foreground: an iCloud conflict may arrive without a vault folder event.
    @State private var activations = 0

    var body: some View {
        List {
            #if os(iOS)
                InkPageTitleRow("Tanılama")
            #endif
            Section {
                SectionHeader("İndeks")
                    .inkListRow()
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
                InkCard(padded: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // One action per row with a hairline between, as every other card row.
                        actionRow(rebuildButton)
                        InkCardDivider()
                        actionRow(clearHistoryButton)
                        InkCardDivider()
                        countRow("Dosyalar", store.counts.files)
                        InkCardDivider()
                        countRow("Günler", store.counts.filesByKind["day", default: 0])
                        InkCardDivider()
                        countRow("Kişiler", store.counts.filesByKind["person", default: 0])
                        InkCardDivider()
                        countRow("Konumlar", store.counts.filesByKind["place", default: 0])
                        InkCardDivider()
                        countRow("Hedefler", store.counts.filesByKind["goal", default: 0])
                        InkCardDivider()
                        countRow("Notlar", store.counts.filesByKind["note", default: 0])
                        InkCardDivider()
                        countRow("Olaylar", store.counts.events)
                        InkCardDivider()
                        countRow("Görevler", store.counts.tasks)
                        InkCardDivider()
                        countRow("Varlıklar", store.counts.entities)
                        InkCardDivider()
                        countRow("Bağlantılar", store.counts.links)
                        InkCardDivider()
                        countRow("Çözülmemiş bağlantılar", store.counts.unresolvedLinks)
                        InkCardDivider()
                        countRow("Reddedilen iCloud indirme istekleri", store.sync.downloadFailures)
                        if let date = store.lastUpdated {
                            InkCardDivider()
                            LabeledContent("Son güncelleme") {
                                Text(date, format: .dateTime)
                                    .font(.ink.value)
                            }
                            .frame(minHeight: InkButtonChrome.minimumHeight)
                            .padding(.horizontal, InkSpacing.cardPadding)
                        }
                    }
                }
                .inkListRow()
            }
            Section {
                SectionHeader("Atlanan yollar")
                    .inkListRow()
                InkCard(padded: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if store.skippedPaths.isEmpty {
                            Text("Atlanan yol yok.")
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.secondaryText)
                                .frame(
                                    maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading
                                )
                                .padding(.horizontal, InkSpacing.cardPadding)
                        }
                        ForEach(Array(store.skippedPaths.enumerated()), id: \.element.path) { index, skipped in
                            if index > 0 { InkCardDivider() }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: skipped.path)
                                    .font(.ink.meta)
                                    .foregroundStyle(Color.ink.text)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                if skipped.reason == .symbolicLink {
                                    Text("Sembolik bağlantı")
                                        .font(.ink.meta)
                                        .foregroundStyle(Color.ink.secondaryText)
                                } else {
                                    Text("Yinelenen normalleştirilmiş yol")
                                        .font(.ink.meta)
                                        .foregroundStyle(Color.ink.secondaryText)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, InkSpacing.cardPadding)
                            .padding(.vertical, 10)
                        }
                    }
                }
                .inkListRow()
            }
            ShareListProblemsSection(names: store.shareListProblems)
            CopyFilesSection(copies: copies)
            ConflictedFilesSection(files: conflictedFiles)
            ConflictCopiesSection(copies: conflictCopies)
            Section {
                licensesLink
            }
        }
        .listStyle(.plain)
        .inkPageNavigationTitle("Tanılama")
        .inkPageScrollColumn()
        .inkPage()
        .task(id: SyncListReload(lastUpdated: store.lastUpdated, activations: activations)) {
            await reloadSyncLists()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { activations += 1 }
        }
    }

    /// Each list loads on its own: one that fails is empty, the others still show.
    private func reloadSyncLists() async {
        do {
            copies = try await store.computeCopyFiles()
        } catch is CancellationError {
            return
        } catch {
            copies = []
        }
        do {
            conflictedFiles = try await store.computeConflictedFiles()
        } catch is CancellationError {
            return
        } catch {
            conflictedFiles = []
        }
        do {
            conflictCopies = try await store.computeConflictCopies()
        } catch is CancellationError {
            return
        } catch {
            conflictCopies = []
        }
    }

    private func actionRow(_ button: some View) -> some View {
        button
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading)
            .padding(.horizontal, InkSpacing.cardPadding)
    }

    private var rebuildButton: some View {
        Button("Yeniden üret") { Task { await store.refresh(rebuild: true) } }
            .disabled(store.isProcessing)
    }

    @ViewBuilder private var licensesLink: some View {
        InkCard(padded: false) {
            #if os(macOS)
                Button("Üçüncü taraf lisansları", action: openLicenses)
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading)
                    .padding(.horizontal, InkSpacing.cardPadding)
                    .accessibilityIdentifier("button.settings.diagnostics.licenses")
            #else
                NavigationLink("Üçüncü taraf lisansları") {
                    ThirdPartyLicensesView()
                }
                .frame(minHeight: InkButtonChrome.minimumHeight)
                .padding(.horizontal, InkSpacing.cardPadding)
                .accessibilityIdentifier("button.settings.diagnostics.licenses")
            #endif
        }
        .inkListRow()
    }

    private var clearHistoryButton: some View {
        Button("Arama geçmişini temizle") {
            SearchModel.clearStoredHistory(for: store.vaultURL)
        }
        .disabled(store.vaultURL == nil)
    }

    private func countRow(_ label: LocalizedStringKey, _ value: Int) -> some View {
        LabeledContent(label) {
            Text(value, format: .number)
                .font(.ink.value)
                .monospacedDigit()
        }
        .frame(minHeight: InkButtonChrome.minimumHeight)
        .padding(.horizontal, InkSpacing.cardPadding)
    }
}

/// Day and entity copies a sync service set apart, each with the file it duplicates. The app
/// lists them and changes nothing; no copies, no section.
struct CopyFilesSection: View {
    let copies: [CopyFile]

    var body: some View {
        if !copies.isEmpty {
            Section {
                SectionHeader("Kopya dosyalar")
                    .inkListRow()
                InkCard(padded: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(copies.enumerated()), id: \.element.copy) { index, copy in
                            if index > 0 { InkCardDivider() }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: copy.copy)
                                    .font(.ink.meta)
                                    .foregroundStyle(Color.ink.text)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                Text("Özgün dosya: \(copy.original)")
                                    .font(.ink.meta)
                                    .foregroundStyle(Color.ink.secondaryText)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, InkSpacing.cardPadding)
                            .padding(.vertical, 10)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .inkListRow()
            }
        }
    }
}

private struct SyncListReload: Equatable {
    let lastUpdated: Date?
    let activations: Int
}

/// Files iCloud keeps unresolved conflicting versions of: the path, how many versions, when the
/// newest was saved and on which devices. The app merges and removes nothing; no files, no section.
struct ConflictedFilesSection: View {
    let files: [ConflictedFile]
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        if !files.isEmpty {
            Section {
                SectionHeader("Çakışan sürümler")
                    .inkListRow()
                InkCard(padded: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(files.enumerated()), id: \.element.path) { index, file in
                            if index > 0 { InkCardDivider() }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: file.path)
                                    .font(.ink.meta)
                                    .foregroundStyle(Color.ink.text)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                summary(file)
                                    .font(.ink.meta)
                                    .foregroundStyle(Color.ink.secondaryText)
                                if let devices = Self.deviceNames(file) {
                                    Text(verbatim: devices)
                                        .font(.ink.meta)
                                        .foregroundStyle(Color.ink.secondaryText)
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, InkSpacing.cardPadding)
                            .padding(.vertical, 10)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .inkListRow()
                Text("Kenet sürümleri birleştirmez ve silmez.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
            }
        }
    }

    /// "N sürüm", with the newest version's time when the service knows it.
    private func summary(_ file: ConflictedFile) -> Text {
        let count = file.versions.count
        guard let newest = file.versions.map(\.modificationTime).max(), newest > 0 else {
            return Text("\(count) sürüm")
        }
        let date = Date(timeIntervalSince1970: TimeInterval(newest))
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone)
        return Text("\(count) sürüm · en yenisi \(date, format: style)")
    }

    /// The saving devices in version order, each once; `nil` when none is named.
    static func deviceNames(_ file: ConflictedFile) -> String? {
        var seen: Set<String> = []
        let names = file.versions.compactMap(\.deviceName).filter { !$0.isEmpty && seen.insert($0).inserted }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }
}

/// The versions a day copy merge saved under `conflicts/`, each with its day file, in the
/// `CopyFilesSection` layout. The app reads and removes none of them; no copies, no section.
struct ConflictCopiesSection: View {
    let copies: [CopyFile]

    var body: some View {
        if !copies.isEmpty {
            Section {
                SectionHeader("Çakışma kopyaları")
                    .inkListRow()
                InkCard(padded: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(copies.enumerated()), id: \.element.copy) { index, copy in
                            if index > 0 { InkCardDivider() }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: copy.copy)
                                    .font(.ink.meta)
                                    .foregroundStyle(Color.ink.text)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                Text("Gün dosyası: \(copy.original)")
                                    .font(.ink.meta)
                                    .foregroundStyle(Color.ink.secondaryText)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, InkSpacing.cardPadding)
                            .padding(.vertical, 10)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .inkListRow()
            }
        }
    }
}

/// Share lists in the App Group that the last run could not read or change. They stay in place
/// and the next run reads them again; no problem, no section.
struct ShareListProblemsSection: View {
    let names: [String]

    var body: some View {
        if !names.isEmpty {
            Section {
                SectionHeader("Paylaşım listeleri")
                    .inkListRow()
                InkCard(padded: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(names.enumerated()), id: \.element) { index, name in
                            if index > 0 { InkCardDivider() }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: name)
                                    .font(.ink.meta)
                                    .foregroundStyle(Color.ink.text)
                                    .textSelection(.enabled)
                                Text(
                                    "Okunamadı ya da değiştirilemedi. Paylaşımlar dosyada bekliyor; uygulama sonraki açılışta yeniden dener."
                                )
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, InkSpacing.cardPadding)
                            .padding(.vertical, 10)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .inkListRow()
            }
        }
    }
}
