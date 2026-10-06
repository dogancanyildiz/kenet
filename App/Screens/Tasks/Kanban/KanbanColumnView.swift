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
            SectionHeader(title: column.localizedTitle, count: column.rows.count)
                .padding(.horizontal, 12)
                .padding(.top, 12)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(column.rows) { row in
                        KanbanCard(model: model, row: row) { select(row) }
                    }
                    if column.rows.isEmpty {
                        EmptyState("Görev yok.")
                            .padding()
                    }
                }.padding(10)
            }
        }
        .frame(maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
                .fill(targeted ? Color.ink.well : Color.ink.paper)
        }
        .overlay {
            RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
                .stroke(
                    targeted ? Color.ink.accent : Color.ink.rule,
                    lineWidth: targeted ? InkStroke.highPriority : InkStroke.control)
        }
    }
}
