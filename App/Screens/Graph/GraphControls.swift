import SwiftUI

struct GraphControls: View {
    let maximumWeight: Int
    @Binding var filter: GraphFilter
    @Binding var zoom: Double
    @Binding var pan: CGSize
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            periodMenu
            weightRow
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
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

    private var weightLabel: some View {
        Text("En az \(filter.minimumWeight) ortak gün")
            .font(.ink.meta)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var weightStepper: some View {
        #if os(macOS)
            HStack(spacing: 4) {
                Button {
                    if filter.minimumWeight > 1 {
                        filter.minimumWeight -= 1
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.ink.meta)
                        .foregroundStyle(filter.minimumWeight > 1 ? Color.ink.accent : Color.ink.control)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(filter.minimumWeight <= 1)

                Button {
                    if filter.minimumWeight < max(maximumWeight, filter.minimumWeight) {
                        filter.minimumWeight += 1
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.ink.meta)
                        .foregroundStyle(
                            filter.minimumWeight < max(maximumWeight, filter.minimumWeight)
                                ? Color.ink.accent : Color.ink.control
                        )
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(filter.minimumWeight >= max(maximumWeight, filter.minimumWeight))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("En az \(filter.minimumWeight) ortak gün"))
            .accessibilityValue(Text("\(filter.minimumWeight)"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    if filter.minimumWeight < max(maximumWeight, filter.minimumWeight) {
                        filter.minimumWeight += 1
                    }
                case .decrement:
                    if filter.minimumWeight > 1 {
                        filter.minimumWeight -= 1
                    }
                @unknown default:
                    break
                }
            }
        #else
            Stepper(
                value: $filter.minimumWeight,
                in: 1...max(maximumWeight, filter.minimumWeight)
            ) {
                EmptyView()
            }
            .labelsHidden()
            .accessibilityLabel(
                Text("En az \(filter.minimumWeight) ortak gün"))
        #endif
    }

    @ViewBuilder private var weightRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                weightLabel
                weightStepper
            }
        } else {
            HStack(alignment: .center, spacing: 8) {
                weightLabel
                Spacer(minLength: 8)
                weightStepper
            }
        }
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

/// Node-kind filter on the manşet row: a menu of three switches (people, places, days).
/// The icon turns accent while the choice differs from the default filter.
struct GraphFilterMenu: View {
    @Binding var filter: GraphFilter

    /// Pure rule (unit-tested): only the node kinds count, not period or weight.
    static func isActive(_ filter: GraphFilter) -> Bool {
        let standard = GraphFilter()
        return filter.people != standard.people || filter.places != standard.places
            || filter.days != standard.days
    }

    var body: some View {
        InkHeaderMenu(
            "Filtre", systemImage: "line.3.horizontal.decrease", isActive: Self.isActive(filter),
            identifier: "menu.graph.filter"
        ) {
            Group {
                Toggle("Kişiler", isOn: $filter.people)
                Toggle("Konumlar", isOn: $filter.places)
                Toggle("Günler", isOn: $filter.days)
            }
            // Several kinds are usually switched in one go: keep the menu open (iOS only API).
            #if os(iOS)
                .menuActionDismissBehavior(.disabled)
            #endif
        }
    }
}
