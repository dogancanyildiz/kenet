import SwiftUI

struct KanbanColumnView: View {
    let model: KanbanModel
    let column: KanbanColumn
    let select: (TaskRow) -> Void
    @State private var targeted = false

    var body: some View {
        #if os(macOS)
            content.dropDestination(for: String.self) { tokens, _ in
                guard tokens.count == 1, let token = tokens.first, model.acceptsDrop(token, into: column) else {
                    return false
                }
                Task { await model.drop(token, into: column) }
                return true
            } isTargeted: {
                targeted = $0 && model.grouping != .person
            }
        #else
            content
        #endif
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                column.title.font(.headline)
                Spacer()
                Text(column.rows.count.formatted()).font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 12).padding(.top, 12)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(column.rows) { row in
                        KanbanCard(model: model, row: row) { select(row) }
                    }
                    if column.rows.isEmpty { Text("Görev yok.").foregroundStyle(.secondary).padding() }
                }.padding(10)
            }
        }
        .frame(maxHeight: .infinity)
        .background(.quaternary.opacity(targeted ? 0.5 : 0.2), in: RoundedRectangle(cornerRadius: 14))
        .overlay { if targeted { RoundedRectangle(cornerRadius: 14).stroke(.tint, lineWidth: 2) } }
    }
}
