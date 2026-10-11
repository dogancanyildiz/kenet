import SwiftUI

/// Summary and result sheet for importing contacts selected from Contacts.
///
/// The import is not a save, so its button lives in the page and the bar keeps only "Vazgeç";
/// once the result is in, the bar keeps only "Kapat".
struct ContactImportView: View {
    let model: ContactImportModel
    let onDismiss: () -> Void

    var body: some View {
        Group {
            if model.result != nil {
                page.inkSheet(
                    "Aktarma sonucu", closeIdentifier: "button.contactImport.close", onClose: onDismiss)
            } else {
                page.inkSheet(
                    "Rehberden aktar", cancelIdentifier: "button.contactImport.cancel",
                    isCancelEnabled: !model.isImporting, onCancel: onDismiss)
            }
        }
        // A swipe must not hide a write in flight: the result names what was left out.
        .interactiveDismissDisabled(model.isImporting)
    }

    private var page: some View {
        List {
            if let result = model.result {
                InkPageTitleRow("Aktarma sonucu")
                names("Oluşturulan", result.created, identifier: "contactImport.created")
                names("Atlanan", result.skipped, identifier: "contactImport.skipped")
                names("Hata veren", result.failed, identifier: "contactImport.failed", isFailure: true)
            } else {
                InkPageTitleRow("Rehberden aktar")
                if let plan = model.plan, !plan.isEmpty {
                    planSections(plan)
                } else {
                    EmptyState("Seçilen kişi bulunamadı.")
                        .inkListRow()
                }
            }
        }
        .listStyle(.plain)
        .inkPage()
        .inkPageScrollColumn()
    }

    @ViewBuilder
    private func planSections(_ plan: ContactImportPlan) -> some View {
        if !plan.toCreate.isEmpty {
            SectionHeader("Oluşturulacak kişiler", count: plan.toCreate.count)
                .inkListRow()
            ForEach(plan.toCreate) { item in
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: item.name)
                        .font(.body)
                        .foregroundStyle(Color.ink.text)
                    if let alias = item.aliases.first {
                        Text(verbatim: alias)
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                    }
                }
                .accessibilityElement(children: .combine)
                .inkListRow()
            }
        }
        names("Zaten var olanlar (atlanacak)", plan.alreadyExists.map(\.name), identifier: "contactImport.existing")
        names(
            "Geçersiz adlar",
            plan.invalid.map { $0.name.isEmpty ? String(localized: "(Boş ad)") : $0.name },
            identifier: "contactImport.invalid")

        if model.isImporting {
            InkProgress(kind: .indeterminate(label: "Kişiler aktarılıyor…"))
                .inkListRow()
        }
        Button("İçe aktar") {
            Task { await model.importContacts() }
        }
        .buttonStyle(InkPrimaryButtonStyle())
        .disabled(plan.toCreate.isEmpty || model.isImporting)
        .accessibilityIdentifier("button.contactImport.apply")
        .inkListRow()
    }

    /// A counted section of names; nothing is drawn for an empty list.
    @ViewBuilder
    private func names(
        _ title: LocalizedStringKey, _ names: [String], identifier: String, isFailure: Bool = false
    ) -> some View {
        if !names.isEmpty {
            SectionHeader(title, count: names.count)
                .accessibilityIdentifier(identifier)
                .inkListRow()
            ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                Text(verbatim: name)
                    .font(.body)
                    .foregroundStyle(isFailure ? Color.ink.danger : Color.ink.secondaryText)
                    .inkListRow()
            }
        }
    }
}
