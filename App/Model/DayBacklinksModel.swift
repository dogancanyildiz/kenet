import Foundation
import Observation
import VaultFormat
import VaultIndex

/// Incoming wikilinks to a day queried on demand. Never stored in the read model.
@MainActor @Observable
final class DayBacklinksModel {
    let store: IndexStore
    private(set) var items: [DayBacklinkItem] = []
    private(set) var hasLoaded = false
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private var loaded: (root: URL?, day: CalendarDate)?

    init(store: IndexStore) {
        self.store = store
    }

    func load(day: CalendarDate) async {
        let id = UUID()
        request = id
        let root = store.vaultURL
        if loaded?.root != root || loaded?.day != day {
            items = []
            hasLoaded = false
            loaded = nil
        }
        let raw: [DayBacklink]
        do {
            raw = try await store.computeDayBacklinks(day)
        } catch is CancellationError {
            // A replaced load leaves the list to the newer one.
            return
        } catch {
            if request == id {
                items = []
                loaded = (root, day)
                hasLoaded = true
            }
            return
        }
        guard request == id, root == store.vaultURL, !Task.isCancelled else { return }
        items = Self.buildItems(raw: raw, day: day, store: store)
        loaded = (root, day)
        hasLoaded = true
    }

    static func buildItems(raw: [DayBacklink], day: CalendarDate, store: IndexStore) -> [DayBacklinkItem] {
        let entityLookup = LinkedTextInk.lookup(entities: store.content.entities)
        return raw.map { link in
            let destination: DayBacklinkDestination
            if store.content.entities.contains(where: { $0.id == link.file }) {
                destination = .entity(link.file)
            } else if link.kind == "day", let fileDate = CalendarDate(link.name) {
                destination = .day(fileDate)
            } else {
                destination = .note(link.file)
            }

            let segments = buildSegments(from: link.text, byPath: entityLookup)

            return DayBacklinkItem(
                id: "\(link.file):\(link.line)",
                sourceFile: link.file,
                sourceKind: link.kind,
                sourceTitle: link.name,
                line: link.line,
                text: link.text,
                segments: segments,
                destination: destination
            )
        }
    }

    static func buildSegments(from text: String, byPath: [String: EntitySummary]) -> [InkLinkSegment] {
        let document = RawDocument(bytes: Array(text.utf8))
        let links = document.links
        guard !links.isEmpty else {
            return [InkLinkSegment(id: "0", text: text, kind: .plain)]
        }

        let bytes = Array(text.utf8)
        var cursor = 0
        var spans: [LinkedText.Span] = []
        for link in links.sorted(by: { $0.byteRange.lowerBound < $1.byteRange.lowerBound }) {
            let start = link.byteRange.lowerBound
            let end = link.byteRange.upperBound
            guard start >= cursor, end <= bytes.count else { continue }
            if start > cursor {
                let plainText = String(decoding: bytes[cursor..<start], as: UTF8.self)
                spans.append(LinkedText.Span(text: plainText, destination: nil))
            }
            let label = link.displayText ?? link.target
            let entityPath = byPath.first(where: {
                $0.value.name == link.target || ([$0.value.name] + $0.value.aliases).contains(link.target)
            })?.key
            spans.append(LinkedText.Span(text: label, destination: entityPath, target: link.target))
            cursor = end
        }
        if cursor < bytes.count {
            let rest = String(decoding: bytes[cursor...], as: UTF8.self)
            spans.append(LinkedText.Span(text: rest, destination: nil))
        }

        return LinkedTextInk.segments(LinkedText(spans: spans), byPath: byPath)
    }
}

/// A presentation item for an incoming wikilink to a day.
struct DayBacklinkItem: Identifiable, Sendable, Equatable {
    let id: String
    let sourceFile: String
    let sourceKind: String
    let sourceTitle: String
    let line: Int
    let text: String
    let segments: [InkLinkSegment]
    let destination: DayBacklinkDestination
}

/// Navigation destination for an incoming day backlink row.
enum DayBacklinkDestination: Hashable, Identifiable, Sendable {
    case entity(String)
    case day(CalendarDate)
    case note(String)

    var id: String {
        switch self {
        case .entity(let file): return "entity:" + file
        case .day(let date): return "day:" + date.description
        case .note(let file): return "note:" + file
        }
    }
}
