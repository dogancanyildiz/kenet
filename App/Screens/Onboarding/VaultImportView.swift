import SwiftUI

/// Pure decisions of the vault preparation page (unit-tested; ``VaultImportView`` calls these).
enum VaultImportChrome {
    /// A write is in flight: the preparation itself, or opening and indexing the vault.
    static func isWriting(isApplying: Bool, isProcessing: Bool) -> Bool { isApplying || isProcessing }

    /// The sheet is cancel-only. "Vazgeç" stays until the result is in; after that the bar is
    /// empty and "Kasayı aç" in the page is the way out. If opening the vault fails, "Vazgeç"
    /// comes back: the sheet must never be a dead end.
    static func showsCancel(hasResult: Bool, openFailed: Bool) -> Bool { !hasResult || openFailed }

    /// Opening the prepared vault reported an error.
    static func openFailed(hasResult: Bool, hasError: Bool) -> Bool { hasResult && hasError }

    /// "Uygula" writes folders, templates and settings into the vault.
    static func canApply(canPrepare: Bool, isWriting: Bool) -> Bool { canPrepare && !isWriting }

    /// Swiping the sheet away would lose the report of what was written.
    static func blocksInteractiveDismiss(hasResult: Bool, isWriting: Bool, openFailed: Bool) -> Bool {
        isWriting || (hasResult && !openFailed)
    }
}

/// Folder report and preparation options for a chosen vault folder.
///
/// "Uygula" does not save a draft: it creates folders, templates and a settings file in the
/// vault. So the sheet (the default) is cancel-only: the bar holds "Vazgeç" alone, the actions
/// ("Uygula", "Atla") are buttons in the page and nothing is bound to Return. Once the result
/// is in, its section appears directly under the manşet, the bar is empty and "Kasayı aç" is the
/// only way out. Pushed inside Settings (`isSheet: false`) it is a subpage: the bar keeps only
/// the back button and the page is the same.
///
/// The page is one `List` in one branch: the result must not rebuild the list (that would
/// reset the scroll position and leave the result below the fold).
struct VaultImportView: View {
    let store: IndexStore
    @Bindable var model: VaultImportModel
    var isSheet = true
    @Environment(\.vaultPathDisplayOverride) private var pathDisplayOverride
    /// Open by default: a failure must be seen without an extra tap.
    @State private var showsFailures = true

    private var openFailed: Bool {
        VaultImportChrome.openFailed(hasResult: model.result != nil, hasError: store.errorText != nil)
    }

    private var isWriting: Bool {
        VaultImportChrome.isWriting(isApplying: model.isApplying, isProcessing: store.isProcessing)
    }

    var body: some View {
        // `isSheet` never changes for one presentation, so this branch is not a state change.
        if isSheet {
            page.inkSheet(
                "Kasa hazırlığı", cancelIdentifier: "button.vaultImport.cancel",
                showsCancel: VaultImportChrome.showsCancel(
                    hasResult: model.result != nil, openFailed: openFailed),
                isCancelEnabled: !isWriting)
        } else {
            page.inkPageNavigationTitle("Kasa hazırlığı")
        }
    }

    private var page: some View {
        ScrollViewReader { proxy in
            content
                .onChange(of: model.result != nil) { _, hasResult in
                    guard hasResult else { return }
                    withAnimation { proxy.scrollTo(Self.topAnchor, anchor: .top) }
                }
        }
    }

    private static let topAnchor = "vaultImport.top"

