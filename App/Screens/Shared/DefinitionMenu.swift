import GoalTracking
import SwiftUI
import VaultFormat

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

enum DefinitionMenuItem: String, Hashable {
    case edit, copyLink, delete, markToday, enterAmount, unmark

    var title: LocalizedStringKey {
        switch self {
        case .edit: "Düzenle"
        case .copyLink: "Bağlantıyı kopyala"
        case .delete: "Sil"
        case .markToday: "Bugünü işaretle"
        case .enterAmount: "Miktar gir"
        case .unmark: "İşareti kaldır"
        }
    }

    var symbol: String {
        switch self {
        case .edit: "pencil"
        case .copyLink: "link"
        case .delete: "trash"
        case .markToday: "checkmark.circle"
        case .enterAmount: "number"
        case .unmark: "minus.circle"
        }
    }

    var group: Int {
        switch self {
        case .copyLink: 1
        case .delete: 2
        default: 0
        }
    }
}

/// Menu composition is independent of views, selection and file writes.
enum DefinitionMenu {
    static func items(forEntity entity: EntitySummary) -> [DefinitionMenuItem] {
        [.edit, .copyLink, .delete]
    }

    static func items(forGoal kind: GoalKind, markedToday: Bool) -> [DefinitionMenuItem] {
        switch kind {
        case .boolean: [markedToday ? .unmark : .markToday, .edit, .delete]
        case .number: [.enterAmount, .edit, .delete]
        case .milestone: [.edit, .delete]
        }
    }

    static func link(for name: String) -> String { "[[\(name)]]" }

    @MainActor static func copyLink(for name: String) {
        let link = link(for: name)
        #if os(iOS)
            UIPasteboard.general.string = link
        #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link, forType: .string)
        #endif
    }
}

struct DefinitionMenuButtons: View {
    let items: [DefinitionMenuItem]
    let canEdit: Bool
    let action: (DefinitionMenuItem) -> Void

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.element) { index, item in
            if index > 0, items[index - 1].group != item.group { Divider() }
            Button(role: item == .delete ? .destructive : nil) {
                action(item)
            } label: {
                Label(item.title, systemImage: item.symbol)
            }
            .disabled(item != .copyLink && !canEdit)
            .accessibilityIdentifier("button.definition.\(item.rawValue)")
        }
    }
}

extension View {
    func entityDefinitionActions(
        store: IndexStore, editing: Binding<EntitySummary?>,
        onRenamed: @escaping (String, String) -> Void = { _, _ in },
        onDeleted: @escaping (String) -> Void = { _ in }
    ) -> some View {
        modifier(EntityDefinitionActions(store: store, editing: editing, onRenamed: onRenamed, onDeleted: onDeleted))
    }
}

/// Both list shells share the same row editor and selection callbacks.
private struct EntityDefinitionActions: ViewModifier {
    let store: IndexStore
    @Binding var editing: EntitySummary?
    let onRenamed: (String, String) -> Void
    let onDeleted: (String) -> Void

    func body(content: Content) -> some View {
        content.sheet(item: $editing) { entity in
            EntityRowEditor(store: store, entity: entity, onRenamed: onRenamed, onDeleted: onDeleted)
        }
    }
}

private struct EntityRowEditor: View {
    let store: IndexStore
    let entity: EntitySummary
    let onRenamed: (String, String) -> Void
    let onDeleted: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var model: EntityDetailModel
    @State private var deletion = DefinitionDeletionModel()

    init(
        store: IndexStore, entity: EntitySummary,
        onRenamed: @escaping (String, String) -> Void, onDeleted: @escaping (String) -> Void
    ) {
        self.store = store
        self.entity = entity
        self.onRenamed = onRenamed
        self.onDeleted = onDeleted
        _model = State(initialValue: EntityDetailModel(store: store, path: entity.id))
    }

    var body: some View {
        Group {
            if model.isLoaded {
                EntityEditSheet(
                    store: store, model: model,
                    entity: store.content.entities.first { $0.id == model.path } ?? entity, deletion: deletion)
            } else {
                NavigationStack {
                    List {
                        if let error = model.errorText {
                            InfoBand(kind: .error, verbatim: error)
                        } else {
                            ProgressView("Yükleniyor…")
                        }
                    }
                    .inkSheet("Düzenle", onClose: { dismiss() })
                }
            }
        }
        .task { await model.load() }
        .onChange(of: model.path) { old, path in onRenamed(old, path) }
        .onChange(of: deletion.isDeleted) { _, deleted in
            if deleted { onDeleted(model.path) }
        }
    }
}
