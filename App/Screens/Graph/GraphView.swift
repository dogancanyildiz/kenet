import SwiftUI
import VaultFormat

struct GraphView: View {
    let store: IndexStore
    /// `false` shows the settled layout without animating it (image tests need a fixed picture).
    let liveMotion: Bool
    @State private var model: GraphScreenModel
    @Environment(\.clockNow) private var clockNow
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    /// - Parameters:
    ///   - focus: The node selected and framed first. A custom type entity switches its type on.
    ///   - scope: `.day` draws that day's own graph (the day page's Graph icon).
    init(store: IndexStore, focus: String? = nil, scope: GraphScope = .all, liveMotion: Bool = true) {
        self.store = store
        self.liveMotion = liveMotion
        _model = State(
            initialValue: GraphScreenModel(
                store: store, focus: focus,
                filter: Self.initialFilter(
                    scope: scope,
                    focusKind: focus.flatMap { id in
                        store.content.entities.first { $0.id == id }?.kind
                    })))
    }

    /// The filter a graph opens with: the default, in `scope`; a focused custom type entity's
    /// type is switched on so its node is there (custom types are off by default).
    static func initialFilter(scope: GraphScope, focusKind: String?) -> GraphFilter {
        var filter = GraphFilter()
        filter.scope = scope
        if let focusKind, case .custom(let type) = GraphNode.Kind(entityKind: focusKind) {
            filter.setCustomType(type, true)
        }
        return filter
    }

    private var day: CalendarDate? {
        if case .day(let date) = model.filter.scope { date } else { nil }
    }

    var body: some View {
        @Bindable var model = model
        // Reduce Motion: the layout settles out of sight and appears in one go.
        let live = liveMotion && !reduceMotion
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let today = LocalDay.today(at: clockNow())
            let canvasHeight: CGFloat = dynamicTypeSize.isAccessibilitySize ? 280 : 360
            let masthead = self.masthead
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        InkScrolledMasthead(masthead)
                        GraphControls(
                            maximumWeight: max(365, model.graph.edges.map(\.weight).max() ?? 1),
                            filter: $model.filter,
                            zoom: $model.zoom,
                            // The center control writes a zero pan: frame the layout as it is now.
                            pan: Binding(
                                get: { model.pan },
                                set: { if $0 == .zero { model.recenter() } else { model.pan = $0 } })
                        )
                        if model.isLoading {
                            InkProgress(kind: .indeterminate(label: "Yükleniyor…"))
                                .padding(.horizontal, InkSpacing.margin)
                        }
                        if model.graph.nodes.isEmpty && !model.isLoading {
                            EmptyState("Gösterilecek düğüm yok")
                        }
                    }
                    .inkPageColumn()