    private var content: some View {
        List {
            InkPageTitleRow("Kasa hazırlığı")
                .id(Self.topAnchor)
            if let result = model.result {
                resultSection(result)
            }
            Section {
                SectionHeader(title: String(localized: "Klasör raporu"))
                    .inkListRow()
                Text(verbatim: VaultPathDisplay.text(for: model.report.root, override: pathDisplayOverride) ?? "")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.text)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .inkListRow()
                labeled("Markdown dosyaları", model.report.markdownCount)
                labeled("Gün dosyaları", model.report.journalDays.count)
                labeled("Diğer yollardaki gün dosyaları", model.report.externalDays.count)
                labeled("Kişiler", model.report.typed["person", default: 0])
                labeled("Konumlar", model.report.typed["place", default: 0])
                labeled("Hedefler", model.report.typed["goal", default: 0])
                DisclosureGroup("Bulunan klasörler") {
                    ForEach(model.report.foundFolders, id: \.self) { path in
                        Text(verbatim: path)
                            .font(.ink.meta)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                .inkListRow()
                if !model.report.caseVariantFolders.isEmpty {
                    DisclosureGroup("Harf farkı olan klasörler") {
                        ForEach(model.report.caseVariantFolders, id: \.self) { Text(verbatim: $0 + "/") }
                    }
                    .inkListRow()
                    Text(
                        "Bu klasör adları tam olarak journal, people, places, goals, notes veya templates olmalı. Obsidian'da yeniden adlandır; aksi halde o klasöre yazma reddedilir."
                    )
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
                }
                if !model.report.externalDays.isEmpty {
                    DisclosureGroup("Taşınmayacak günlükler") {
                        ForEach(model.report.externalDays, id: \.self) { path in
                            Text(verbatim: path)
                                .font(.ink.meta)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                    .inkListRow()
                    Text(
                        "Bu günlükler taşınmaz. Gün görünümünde kullanmak için Obsidian'da journal klasörüne düzenleyebilirsin."
                    )
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
                }
                DisclosureGroup("Türü olmayan dosyalar") {
                    ForEach(model.report.candidates, id: \.path) { candidate in
                        Text(verbatim: candidate.path)
                            .font(.ink.meta)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                .inkListRow()
                if !model.report.skipped.isEmpty {
                    DisclosureGroup("Atlanacak dosyalar") {
                        ForEach(model.report.skipped, id: \.self) { path in
                            Text(verbatim: path)
                                .font(.ink.meta)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                    .inkListRow()
                }
            }
            if model.result == nil {
                Section {
                    SectionHeader(title: String(localized: "Hazırlama seçenekleri"))
                        .inkListRow()
                    DisclosureGroup("Eksik klasörler ve şablonlar") {
                        ForEach(
                            model.report.missingFolders.map { $0 + "/" } + model.report.missingTemplates, id: \.self
                        ) { Text(verbatim: $0) }
                    }
                    .inkListRow()
                    Toggle("Eksik klasörleri ve şablonları oluştur", isOn: $model.options.folders)
                        .inkListRow()
                    Toggle("Eksik kasa ayarını oluştur", isOn: $model.options.settings)
                        .inkListRow()
                    Toggle("Kişi ve konum dosyalarına tür ekle", isOn: $model.options.types)
                        .inkListRow()
                    Text("Mevcut dosyalar taşınmaz; Obsidian ayarları korunur.")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        .inkListRow()
                    if !model.report.canPrepare {
                        Text("Kasa sürümü okunamıyor veya desteklenmiyor. Hazırlama yapılamaz.")
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                            .inkListRow()
                    }
                    // The primary action lives in the page, not in the bar: it is not a save.
                    Button("Uygula") { Task { await model.apply() } }
                        .buttonStyle(InkPrimaryButtonStyle())
                        .disabled(
                            !VaultImportChrome.canApply(
                                canPrepare: model.report.canPrepare, isWriting: isWriting)
                        )
                        .accessibilityIdentifier("button.vaultImport.apply")
                        .inkListRow()
                    Button("Atla") { Task { await store.finishImport(model) } }
                        .buttonStyle(InkTextButtonStyle())
                        .accessibilityIdentifier("button.vaultImport.skip")
                        .inkListRow()
                }
                .disabled(isWriting)
            }
            if model.isApplying {
                InkProgress(kind: .indeterminate(label: "Kasa hazırlanıyor…"))
                    .inkListRow()
            }
            // With a result these rows sit under "Kasayı aç" instead (see `resultSection`).
            if model.result == nil {
                statusRows
            }
        }
        .listStyle(.plain)
        .inkToggle()
        .inkPageColumn()
        .inkPage()
        .interactiveDismissDisabled(
            VaultImportChrome.blocksInteractiveDismiss(
                hasResult: model.result != nil, isWriting: isWriting, openFailed: openFailed))
    }

    /// Indexing progress and the store's error, next to the button that caused them.
    @ViewBuilder private var statusRows: some View {
        if store.isProcessing {
            VaultIndexingProgress(store: store)
                .inkListRow()
        }
        if let error = store.errorText {
            Text(verbatim: error)
                .font(.ink.meta)
                .foregroundStyle(Color.ink.danger)
                .inkListRow()
        }
    }

    /// What the preparation wrote, and what it could not: directly under the manşet.
    private func resultSection(_ result: VaultImportResult) -> some View {
        Section {
            SectionHeader(title: String(localized: "Hazırlama sonucu"))
                .inkListRow()
            labeled("Oluşturulan öğeler", result.created.count)
            labeled("Tür eklenen dosyalar", result.typed.count)
            DisclosureGroup("Atlananlar") {
                ForEach(result.skipped, id: \.self) { path in
                    Text(verbatim: path)
                        .font(.ink.meta)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            .inkListRow()
            DisclosureGroup("Tamamlanamayanlar", isExpanded: $showsFailures) {
                ForEach(result.failures, id: \.self) { path in
                    Text(verbatim: path)
                        .font(.ink.meta)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            .inkListRow()
            Button("Kasayı aç") { Task { await store.finishImport(model) } }
                .buttonStyle(InkPrimaryButtonStyle())
                .disabled(store.isProcessing)
                .accessibilityIdentifier("button.vaultImport.open")
                .inkListRow()
            statusRows
        }
    }

    private func labeled(_ title: LocalizedStringKey, _ value: Int) -> some View {
        LabeledContent(title) {
            Text(value, format: .number)
                .font(.ink.value)
                .monospacedDigit()
        }
        .inkListRow()
    }
}
