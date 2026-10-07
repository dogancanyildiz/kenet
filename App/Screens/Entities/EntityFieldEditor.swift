import SwiftUI
import VaultFormat

struct EntityFieldEditor: View {
    let field: EntityField
    let model: EntityDetailModel
    @Environment(\.entityEditorDraft) private var draft
    @State private var deleteConfirmation = DestructiveConfirmation<DestructiveConfirmationToken>()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: field.key).font(.ink.section).foregroundStyle(.ink.text)
            switch field.value {
            case .scalar(let value):
                EntityScalarEditor(draftID: "field:" + field.key, scalar: value) {
                    await model.set(field.key, to: $0)
                }
            case .list(let values, _):
                ForEach(values.indices, id: \.self) { index in
                    EntityScalarEditor(
                        draftID: "field:" + field.key + "." + String(index), scalar: values[index]
                    ) { newValue in
                        var literals = values.map(Self.literal)
                        literals[index] = newValue
                        return await model.setList(field.key, values: literals)
                    }.id(values[index])
                }
            case .mapping(let entries):
                ForEach(entries.indices, id: \.self) { index in
                    let entry = entries[index]
                    Text(verbatim: entry.key).font(.ink.meta).foregroundStyle(.ink.secondaryText)
                    EntityScalarEditor(
                        draftID: "field:" + field.key + "." + entry.key, scalar: entry.value
                    ) {
                        await model.setEntry(field.key, entry: entry.key, value: $0)
                    }
                    .id(entry.value)
                }
            case .raw(let text):
                Text(verbatim: text).font(.ink.content).foregroundStyle(.ink.text).textSelection(.enabled)
                Text("Ham alan — salt okunur").font(.ink.meta).foregroundStyle(.ink.secondaryText)
            }
            if case .raw = field.value {
            } else {
                HStack(spacing: InkSpacing.margin) {
                    Button("Değeri boş bırak") { Task { await model.set(field.key, to: .text("")) } }
                        .buttonStyle(InkTextButtonStyle())
                    Button("Alanı kaldır", role: .destructive) { deleteConfirmation.request(.pending) }
                        .buttonStyle(InkDestructiveButtonStyle())
                }
            }
        }
        // Row default for a List row with several buttons; the word buttons carry ink styles.
        .buttonStyle(.borderless)
        .disabled(!model.canEdit)
        .destructiveConfirmationDialog(
            "Alanı kaldır?", confirmation: $deleteConfirmation, confirmTitle: "Alanı kaldır"
        ) { _ in
            Task {
                if await model.remove(field.key) {
                    draft?.clear(ids: Self.draftIDs(for: field))
                }
            }
        }
    }

    /// Exact draft ids owned by this field (scalar, list indices, or mapping keys).
    private static func draftIDs(for field: EntityField) -> [String] {
        let base = "field:" + field.key
        switch field.value {
        case .list(let values, _):
            return [base] + values.indices.map { base + "." + String($0) }
        case .mapping(let entries):
            return [base] + entries.map { base + "." + $0.key }
        case .scalar, .raw:
            return [base]
        }
    }

    private static func literal(_ scalar: FrontmatterScalar) -> FrontmatterLiteral {
        switch scalar.kind {
        case .text, .empty: .text(scalar.text)
        case .number: .number(scalar.raw)
        case .boolean(let value): .boolean(value)
        case .date(let day): .date(day)
        }
    }
}