                    if !(model.graph.nodes.isEmpty && !model.isLoading) {
                        GraphCanvas(model: model)
                            .frame(height: canvasHeight)
                            .frame(maxWidth: .infinity)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        legendRow
                        if let node = model.graph.nodes.first(where: { $0.id == model.selected }) {
                            selectedRow(node)
                        }
                        explanation
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, InkSpacing.margin)
                            .padding(.bottom, 8)
                    }
                    .inkPageColumn()
                }
            }
            .inkPinnedMasthead(masthead)
            .inkPage()
            .task(
                id: String(describing: model.filter) + today.description
                    + String(describing: store.lastUpdated) + (store.vaultURL?.path ?? "") + String(live)
            ) {
                await model.load(today: today, live: live)
            }
        }
        .inkPageNavigationTitle(pageTitle)
        .accessibilityIdentifier(screenIdentifier)
        .onChange(of: store.vaultURL) { model.reset() }
    }

    private func selectedRow(_ node: GraphNode) -> some View {
        HStack {
            Text(verbatim: node.name)
                .font(.ink.content)
                .foregroundStyle(Color.ink.text)
            Spacer()
            if let date = node.date {
                // A day's own graph came from that day's page.
                if date != day {
                    NavigationLink("Sayfayı aç") { DayView(store: store, date: date) }
                }
            } else if let entity = store.content.entities.first(where: { $0.id == node.id }) {
                NavigationLink("Sayfayı aç") {
                    EntityView(store: store, entity: entity)
                }
            }
        }
        .padding(InkSpacing.margin)
    }

    /// The whole graph's manşet holds the kind filter; a day's graph names its day instead.
    private var masthead: InkPageTitle<some View> {
        InkPageTitle(pageTitle, byline: day.map { Self.byline($0, locale: locale) }) {
            if day == nil {
                GraphFilterMenu(filter: $model.filter, types: customTypes)
            }
            SearchButton()
        }
    }

    private var customTypes: [EntityTypeChoice] {
        EntityTypeChoices.choices(store.entityTypes).filter { !GraphInput.kinds.contains($0.id) }
    }

    static func byline(_ day: CalendarDate, locale: Locale) -> String {
        LocalDay.instant(for: day).formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(locale))
    }

    private var pageTitle: LocalizedStringKey { day == nil ? "Graph" : "Günün grafiği" }
    private var screenIdentifier: String { day == nil ? "screen.graph" : "screen.dayGraph" }

    private var explanation: Text {
        day == nil
            ? Text("Çizgiler aynı olayda geçen kayıtları ve elle kurulan bağları gösterir.")
            : Text(
                "Gün, o gün geçen her kayda bağlanır. Öteki çizgiler aynı olayda geçen kayıtları ve elle kurulan bağları gösterir."
            )
    }

    private var legendRow: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    legendMarks
                    nodeMenu
                }
            } else {
                // A day with a relation and a custom type is wider than an iPhone: the menu moves down.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        legendMarks
                        Spacer(minLength: 0)
                        nodeMenu
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) { legendMarks }
                        nodeMenu
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.ink.meta)
        .padding(.horizontal, InkSpacing.margin)
        .padding(.vertical, Self.legendPadding)
    }

    /// iPhone's node menu is a 44 pt target that already spaces the row.
    private static var legendPadding: CGFloat {
        #if os(iOS)
            0
        #else
            8
        #endif
    }

    @ViewBuilder private var legendMarks: some View {
        // Like custom types, the relation entry appears only when the graph draws one.
        if model.graph.edges.contains(where: { $0.kind == .relation }) {
            HStack(spacing: 4) {
                // Drawn in the edge's own colour (GraphCanvas): the sample stands for the line, not a control.
                Rectangle().fill(Color.ink.rule).frame(width: 18, height: InkStroke.highPriority)
                    .accessibilityHidden(true)
                Text("Bağ")
                    .foregroundStyle(Color.ink.secondaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .accessibilityElement(children: .combine)
        }
        legendMark(kind: .person, title: "Kişiler")
        legendMark(kind: .place, title: "Konumlar")
        if day != nil {
            legendMark(kind: .day, title: "Gün")
        } else if model.filter.days {
            legendMark(kind: .day, title: "Günler")
        }
        let types = GraphLegend.customTypeNames(
            in: model.graph, plurals: Dictionary(customTypes.map { ($0.id, $0.plural) }) { first, _ in first })
        if !types.isEmpty {
            HStack(spacing: 4) {
                GraphNodeShape(kind: .custom(""))
                    .fill(GraphNodeStyle.fill(.custom("")))
                    .frame(width: 10, height: 10)
                Text(verbatim: types.joined(separator: ", "))
                    .foregroundStyle(Color.ink.secondaryText)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var nodeMenu: some View {
        #if os(macOS)
            Menu {
                ForEach(model.graph.nodes) { node in
                    Button {
                        model.select(node.id, recenter: true)
                    } label: {
                        Text(verbatim: node.name)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Düğüm seç")
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .font(.ink.meta)
            .foregroundStyle(Color.ink.accent)
        #else
            Menu {
                ForEach(model.graph.nodes) { node in
                    Button {
                        model.select(node.id, recenter: true)
                    } label: {
                        Text(verbatim: node.name)
                    }
                }
            } label: {
                // The 44 pt target sets the legend row's height on iPhone (no extra row padding).
                Text("Düğüm seç")
                    .tapTarget()
            }
            .font(.ink.meta)
            .foregroundStyle(Color.ink.accent)
        #endif
    }

    private func legendMark(kind: GraphNode.Kind, title: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            GraphNodeShape(kind: kind)
                .fill(GraphNodeStyle.fill(kind))
                .frame(width: 10, height: 10)
            Text(title)
                .foregroundStyle(Color.ink.secondaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Legend entries the graph on screen needs beyond people, places and days.
enum GraphLegend {
    /// The custom types with a node in `graph`, by plural name (else the node's type name), in
    /// name order.
    static func customTypeNames(in graph: GraphModel, plurals: [String: String] = [:]) -> [String] {
        Set(
            graph.nodes.compactMap { node -> String? in
                guard case .custom(let type) = node.kind else { return nil }
                return plurals[type] ?? node.typeName ?? type
            }
        ).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

/// Shared node silhouette: person = circle, place = diamond, day = rounded square, custom type =
/// hexagon.
struct GraphNodeShape: Shape {
    var kind: GraphNode.Kind

    func path(in rect: CGRect) -> Path {
        switch kind {
        case .person:
            return Path(ellipseIn: rect)
        case .place:
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
            return path
        case .day:
            return Path(roundedRect: rect, cornerRadius: max(1, min(rect.width, rect.height) * 0.2))
        case .custom:
            // Flat-topped hexagon across the full width.
            let inset = rect.width / 4
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
            return path
        }
    }
}

enum GraphNodeStyle {
    static func fill(_ kind: GraphNode.Kind) -> Color {
        switch kind {
        case .person: Color.ink.person
        case .place: Color.ink.place
        case .day: Color.ink.secondaryText
        // Same token as a custom type link's underline (docs/design.md "Bağlantı biçimleri").
        case .custom: Color.ink.control
        }
    }
}
