import Foundation
import Observation

@MainActor @Observable
final class SearchModel {
    let store: IndexStore
    var query = "" {
        didSet {
            if query != oldValue {
                results = []
                selectedID = nil
                errorText = nil
                request = UUID()
            }
        }
    }
    private(set) var results: [SearchItem] = []
    private(set) var recentQueries: [String]
    private(set) var selectedID: String?
    private(set) var isSearching = false
    private(set) var errorText: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var request = UUID()
    private var resultRoot: URL?
    private static let historyKey = "search.recentQueries"

    init(store: IndexStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        recentQueries = Array((defaults.stringArray(forKey: Self.historyKey) ?? []).prefix(5))
    }

    var isEmpty: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var selected: SearchItem? { results.first { $0.id == selectedID } }

    func search(debounce: Bool = false) async {
        let token = UUID()
        request = token
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = store.vaultURL
        results = []
        selectedID = nil
        errorText = nil
        isSearching = !text.isEmpty
        defer { if request == token { isSearching = false } }
        guard !text.isEmpty else { return }
        do {
            if debounce { try await Task.sleep(for: .milliseconds(150)) }
            try Task.checkCancellation()
            let matches = try await store.search(text)
            try Task.checkCancellation()
            guard request == token, root == store.vaultURL else { return }
            results = SearchResults.build(query: text, entities: store.content.entities, matches: matches)
            resultRoot = root
            selectedID = results.first?.id
        } catch is CancellationError {
        } catch {
            guard request == token, root == store.vaultURL else { return }
            errorText = String(localized: "Arama başarısız: \(error.localizedDescription)")
        }
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == selectedID } ?? 0
        selectedID = results[min(max(index + offset, 0), results.count - 1)].id
    }

    func activate(_ item: SearchItem) -> SearchDestination? {
        guard resultRoot == store.vaultURL, results.contains(item) else { return nil }
        rememberQuery()
        return item.destination
    }

    func rememberQuery() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        recentQueries.removeAll { SearchResults.comparisonKey($0) == SearchResults.comparisonKey(text) }
        recentQueries.insert(text, at: 0)
        recentQueries = Array(recentQueries.prefix(5))
        defaults.set(recentQueries, forKey: Self.historyKey)
    }
}
