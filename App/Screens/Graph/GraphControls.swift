import SwiftUI

struct GraphControls: View {
    let maximumWeight: Int
    @Binding var filter: GraphFilter
    @Binding var zoom: Double
    @Binding var pan: CGSize
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var stacksFilters: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if stacksFilters {
                VStack(alignment: .leading, spacing: 8) { filterChips }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { filterChips }
                    VStack(alignment: .leading, spacing: 8) { filterChips }
                }
            }
            Group {
                if stacksFilters {
                    VStack(alignment: .leading, spacing: 8) {
                        periodPicker
                        weightRow
                    }
                } else {
                    // Keep label + stepper as one unit; reflow both together when narrow.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            periodPicker
                            weightRow
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            periodPicker
                            weightRow
                        }
                    }
                }
            }
            .font(.ink.meta)
            .foregroundStyle(Color.ink.secondaryText)

            zoomBar
        }
        // Half control stroke: TagChip borders are centered on the frame, so plain
        // `InkSpacing.margin` places the visible chip edge ~1–2 pt outside the manşet.
        .padding(.horizontal, InkSpacing.margin + InkStroke.control / 2)
        .padding(.vertical, InkSpacing.margin)
    }

    @ViewBuilder private var filterChips: some View {
        TagChip(
            title: String(localized: "Kişiler"),
            isSelected: filter.people,
            onTap: { filter.people.toggle() }
        )
        TagChip(
            title: String(localized: "Konumlar"),
            isSelected: filter.places,
            onTap: { filter.places.toggle() }
        )
        TagChip(
            title: String(localized: "Günler"),
            isSelected: filter.days,
            onTap: { filter.days.toggle() }
        )
    }

    private var periodPicker: some View {
        Picker("Tarih aralığı", selection: $filter.period) {
            Text("Son 30 gün").tag(GraphPeriod.month)
            Text("Son 90 gün").tag(GraphPeriod.quarter)
            Text("Son 365 gün").tag(GraphPeriod.year)
            Text("Tümü").tag(GraphPeriod.all)
        }
    }

    private var weightLabel: some View {
        Text("En az \(filter.minimumWeight) ortak gün")
            .font(.ink.meta)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var weightStepper: some View {
        Stepper(
            value: $filter.minimumWeight,
            in: 1...max(maximumWeight, filter.minimumWeight)
        ) {
            EmptyView()
        }
        .labelsHidden()
        .accessibilityLabel(
            Text("En az \(filter.minimumWeight) ortak gün"))
    }

    private var weightRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            weightLabel
            weightStepper
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
