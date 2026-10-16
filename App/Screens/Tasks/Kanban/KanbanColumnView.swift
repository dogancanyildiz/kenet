import SwiftUI

struct KanbanColumnView: View {
    let model: KanbanModel
    let column: KanbanColumn
    /// The card being dragged on the touch board (``KanbanDropLanding/draggedRow(in:columns:)``).
    let dragged: TaskRow?
    let select: (TaskRow) -> Void
    @State private var targeted = false
    @Environment(\.shellKind) private var shellKind

    var body: some View {
        #if os(macOS)
            dropTarget
        #else
            if KanbanBoardStyle.resolve(shell: shellKind).dragsCards { dropTarget } else { content }
        #endif
    }

    private var dropTarget: some View {
        content.dropDestination(for: String.self) { tokens, _ in
            guard tokens.count == 1, let token = tokens.first, model.acceptsDrop(token, into: column) else {
                return false
            }
            Task { await model.drop(token, into: column) }
            return true
        } isTargeted: {
            targeted = $0 && model.grouping != .person
        }
    }

    /// Touch only (`dragged` is `nil` on Mac): where the card being dragged over this column will
    /// land. The Mac board marks the column alone.
    private var landing: KanbanDropLanding? {
        guard targeted, let dragged else { return nil }
        return KanbanDropLanding.resolve(dragged, over: column, in: model)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            columnHeader
                .padding(.horizontal, 12)
                .padding(.top, 12)
            ScrollView {
                LazyVStack(spacing: 10) {
                    let landing = landing
                    ForEach(Array(column.rows.enumerated()), id: \.element.id) { index, row in
                        if landing?.index == index { KanbanDropMarker() }
                        KanbanCard(model: model, row: row) { select(row) }
                    }
                    if let landing, landing.index >= column.rows.count { KanbanDropMarker() }
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

    @ViewBuilder private var columnHeader: some View {
        if let name = column.name {
            SectionHeader(title: name, count: column.rows.count)
        } else {
            switch column.destination {
            case .status(.todo), .status(.unknown):
                SectionHeader("Yapılacak", count: column.rows.count)
            case .status(.inProgress):
                SectionHeader("Devam", count: column.rows.count)
            case .status(.done):
                SectionHeader("Bitti", count: column.rows.count)
            case .status(.cancelled):
                SectionHeader("İptal", count: column.rows.count)
            case .project:
                SectionHeader("Projesiz", count: column.rows.count)
            case .person:
                SectionHeader("Kişisiz", count: column.rows.count)
            }
        }
    }
}

/// The accent rule a touch drag shows where the card will land (``KanbanDropLanding``).
private struct KanbanDropMarker: View {
    var body: some View {
        Capsule()
            .fill(Color.ink.accent)
            .frame(height: InkStroke.highPriority * 2)
            .accessibilityHidden(true)
    }
}
