import SwiftUI
import VaultFormat

struct SearchView: View {
    let store: IndexStore
    @State private var model: SearchModel
    /// Search asked for inside the sheet: ⌘F and a page's magnifier. Made once (``ShellAction``).
    @State private var returnToField: ShellAction
    @FocusState private var searchFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    init(store: IndexStore, initialQuery: String = "") {
        let model = SearchModel(store: store)
        model.query = initialQuery
        self.init(store: store, model: model)
    }

    /// The caller keeps the model (and with it the pages open in the sheet).
    init(store: IndexStore, model: SearchModel) {
        self.store = store
        _model = State(initialValue: model)
        _returnToField = State(initialValue: ShellAction { [model] in model.returnToField() })
    }

    var body: some View {
        NavigationStack(path: $model.path) {
            VStack(spacing: 0) {
                InkPageTitle("Ara")
                searchField
                    .padding(.horizontal, InkSpacing.margin)
                    .padding(.bottom, 8)
                scopeChips
                if model.isSearching { ProgressView().padding(.bottom, 8) }
                if let error = model.errorText {
                    Text(verbatim: error).foregroundStyle(.ink.danger).padding()
                }
                resultList
            }
            .inkPageColumn()
            .inkSheet("Ara", closeIdentifier: "button.search.close")
            .navigationDestination(for: SearchDestination.self) { destination in
                switch destination {
                case .entity(let file):
                    if let entity = store.content.entities.first(where: { $0.id == file }) {
                        EntityView(store: store, entity: entity)
                    } else {
                        ContentUnavailableView("Sonuç artık mevcut değil", systemImage: "doc.questionmark")
                    }
                case .day(let date): DayView(store: store, date: date)
                case .note(let file): SearchNoteView(store: store, file: file)
                }
            }
        }
        // Nested destinations (notes) use this so "Kapat" closes the sheet, not only the push.
        .inkSheetDismissAction { dismiss() }
        #if os(macOS)
            .frame(minWidth: 520, idealWidth: 650, minHeight: 460, idealHeight: 650)
            .focusedSceneValue(\.openSearch, returnToField)
        #endif
        .searchSheetContext(returnToField)
        .onChange(of: model.path) { _, path in if path.isEmpty { searchFocused = true } }
        .onChange(of: model.fieldFocusRequests) { searchFocused = true }
        .onChange(of: store.vaultURL) { _, _ in model.reloadHistory() }
        .task { searchFocused = true }
        .task(id: store.vaultURL) { model.reloadHistory() }
        .task(id: SearchRequest(query: model.query, root: store.vaultURL, updated: store.lastUpdated)) {
            await model.search(debounce: true)
        }
    }

