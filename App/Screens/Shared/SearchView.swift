import SwiftUI
import VaultFormat

struct SearchView: View {
    let store: IndexStore
    @State private var model: SearchModel
    @State private var path: [SearchDestination] = []
    @FocusState private var searchFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(store: IndexStore) {
        self.store = store
        _model = State(initialValue: SearchModel(store: store))
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                searchField.padding()
                if model.isSearching { ProgressView().padding(.bottom, 8) }
                if let error = model.errorText {
                    Text(verbatim: error).foregroundStyle(.red).padding()
                }
                resultList
            }
            .navigationTitle("Ara")
            .toolbar { Button("Kapat") { dismiss() } }
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
        .task { searchFocused = true }
        .task(id: SearchRequest(query: model.query, root: store.vaultURL, updated: store.lastUpdated)) {
            await model.search(debounce: true)
        }
    }

    private var searchField: some View {
        TextField("Kişi, konum veya metin ara", text: $model.query)
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
            .onSubmit { if let selected = model.selected { open(selected) } else { model.rememberQuery() } }
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
                    Section("Son aramalar") {
                        ForEach(model.recentQueries, id: \.self) { query in
                            Button {
                                model.query = query
                                searchFocused = true
                            } label: {
                                Text(verbatim: query)
                            }
                        }
                    }
                } else if model.results.isEmpty && !model.isSearching && model.errorText == nil {
                    Text("Sonuç bulunamadı").foregroundStyle(.secondary)
                } else {
                    ForEach(SearchGroup.allCases) { group in
                        let items = model.results.filter { $0.group == group }
                        if !items.isEmpty {
                            Section {
                                ForEach(items) { item in resultRow(item) }
                            } header: {
                                Text(group.title)
                            }
                        }
                    }
                }
            }
            .onChange(of: model.selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private func resultRow(_ item: SearchItem) -> some View {
        Button {
            open(item)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(SearchHighlight.text(item.title, query: model.query)).lineLimit(3)
                Text(SearchHighlight.text(item.detail, query: model.query))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(item.id == model.selectedID ? Color.accentColor.opacity(0.15) : Color.clear)
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
