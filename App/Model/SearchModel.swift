import CryptoKit
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
    /// Pages opened from the results inside the search sheet; empty while the results show.
    var path: [SearchDestination] = []
    /// Asks for search inside the open sheet (⌘F, a page's magnifier); the sheet focuses its
    /// field on each one (``SearchView``).
    private(set) var fieldFocusRequests = 0
    private(set) var recentQueries: [String] = []
    private(set) var selectedID: String?
    /// The scope chip. Selection, the arrow keys and Enter work on what it shows; a new scope
    /// selects its first visible result.
    var scope: SearchScope = .all {
        didSet { if scope != oldValue { selectedID = visibleResults.first?.id } }
    }
    private(set) var isSearching = false
    private(set) var errorText: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private var historyRoot: URL?
    private var resultRoot: URL?

    init(store: IndexStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        reloadHistory()
    }

    var isEmpty: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// The results the list draws, in its order: by group, then as built, filtered by `scope`.
    var visibleResults: [SearchItem] {
        SearchGroup.allCases.flatMap { group in results.filter { $0.group == group && scope.includes($0) } }
    }
    var selected: SearchItem? { visibleResults.first { $0.id == selectedID } }

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
            selectedID = visibleResults.first?.id
        } catch is CancellationError {
        } catch {
            guard request == token, root == store.vaultURL else { return }
            errorText = String(localized: "Arama başarısız: \(error.localizedDescription)")
        }
    }

    func moveSelection(by offset: Int) {
        let visible = visibleResults
        guard !visible.isEmpty else { return }
        let index = visible.firstIndex { $0.id == selectedID } ?? 0
        selectedID = visible[min(max(index + offset, 0), visible.count - 1)].id
    }

    /// Back from an opened page to the result list.
    func showResults() { path = [] }

    /// Search asked for again while the sheet is open: back to the results, the field focused.
    func returnToField() {
        showResults()
        fieldFocusRequests += 1
    }

    func activate(_ item: SearchItem) -> SearchDestination? {
        guard resultRoot == store.vaultURL, visibleResults.contains(item) else { return nil }
        rememberQuery()
        return item.destination
    }

    func rememberQuery() {
        reloadHistory()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let key = Self.historyKey(for: store.vaultURL) else { return }
        recentQueries.removeAll { SearchResults.comparisonKey($0) == SearchResults.comparisonKey(text) }
        recentQueries.insert(text, at: 0)
        recentQueries = Array(recentQueries.prefix(5))
        defaults.set(recentQueries, forKey: key)
    }

    func clearHistory() {
        if let key = Self.historyKey(for: store.vaultURL) {
            defaults.removeObject(forKey: key)
        }
        recentQueries = []
        historyRoot = store.vaultURL
    }

    /// Reloads recent queries for the current vault (call after vault switch or Settings clear).
    func reloadHistory() {
        let root = store.vaultURL
        historyRoot = root
        guard let key = Self.historyKey(for: root) else {
            recentQueries = []
            return
        }
        recentQueries = Array((defaults.stringArray(forKey: key) ?? []).prefix(5))
    }

    /// UserDefaults key for one vault's recent queries. `nil` when no vault is open.
    static func historyKey(for vaultURL: URL?) -> String? {
        guard let vaultURL else { return nil }
        let identity = vaultURL.resolvingSymlinksInPath().standardizedFileURL.path
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return "search.recentQueries." + digest
    }

    static func clearStoredHistory(for vaultURL: URL?, defaults: UserDefaults = .standard) {
        guard let key = historyKey(for: vaultURL) else { return }
        defaults.removeObject(forKey: key)
    }
}
