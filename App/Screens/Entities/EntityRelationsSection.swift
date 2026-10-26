import SwiftUI

struct EntityRelationsSection: View {
    let model: EntityRelationsModel
    @State private var isAdding = false
    @Environment(\.locale) private var locale

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
                    Text("Bağ kur")
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
                        EntityRelationCopy.text(for: row, locale: locale)
                            .font(.ink.content)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityLabel(EntityRelationCopy.text(for: row, locale: locale))
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

/// Catalog resources are resolved by Text in the view's environment, never by the model.
enum EntityRelationCopy {
    static func text(for row: EntityRelationRow, locale: Locale) -> Text {
        if row.isOutgoing {
            if let label = row.relation.label { return Text("\(label) · \(row.name)") }
            return Text(verbatim: row.name)
        }
        let page = Text(incomingPage(row.name, locale: locale))
        if let label = row.relation.label { return Text("\(page) · \(label)") }
        return page
    }

    static func incomingPage(
        _ name: String, locale: Locale = .current, bundle: LocalizedStringResource.BundleDescription = .main
    ) -> LocalizedStringResource {
        func page(_ value: String.LocalizationValue) -> LocalizedStringResource {
            LocalizedStringResource(value, locale: locale, bundle: bundle)
        }
        let letters = name.lowercased(with: Locale(identifier: "tr_TR"))
        let lastVowel = letters.last { "aeıioöuü".contains($0) } ?? "ı"
        let vowelEnding = letters.last.map { "aeıioöuü".contains($0) } ?? false
        switch (lastVowel, vowelEnding) {
        case ("a", true), ("ı", true): return page("\(name)'nın sayfasında")
        case ("e", true), ("i", true): return page("\(name)'nin sayfasında")
        case ("o", true), ("u", true): return page("\(name)'nun sayfasında")
        case ("ö", true), ("ü", true): return page("\(name)'nün sayfasında")
        case ("e", false), ("i", false): return page("\(name)'in sayfasında")
        case ("o", false), ("u", false): return page("\(name)'un sayfasında")
        case ("ö", false), ("ü", false): return page("\(name)'ün sayfasında")
        default: return page("\(name)'ın sayfasında")
        }
    }
}
