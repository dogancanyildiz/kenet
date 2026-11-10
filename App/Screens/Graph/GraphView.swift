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
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            InkScrolledMasthead(masthead)
                            GraphControls(
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
                            InkCard(padded: false) {
                                GraphCanvas(model: model)
                                    .frame(height: canvasHeight)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.ink.paper)
                                    .clipShape(RoundedRectangle(cornerRadius: InkCorner.card))
                            }
                            .padding(.horizontal, InkSpacing.margin)
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            legendRow
                            if let node = model.graph.nodes.first(where: { $0.id == model.selected }) {
                                #if os(macOS)
                                    EmptyView()
                                #else
                                    selectedRow(node)
                                #endif
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
                .frame(maxWidth: .infinity)
                #if os(macOS)
                    // The panel stays; with no selection it says "Düğüm seç" (docs/screens.md).
                    GraphSelectionPanel(
                        store: store, node: model.graph.nodes.first { $0.id == model.selected },
                        graph: model.graph, currentDay: day
                    ) {
                        model.select(nil, recenter: false)
                    }
                    .frame(width: 300)
                #endif
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
        InkCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    verbatim: GraphSelectionPresentation.summary(
                        name: node.name, links: GraphSelectionPresentation.relationCount(of: node.id, in: model.graph),
                        daysSince: daysSinceLastMention(node), locale: locale)
                )
                .font(.ink.content).foregroundStyle(.ink.text)
                openPageLink(node)
                    .buttonStyle(InkPrimaryButtonStyle())
            }
        }
        .padding(.horizontal, InkSpacing.margin)
        .padding(.bottom, InkSpacing.margin)
    }

    @ViewBuilder private func openPageLink(_ node: GraphNode) -> some View {
        if let date = node.date {
            if date != day { NavigationLink("Sayfayı aç") { DayView(store: store, date: date) } }
        } else if let entity = store.content.entities.first(where: { $0.id == node.id }) {
            NavigationLink("Sayfayı aç") { EntityView(store: store, entity: entity) }
        }
    }

    /// Nil for day nodes and never-mentioned entities: the summary then has no "son" part.
    private func daysSinceLastMention(_ node: GraphNode) -> Int? {
        guard node.date == nil,
            let last = store.entityUsage.first(where: { $0.file == node.id })?.lastDate
        else { return nil }
        return max(0, LocalDay.today(at: clockNow()).ordinal - last.ordinal)
    }

    /// The whole graph's manşet holds the kind filter; a day's graph names its day instead.
    private var masthead: InkPageTitle<some View> {
        InkPageTitle(pageTitle, byline: day.map { Self.byline($0, locale: locale) } ?? rootByline) {
            if day == nil {
                GraphFilterMenu(filter: $model.filter, types: customTypes)
            }
            SearchButton()
        }
    }

    /// Counts of what the graph draws for the chosen period.
    private var rootByline: String {
        let nodes = model.graph.nodes
        let people = nodes.filter { $0.kind == .person }.count
        let places = nodes.filter { $0.kind == .place }.count
        let days = nodes.filter { $0.kind == .day }.count
        return String(localized: "\(people) kişi · \(places) konum · \(days) gün", locale: locale)
    }

    private var customTypes: [EntityTypeChoice] {
        EntityTypeChoices.choices(store.entityTypes).filter { !GraphInput.kinds.contains($0.id) }
    }

    static func byline(_ day: CalendarDate, locale: Locale) -> String {
        LocalDay.instant(for: day).formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(locale))
    }

    private var pageTitle: LocalizedStringKey { day == nil ? "Graph" : "Günün grafiği" }
    private var screenIdentifier: String { day == nil ? "screen.graph" : "screen.dayGraph" }

    /// One rule for both graphs: days are the hubs, entities meet only through a written relation.
    private var explanation: Text {
        Text("Gün, o gün geçen her kayda bağlanır. Öteki çizgiler elle kurulan bağları gösterir.")
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
        // Days are always drawn: the hubs every other node hangs from.
        if day != nil {
            legendMark(kind: .day, title: "Gün")
        } else {
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

/// Mac's persistent selection column; kept independent of the graph shell so the D7 split shell
/// can host the same detail view later.
struct GraphSelectionPanel: View {
    let store: IndexStore
    let node: GraphNode?
    let graph: GraphModel
    /// A day's own graph: its day node has no "Sayfayı aç" (the user came from that day).
    var currentDay: CalendarDate? = nil
    var onClose: () -> Void

    var body: some View {
        Group {
            if let node {
                GraphSelectionDetail(store: store, node: node, graph: graph, currentDay: currentDay, onClose: onClose)
            } else {
                Text("Düğüm seç")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                    .padding(InkSpacing.margin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(Color.ink.paper)
        .overlay(alignment: .leading) { Rectangle().fill(Color.ink.rule).frame(width: 1) }
    }
}

private struct GraphSelectionDetail: View {
    let store: IndexStore
    let node: GraphNode
    let graph: GraphModel
    let currentDay: CalendarDate?
    var onClose: () -> Void

    private var kindName: String {
        switch node.kind {
        case .person: String(localized: "Kişi")
        case .place: String(localized: "Konum")
        case .day: String(localized: "Gün")
        case .custom(let type):
            EntityTypeChoices.choices(store.entityTypes).first { $0.id == type }?.name ?? type
        }
    }

    private var relatedDays: [GraphNode] {
        let ids = graph.neighbors(of: node.id)
        return graph.nodes.filter { ids.contains($0.id) && $0.date != nil }
            .sorted { ($0.date?.ordinal ?? 0) > ($1.date?.ordinal ?? 0) }
            .prefix(4).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: InkSpacing.section) {
            HStack {
                Text(verbatim: node.name).font(.ink.dayName).foregroundStyle(.ink.text)
                Spacer()
                Button(action: onClose) {
                    Label("Kapat", systemImage: "xmark").labelStyle(.iconOnly).tapTarget()
                }.buttonStyle(InkTextButtonStyle())
            }
            Text(verbatim: kindName).font(.ink.meta).foregroundStyle(.ink.secondaryText)
            InkCard {
                detailRow("Bağlar", GraphSelectionPresentation.relationCount(of: node.id, in: graph).formatted())
                InkCardDivider()
                detailRow("Geçişler", node.count.formatted())
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Birlikte geçen günler", count: relatedDays.count)
                InkCard {
                    if relatedDays.isEmpty {
                        Text("Birlikte geçen gün yok.").font(.ink.meta).foregroundStyle(.ink.secondaryText)
                    } else {
                        ForEach(relatedDays.indices, id: \.self) { index in
                            let day = relatedDays[index]
                            if index > 0 { InkCardDivider() }
                            NavigationLink {
                                if let date = day.date { DayView(store: store, date: date) }
                            } label: {
                                Text(verbatim: day.name).frame(minHeight: TapTarget.minimumLength)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            if let entity = store.content.entities.first(where: { $0.id == node.id }) {
                NavigationLink("Sayfayı aç") { EntityView(store: store, entity: entity) }
                    .buttonStyle(InkPrimaryButtonStyle())
            } else if let date = node.date, date != currentDay {
                NavigationLink("Sayfayı aç") { DayView(store: store, date: date) }
                    .buttonStyle(InkPrimaryButtonStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(InkSpacing.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func detailRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label).font(.ink.meta).foregroundStyle(.ink.secondaryText)
            Spacer()
            Text(verbatim: value).font(.ink.value).foregroundStyle(.ink.text)
        }
    }
}

enum GraphSelectionPresentation {
    /// "N bağ" counts explicit relations only; the day edges (a day meets everything mentioned
    /// on it) are not relations.
    static func relationCount(of id: String, in graph: GraphModel) -> Int {
        graph.edges.filter { $0.kind == .relation && ($0.first == id || $0.second == id) }.count
    }

    /// "Baran Tunç · 8 bağ · son 3 gün önce"; today reads "bugün"; no date (a day node, a
    /// never-mentioned entity) drops the last part.
    static func summary(name: String, links: Int, daysSince: Int?, locale: Locale = .autoupdatingCurrent) -> String {
        let bundle = PresentationLocalization.bundle(locale)
        return switch daysSince {
        case nil: String(localized: "\(name) · \(links) bağ", bundle: bundle, locale: locale)
        case 0?: String(localized: "\(name) · \(links) bağ · son bugün", bundle: bundle, locale: locale)
        case let days?:
            String(localized: "\(name) · \(links) bağ · son \(days) gün önce", bundle: bundle, locale: locale)
        }
    }
}
