import SwiftUI

struct GraphControls: View {
    @Binding var filter: GraphFilter
    @Binding var zoom: Double
    @Binding var pan: CGSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // A day's own graph is the whole day: no period.
            if filter.scope == .all {
                periodMenu
            }
            zoomBar
        }
        .padding(.horizontal, InkSpacing.margin)
        .padding(.vertical, InkSpacing.margin)
    }

    /// Four choices: labeled menu, left-aligned under the manşet.
    private var periodMenu: some View {
        InkLabeledMenu(
            "Dönem", selection: $filter.period,
            options: [
                InkMenuOption("Son 30 gün", value: GraphPeriod.month),
                InkMenuOption("Son 90 gün", value: GraphPeriod.quarter),
                InkMenuOption("Son 365 gün", value: GraphPeriod.year),
                InkMenuOption("Tümü", value: GraphPeriod.all),
            ], identifier: "menu.graph.period")
    }

    private var zoomBar: some View {
        HStack(spacing: 4) {
            Button {
                zoom = max(0.2, zoom / 1.25)
            } label: {
                Label("Uzaklaştır", systemImage: "minus.magnifyingglass")
                    .foregroundStyle(Color.ink.accent)
                    .tapTarget()
            }
            Button {
                zoom = min(5, zoom * 1.25)
            } label: {
                Label("Yakınlaştır", systemImage: "plus.magnifyingglass")
                    .foregroundStyle(Color.ink.accent)
                    .tapTarget()
            }
            Button {
                zoom = 1
                pan = .zero
            } label: {
                Label("Ortala", systemImage: "scope")
                    .foregroundStyle(Color.ink.accent)
                    .tapTarget()
            }
            Spacer(minLength: 0)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }
}

/// Node-kind filter on the manşet row: a menu of switches (people, places, then one per custom
/// type of the vault); days are always drawn. The icon turns accent while the choice differs from the default filter.
struct GraphFilterMenu: View {
    @Binding var filter: GraphFilter
    /// The vault's custom types, in catalog order.
    var types: [EntityTypeChoice] = []

    /// Pure rule (unit-tested): only the entity kinds count, not the period.
    static func isActive(_ filter: GraphFilter) -> Bool {
        let standard = GraphFilter()
        return filter.people != standard.people || filter.places != standard.places
            || filter.customTypes != standard.customTypes
    }

    var body: some View {
        InkHeaderMenu(
            "Filtre", systemImage: "line.3.horizontal.decrease", isActive: Self.isActive(filter),
            identifier: "menu.graph.filter"
        ) {
            Group {
                Toggle("Kişiler", isOn: $filter.people)
                Toggle("Konumlar", isOn: $filter.places)
                if !types.isEmpty {
                    Section {
                        ForEach(types) { type in
                            Toggle(
                                isOn: Binding(
                                    get: { filter.showsCustomType(type.id) },
                                    set: { filter.setCustomType(type.id, $0) })
                            ) {
                                Text(verbatim: type.plural)
                            }
                        }
                    }
                }
            }
            // Several kinds are usually switched in one go: keep the menu open (iOS only API).
            #if os(iOS)
                .menuActionDismissBehavior(.disabled)
            #endif
        }
    }
}
