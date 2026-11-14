import SwiftUI

struct EntityRelationsSection: View {
    let model: EntityRelationsModel
    @State private var isAdding = false

    enum RemoveAction: Hashable { case remove }

    static func removeActions(for row: EntityRelationRow, canWrite: Bool) -> [RemoveAction] {
        row.canRemove && canWrite ? [.remove] : []
    }

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SectionHeader("Bağlar")
                Button {
                    model.clearSheetError()
                    isAdding = true
                } label: {
                    // A small link beside the section title (drawing), not a title-sized one:
                    // the text button style's own font is the larger byline.
                    Text("Bağ kur")
                        .font(.subheadline.weight(.semibold))
                        .tapTarget()
                }
                .buttonStyle(InkTextButtonStyle())
                .disabled(!model.canWrite)
                .accessibilityIdentifier("button.addRelation")
            }
            .inkListRow()
            ForEach(model.rows) { row in
                if let entity = model.store.content.entities.first(where: { $0.id == row.path }) {
                    NavigationLink {
                        EntityView(store: model.store, entity: entity)
                    } label: {
                        EntityRelationCopy.text(for: row)
                            .font(.ink.content)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityLabel(EntityRelationCopy.text(for: row))
                    .accessibilityIdentifier("row.relation." + row.path)
                    .accessibilityActions {
                        ForEach(Self.removeActions(for: row, canWrite: model.canWrite), id: \.self) { _ in
                            Button("Bağı kaldır", role: .destructive) { Task { await model.remove(row) } }
                        }
                    }
                    .contextMenu {
                        if !Self.removeActions(for: row, canWrite: model.canWrite).isEmpty {
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

/// Both ends of a relation read alike: the other page's name, never the direction. The label
/// keeps its side of the name, since it describes the source's view of the target ("eşi · Selin"
/// on the source, "Mert · iş arkadaşı" on the target).
enum EntityRelationCopy {
    static func text(for row: EntityRelationRow) -> Text {
        guard let label = row.relation.label else { return Text(verbatim: row.name) }
        return row.isOutgoing ? Text("\(label) · \(row.name)") : Text("\(row.name) · \(label)")
    }
}
