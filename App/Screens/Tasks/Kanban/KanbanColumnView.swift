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

    /// The phone board draws no column box: the header and the cards sit on the page
    /// (Şafak drawing); a desktop column keeps its box, which also shows a drop target.
    private var isBoxed: Bool { KanbanBoardStyle.resolve(shell: shellKind) == .desktop }

    private var content: some View {
        VStack(alignment: .leading, spacing: isBoxed ? 12 : 4) {
            columnHeader
                .padding(.horizontal, isBoxed ? 12 : 4)
                .padding(.top, isBoxed ? 12 : 0)
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
                }.padding(isBoxed ? 10 : 4)
            }
            .scrollClipDisabled(!isBoxed)
        }
        .frame(maxHeight: .infinity)
        .background {
            if isBoxed {
                RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
                    .fill(targeted ? Color.ink.well : Color.ink.paper)
            }
        }
        .overlay {
            if isBoxed {
                RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
                    .stroke(
                        targeted ? Color.ink.accent : Color.ink.rule,
                        lineWidth: targeted ? InkStroke.highPriority : InkStroke.control)
            }
        }
    }

    @ViewBuilder private var columnHeader: some View {
        if isBoxed {
            SectionHeader(title: columnTitle, count: column.rows.count)
        } else {
            // Phone: state icon, name and a count capsule ("○ Yapılacak 4").
            HStack(spacing: 6) {
                if let icon = statusIcon {
                    Image(systemName: icon)
                        .font(.ink.meta.weight(.semibold))
                        .foregroundStyle(.ink.secondaryText)
                        .accessibilityHidden(true)
                }
                Text(verbatim: columnTitle)
                    .font(.ink.section)
                    .foregroundStyle(.ink.text)
                    .lineLimit(1)
                TasksCountPill(count: column.rows.count)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }

    private var columnTitle: String {
        if let name = column.name { return name }
        switch column.destination {
        case .status(.todo), .status(.unknown): return String(localized: "Yapılacak")
        case .status(.inProgress): return String(localized: "Devam")
        case .status(.done): return String(localized: "Bitti")
        case .status(.cancelled): return String(localized: "İptal")
        case .project: return String(localized: "Projesiz")
        case .person: return String(localized: "Kişisiz")
        }
    }

    /// Status columns carry their state's mark; project and person columns have none.
    private var statusIcon: String? {
        switch column.destination {
        case .status(.todo), .status(.unknown): return "circle"
        case .status(.inProgress): return "circle.lefthalf.filled"
        case .status(.done): return "checkmark.circle"
        case .status(.cancelled): return "xmark.circle"
        case .project, .person: return nil
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
