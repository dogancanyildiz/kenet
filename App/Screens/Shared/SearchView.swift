import SwiftUI
import VaultFormat

struct SearchView: View {
    let store: IndexStore
    @State private var model: SearchModel
    /// Search asked for inside the sheet: ⌘F and a page's magnifier. Made once (``ShellAction``).
    @State private var returnToField: ShellAction
    @FocusState private var searchFocused: Bool
    @State private var scope: SearchScope = .all
    @Environment(\.dismiss) private var dismiss

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
                } else if model.results.isEmpty && !model.isSearching && model.errorText == nil {
                    EmptyState("Sonuç bulunamadı")
                        .inkListRow()
                } else {
                    ForEach(SearchGroup.allCases) { group in
                        let items = visibleResults.filter { $0.group == group }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionHeader(title: group.title)
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

    private var visibleResults: [SearchItem] {
        model.results.filter(scope.includes)
    }

    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchScope.allCases) { item in
                    TagChip(title: item.title, isSelected: scope == item, onTap: { scope = item })
                }
            }
            .padding(.horizontal, InkSpacing.margin)
        }
        .padding(.bottom, 8)
    }

    private func resultRow(_ item: SearchItem) -> some View {
        Button {
            open(item)
        } label: {
            MarginRow(kind: .vault, time: nil) {
                Text(SearchHighlight.text(item.title, query: model.query))
                    .foregroundStyle(.ink.text)
                    .lineLimit(3)
            } secondary: {
                if !item.detail.isEmpty {
                    Text(SearchHighlight.text(item.detail, query: model.query))
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, InkSpacing.cardPadding)
        .padding(.vertical, 8)
        .background(item.id == model.selectedID ? Color.ink.accentSoft : Color.clear)
        .accessibilityElement(children: .contain)
        .id(item.id)
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
