import EntityRecognition
import Foundation
import Observation
import VaultFormat
import VaultIndex
import VaultStore

/// Plain spellings on an entity page that the user has not linked yet.
/// The query reads the vault on a background task; call it from the page loader, not the list row.
@MainActor @Observable
final class UnlinkedMentionsModel {
    let store: IndexStore
    private(set) var entity: KnownEntity?
    private(set) var mentions: [UnlinkedMention] = []
    /// True once a query for the current vault and file has answered, including an empty or failed one.
    private(set) var hasLoaded = false
    /// A link was refused because the line on disk no longer matches the row the user approved.
    private(set) var showsStaleNotice = false
    /// True while a link is being written and the list re-read, so a second write cannot start.
    private(set) var isLinking = false
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private var loaded: (root: URL?, file: String)?
    /// Test seam: runs after the link lock is taken and before the file write.
    @ObservationIgnored var testingHoldBeforeWrite: (@MainActor () async -> Void)?
    /// Test seam: replaces the index query. Production leaves this nil.
    @ObservationIgnored var testingQuery: (@MainActor (KnownEntity) async throws -> [UnlinkedMention])?

    init(store: IndexStore) {
        self.store = store
    }

    /// The entity is not in this vault. The section stays hidden.
    func markUnavailable() {
        entity = nil
        mentions = []
        showsStaleNotice = false
        loaded = (store.vaultURL, "")
        hasLoaded = true
    }

    func load(_ entity: KnownEntity) async {
        let id = UUID()
        request = id
        let root = store.vaultURL
        // Another vault or file must not keep the previous rows on screen.
        if loaded?.root != root || loaded?.file != entity.file {
            mentions = []
            hasLoaded = false
            showsStaleNotice = false
            loaded = nil
        }
        self.entity = entity
        let fetched: [UnlinkedMention]?
        do {
            if let testingQuery {
                fetched = try await testingQuery(entity)
            } else {
                fetched = try await store.computeUnlinkedMentions(of: entity)
            }
        } catch {
            fetched = nil
        }
        guard request == id, root == store.vaultURL, !Task.isCancelled else { return }
        mentions = fetched ?? []
        loaded = (root, entity.file)
        hasLoaded = true
    }

    /// Links one approved spelling, then re-reads the list. A busy call does not write.
    func link(_ mention: UnlinkedMention, to entity: KnownEntity) async -> UnlinkedMentionLinkResult {
        guard !isLinking else { return .busy }
        isLinking = true
        defer { isLinking = false }
        if let testingHoldBeforeWrite {
            await testingHoldBeforeWrite()
        }
        do {
            try await store.linkUnlinkedMention(mention, to: entity)
            showsStaleNotice = false
            await load(entity)
            return .linked
        } catch VaultStoreError.staleTarget {
            showsStaleNotice = true
            await load(entity)
            return .stale
        } catch {
            // The file was saved; do not write it again. A re-read drops the linked row.
            if case VaultStoreError.indexUpdateFailed = error {
                await load(entity)
            }
            return .failed
        }
    }
}

enum UnlinkedMentionLinkResult: Equatable {
    case linked
    case busy
    case stale
    case failed
}

/// How many rows the section shows before "show all" expands it on the same page.
enum UnlinkedMentionList {
    static let collapsedLimit = 5

    static func visibleCount(total: Int, expanded: Bool) -> Int {
        expanded || total <= collapsedLimit ? total : collapsedLimit
    }

    static func showsAll(total: Int, expanded: Bool) -> Bool {
        !expanded && total > collapsedLimit
    }
}

/// UTF-8 byte range of a spelling, mapped onto `String` without splitting a character.
enum MentionByteRange {
    /// Nil when the range is empty, outside the text, or lands inside a character.
    static func characterRange(in text: String, utf8 bytes: Range<Int>) -> Range<String.Index>? {
        guard bytes.lowerBound >= 0, !bytes.isEmpty else { return nil }
        let view = text.utf8
        guard let lowerByte = view.index(view.startIndex, offsetBy: bytes.lowerBound, limitedBy: view.endIndex),
            let upperByte = view.index(lowerByte, offsetBy: bytes.count, limitedBy: view.endIndex),
            let lower = String.Index(lowerByte, within: text),
            let upper = String.Index(upperByte, within: text),
            lower < upper
        else { return nil }
        return lower..<upper
    }

    /// The spelling is strongly emphasized. An unusable range leaves the line plain.
    static func styled(_ text: String, utf8 bytes: Range<Int>) -> AttributedString {
        var result = AttributedString(text)
        guard let range = characterRange(in: text, utf8: bytes),
            let lower = AttributedString.Index(range.lowerBound, within: result),
            let upper = AttributedString.Index(range.upperBound, within: result)
        else { return result }
        result[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
        return result
    }
}
