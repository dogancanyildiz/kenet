import SwiftUI

struct EntityRelationsSection: View {
    let model: EntityRelationsModel
    @State private var isAdding = false

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SectionHeader("Bağlar")
                Button("Bağ kur") { isAdding = true }
                    .buttonStyle(InkTextButtonStyle())
                    .foregroundStyle(Color.ink.accent)
                    .tapTarget()
                    .disabled(!model.canWrite)
                    .accessibilityIdentifier("button.addRelation")
            }
            .inkListRow()
            ForEach(model.rows) { row in
                if let entity = model.store.content.entities.first(where: { $0.id == row.path }) {
                    NavigationLink {
                        EntityView(store: model.store, entity: entity)
                    } label: {
                        Text(verbatim: row.text)
                            .font(.ink.content)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("row.relation." + row.path)
                    .contextMenu {
                        if row.canRemove {
                            Button("Bağı kaldır", role: .destructive) { Task { await model.remove(row) } }
                                .disabled(!model.canWrite)
                        }
                    }
                    .inkListRow()
                }
            }
            if let error = model.errorText { InfoBand(kind: .error, verbatim: error).inkListRow() }
        }
        .sheet(isPresented: $isAdding) { EntityRelationSheet(model: model) }
    }
}
