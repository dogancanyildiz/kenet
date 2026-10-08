import SwiftUI
import VaultFormat

struct SearchView: View {
    let store: IndexStore
    @State private var model: SearchModel
    @State private var path: [SearchDestination] = []
    @FocusState private var searchFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(store: IndexStore, initialQuery: String = "") {
        self.store = store
        let model = SearchModel(store: store)
        model.query = initialQuery
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                InkPageTitle("Ara")
                searchField
                    .padding(.horizontal, InkSpacing.margin)
                    .padding(.bottom, 8)
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
            .focusedSceneValue(
                \.openSearch,
                {
                    path = []
                    searchFocused = true
                })
        #endif
        .environment(
            \.openSearch,
            {
                path = []
                searchFocused = true
            }
        )
        .onChange(of: path) { _, path in if path.isEmpty { searchFocused = true } }
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
                        let items = model.results.filter { $0.group == group }
                        if !items.isEmpty {
                            Section {
                                SectionHeader(title: group.title)
                                    .inkListRow()
                                ForEach(items) { item in resultRow(item) }
                            }
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
        .inkListRow(isSelected: item.id == model.selectedID)
        .id(item.id)
    }

    private func open(_ item: SearchItem) {
        if let destination = model.activate(item) {
            searchFocused = false
            path.append(destination)
        }
    }
}

private struct SearchRequest: Hashable {
    let query: String
    let root: URL?
    let updated: Date?
}
