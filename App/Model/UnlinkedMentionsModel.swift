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
    /// What the last link attempt has to tell the user; nil after a clean link or once dismissed.
    private(set) var notice: UnlinkedMentionNotice?
    /// True while a link is being written, so a second write cannot start.
    private(set) var isLinking = false
    /// True from a write until a query that started after it has answered: until then the rows on
    /// screen describe the file as it was, and a write from one of them would be refused as stale.
    private(set) var awaitsFreshList = false
    /// Whether a row may be linked now.
    var canLink: Bool { !isLinking && !awaitsFreshList }
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private var loaded: (root: URL?, file: String)?
    /// Test seam: runs after the link lock is taken and before the file write.
    @ObservationIgnored var testingHoldBeforeWrite: (@MainActor () async -> Void)?
    /// Test seam: replaces the file write. Production leaves this nil.
    @ObservationIgnored var testingWrite: (@MainActor (UnlinkedMention, KnownEntity) async throws -> Void)?
    /// Test seam: replaces the index query. Production leaves this nil.
    @ObservationIgnored var testingQuery: (@MainActor (KnownEntity) async throws -> [UnlinkedMention])?

    init(store: IndexStore) {
        self.store = store
    }

    /// The entity is not in this vault. The section stays hidden.
    func markUnavailable() {
        request = UUID()
        entity = nil
        mentions = []
        notice = nil
        awaitsFreshList = false
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
            notice = nil
            awaitsFreshList = false
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
        awaitsFreshList = false
    }

    func dismissNotice() {
        notice = nil
    }

    /// Links one approved spelling, then re-reads the list. A busy call does not write.
    func link(_ mention: UnlinkedMention, to entity: KnownEntity) async -> UnlinkedMentionLinkResult {
        guard canLink else { return .busy }
        isLinking = true
        defer { isLinking = false }
        let root = loaded?.root
        if let testingHoldBeforeWrite {
            await testingHoldBeforeWrite()
        }
        do {
            if let testingWrite {
                try await testingWrite(mention, entity)
            } else {
                try await store.linkUnlinkedMention(mention, to: entity, readFrom: root)
            }
            await finish(entity, notice: nil)
            return .linked
        } catch VaultStoreError.staleTarget {
            await finish(entity, notice: .stale)
            return .stale
        } catch VaultStoreError.indexUpdateFailed {
            // The file was saved; do not write it again. A re-read drops the linked row.
            await finish(entity, notice: .savedNotIndexed)
            return .savedNotIndexed
        } catch {
            // Nothing was written, so the rows still describe the file.
            if showsPage(of: entity) { notice = .failed }
            return .failed
        }
    }

    /// After a write or a refusal the rows are out of date. Another entity's page, opened while the
    /// write ran, keeps its own rows and hears nothing about this one.
    private func finish(_ entity: KnownEntity, notice: UnlinkedMentionNotice?) async {
        guard showsPage(of: entity) else { return }
        self.notice = notice
        awaitsFreshList = true
        await load(self.entity ?? entity)
    }

    private func showsPage(of entity: KnownEntity) -> Bool {
        self.entity?.file == entity.file && loaded?.root == store.vaultURL
    }
}

enum UnlinkedMentionLinkResult: Equatable {
    case linked
    case busy
    case stale
    case savedNotIndexed
    case failed
}

enum UnlinkedMentionNotice: Equatable {
    /// The line on disk no longer matches the row the user approved; nothing was written.
    case stale
    /// The link is in the file, the index could not follow.
    case savedNotIndexed
    /// Nothing was written.
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

/// The text one row shows: the event or task text without its list marker, clock, checkbox or
/// identifier, wikilinks reduced to their labels, and the bytes a link would replace emphasized.
enum UnlinkedMentionLine {
    static func styled(_ mention: UnlinkedMention) -> AttributedString {
        styled(
            line: mention.target.firstLineContent, text: mention.target.text, bytes: mention.position.byteRange,
            spelling: mention.spelling, isExplicit: mention.isExplicit)
    }

    /// `bytes` is the spelling's UTF-8 range in `line`. Nothing here indexes a `String` by offset:
    /// the line is cut as bytes and each piece decoded on its own, so a range that leaves the line,
    /// splits a character or does not hold the spelling shows the text plain instead.
    static func styled(
        line: [UInt8], text: String, bytes: Range<Int>, spelling: String, isExplicit: Bool
    ) -> AttributedString {
        let plain = AttributedString(VaultDisplayText.wikilinksOnly(text))
        guard !bytes.isEmpty, bytes.lowerBound >= 0, bytes.upperBound <= line.count,
            line[bytes].elementsEqual(spelling.utf8)
        else { return plain }
        // Linking removes a preceding at sign with the spelling, so it is marked with it.
        let lower =
            isExplicit && bytes.lowerBound > 0 && line[bytes.lowerBound - 1] == 64
            ? bytes.lowerBound - 1 : bytes.lowerBound
        let needle = Array(text.utf8)
        guard !needle.isEmpty, needle.count <= line.count,
            let start = (0...(line.count - needle.count)).first(where: {
                $0 <= lower && bytes.upperBound <= $0 + needle.count
                    && line[$0..<($0 + needle.count)].elementsEqual(needle)
            }),
            let before = String(bytes: line[start..<lower], encoding: .utf8),
            let marked = String(bytes: line[lower..<bytes.upperBound], encoding: .utf8),
            let after = String(bytes: line[bytes.upperBound..<(start + needle.count)], encoding: .utf8)
        else { return plain }
        var emphasized = AttributedString(marked)
        emphasized.inlinePresentationIntent = .stronglyEmphasized
        return AttributedString(VaultDisplayText.wikilinksOnly(before)) + emphasized
            + AttributedString(VaultDisplayText.wikilinksOnly(after))
    }
}

extension UnlinkedMention {
    /// One spelling on one line. It survives a re-query of an unchanged line, which value equality
    /// does not: that also compares the file's digest.
    var rowIdentity: String {
        "\(file)|\(position.line)|\(position.byteRange.lowerBound)|\(position.byteRange.upperBound)"
    }
}
