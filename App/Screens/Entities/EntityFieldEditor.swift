import SwiftUI
import VaultFormat

struct EntityFieldEditor: View {
    let field: EntityField
    let model: EntityDetailModel
    @State private var deleteConfirmation = DestructiveConfirmation<DestructiveConfirmationToken>()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: field.key).font(.headline)
            switch field.value {
            case .scalar(let value):
                EntityScalarEditor(scalar: value) { await model.set(field.key, to: $0) }
            case .list(let values, _):
                ForEach(values.indices, id: \.self) { index in
                    EntityScalarEditor(scalar: values[index]) { newValue in
                        var literals = values.map(Self.literal)
                        literals[index] = newValue
                        await model.setList(field.key, values: literals)
                    }.id(values[index])
                }
            case .mapping(let entries):
                ForEach(entries.indices, id: \.self) { index in
                    let entry = entries[index]
                    Text(verbatim: entry.key).font(.caption)
                    EntityScalarEditor(scalar: entry.value) {
                        await model.setEntry(field.key, entry: entry.key, value: $0)
                    }
                    .id(entry.value)
                }
            case .raw(let text):
                Text(verbatim: text).textSelection(.enabled)
                Text("Ham alan — salt okunur").font(.caption).foregroundStyle(.secondary)
            }
            if case .raw = field.value {
            } else {
                HStack {
                    Button("Değeri boş bırak") { Task { await model.set(field.key, to: .text("")) } }
                    Button("Alanı kaldır", role: .destructive) { deleteConfirmation.request(.pending) }
                }.font(.caption).buttonStyle(.borderless)
            }
        }
        .disabled(!model.canEdit)
        .destructiveConfirmationDialog(
            "Alanı kaldır?", confirmation: $deleteConfirmation, confirmTitle: "Alanı kaldır"
        ) { _ in
            Task { await model.remove(field.key) }
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