    private var searchField: some View {
        InkFilterField(
            "Kişi, konum veya metin ara", text: $model.query, isFocused: $searchFocused,
            identifier: "field.search", clearIdentifier: "button.search.clear"
        )
        .onSubmit {
            if let selected = model.selected {
                open(selected)
            } else {
                model.rememberQuery()
            }
        }
        #if os(macOS)
            .onKeyPress(.downArrow) {
                model.moveSelection(by: 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                model.moveSelection(by: -1)
                return .handled
            }
        #endif
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            List {
                if model.isEmpty {
                    Section {
                        SectionHeader(title: String(localized: "Son aramalar"))
                            .inkListRow()
                        ForEach(model.recentQueries, id: \.self) { query in
                            Button {
                                model.query = query
                                searchFocused = true
                            } label: {
                                MarginRow(kind: .external, time: nil) {
                                    Text(verbatim: query)
                                        .foregroundStyle(.ink.text)
                                }
                            }
                            .buttonStyle(.plain)
                            .inkListRow()
                        }
                    }
                } else if model.visibleResults.isEmpty && !model.isSearching && model.errorText == nil {
                    EmptyState("Sonuç bulunamadı")
                        .inkListRow()
                } else {
                    ForEach(SearchGroup.allCases) { group in
                        let items = model.visibleResults.filter { $0.group == group }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionHeader(title: group.title, count: items.count)
                                InkCard(padded: false) {
                                    VStack(spacing: 0) {
                                        ForEach(items.indices, id: \.self) { index in
                                            if index > 0 { InkCardDivider() }
                                            resultRow(items[index])
                                        }
                                    }
                                }
                            }
                            .inkListRow()
                        }
                    }
                }
            }
            .listStyle(.plain)
            .inkPage()
            .onChange(of: model.selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    /// Thin scope capsules (Şafak çizimi, ~28 pt); the tap area stays 44 pt around them. The
    /// selected one is accent-soft; with "Renksiz ayırt et" it also carries a checkmark.
    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SearchScope.allCases) { item in
                    scopeChip(item)
                }
            }
            .padding(.horizontal, InkSpacing.margin)
        }
        .padding(.bottom, 4)
    }

    private func scopeChip(_ item: SearchScope) -> some View {
        let isSelected = model.scope == item
        return Button {
            model.scope = item
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: item.title)
                    .font(.footnote.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.ink.accent : Color.ink.secondaryText)
                    .lineLimit(1)
                if isSelected && differentiateWithoutColor {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.ink.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.ink.accentSoft : Color.ink.well)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.clear : Color.ink.rule,
                        lineWidth: InkStroke.hairline(scale: displayScale))
            }
            .frame(minHeight: TapTarget.minimumLength)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: item.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Kind mark of a result row: people and places, events, notes on an accent-soft tile; a task
    /// as its empty box.
    @ViewBuilder
    private func resultMark(_ group: SearchGroup) -> some View {
        let symbol: String? =
            switch group {
            case .people: "person"
            case .places: "mappin"
            case .entities: "tag"
            case .events: "calendar"
            case .notes: "doc.text"
            case .tasks: nil
            }
        if let symbol {
            Image(systemName: symbol)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.ink.accent)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.ink.accentSoft)
                )
        } else {
            Circle()
                .strokeBorder(Color.ink.control, lineWidth: InkStroke.control)
                .frame(width: 22, height: 22)
                .frame(width: 30, height: 30)
        }
    }

    /// Matches drawn on a soft accent wash instead of in bold (Şafak çizimi).
    private func highlighted(_ text: String) -> AttributedString {
        var result = SearchHighlight.text(text, query: model.query)
        for run in result.runs where run.inlinePresentationIntent == .stronglyEmphasized {
            result[run.range].inlinePresentationIntent = nil
            result[run.range].backgroundColor = Color.ink.accentSoft
        }
        return result
    }

    private func resultRow(_ item: SearchItem) -> some View {
        Button {
            open(item)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                resultMark(item.group)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(highlighted(item.title))
                        .foregroundStyle(.ink.text)
                        .lineLimit(3)
                    if !item.detail.isEmpty {
                        Text(highlighted(item.detail))
                            .font(.ink.meta)
                            .foregroundStyle(.ink.secondaryText)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if Self.showsChevron(item.group) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.ink.tertiaryText)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: TapTarget.minimumLength, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, InkSpacing.cardPadding)
        .padding(.vertical, 6)
        .background(item.id == model.selectedID ? Color.ink.accentSoft : Color.clear)
        .accessibilityElement(children: .contain)
        .id(item.id)
    }

    /// Rows that open a page of their own (a person, a place, a note) end in "›"; events and tasks
    /// open their day.
    private static func showsChevron(_ group: SearchGroup) -> Bool {
        switch group {
        case .people, .places, .entities, .notes: true
        case .events, .tasks: false
        }
    }

    private func open(_ item: SearchItem) {
        if let destination = model.activate(item) {
            searchFocused = false
            model.path.append(destination)
        }
    }
}

extension View {
    /// What search means on a page opened inside the search sheet: back to the results. Mac draws
    /// the manşet magnifier only in this context (``SearchButton``): the window's toolbar search
    /// is behind the sheet.
    func searchSheetContext(_ showResults: ShellAction) -> some View {
        environment(\.isSearchSheet, true)
            .environment(\.openSearch, showResults)
    }
}

private struct SearchRequest: Hashable {
    let query: String
    let root: URL?
    let updated: Date?
}
