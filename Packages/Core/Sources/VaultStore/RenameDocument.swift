import Foundation
import VaultFormat

struct RenameDocument {
    let document: RawDocument
    let rawFields: [String]
    /// Frontmatter list keys that could not be rewritten; body updates are still applied.
    let listFailures: [(key: String, reason: String)]

    static func rewrite(_ original: RawDocument, targets: RenameTargets, eligible: Bool) throws -> Self {
        guard !original.isReadOnly else { throw EditError.readOnlyDocument }
        var document = original
        if eligible {
            document = try targets.body(
                original,
                links: original.links.filter {
                    $0.source == .body && targets.matches($0.target)
                })
        }
        let links = original.links.filter { targets.matches($0.target) }
        func containsLink(key: String, entry: String? = nil) -> Bool {
            links.contains {
                guard case .frontmatter(let sourceKey, let sourceEntry) = $0.source else { return false }
                return sourceKey.utf8.elementsEqual(key.utf8)
                    && sourceEntry.map { Array($0.utf8) } == entry.map { Array($0.utf8) }
            }
        }
        var raw: [String] = []
        var listFailures: [(key: String, reason: String)] = []
        if case .parsed(let frontmatter) = document.frontmatter {
            for field in frontmatter.fields {
                switch field.value {
                case .raw(let source):
                    if try targets.text(source) != source { raw.append(field.key) }
                case .scalar(let value) where eligible && containsLink(key: field.key):
                    let text = try targets.text(value.text)
                    if !text.utf8.elementsEqual(value.text.utf8) {
                        document = try document.settingFrontmatterValue(.text(text), forKey: field.key)
                    }
                case .list(let items, _) where eligible:
                    let outcome = applyList(document, key: field.key, items: items, targets: targets)
                    document = outcome.document
                    if let reason = outcome.failure {
                        listFailures.append((field.key, reason))
                    }
                case .mapping(let entries) where eligible:
                    for entry in entries where containsLink(key: field.key, entry: entry.key) {
                        let text = try targets.text(entry.value.text)
                        if !text.utf8.elementsEqual(entry.value.text.utf8) {
                            document = try document.settingFrontmatterEntry(
                                .text(text), forKey: entry.key, inMapping: field.key)
                        }
                    }
                default: break
                }
            }
        }
        return Self(document: document, rawFields: raw, listFailures: listFailures)
    }

    /// Rewrites one frontmatter list; on failure leaves the document unchanged and returns a reason.
    static func applyList(
        _ document: RawDocument, key: String, items: [FrontmatterScalar], targets: RenameTargets,
        rewrite: (RawDocument, String, [FrontmatterScalar], RenameTargets) throws -> RawDocument = {
            try RenameList.rewrite($0, key: $1, items: $2, targets: $3)
        }
    ) -> (document: RawDocument, failure: String?) {
        do {
            return (try rewrite(document, key, items, targets), nil)
        } catch {
            return (document, describeListFailure(error))
        }
    }

    private static func describeListFailure(_ error: any Error) -> String {
        if let edit = error as? EditError {
            switch edit {
            case .invalidValue: return "list tokens could not be matched"
            default: return String(describing: edit)
            }
        }
        return String(describing: error)
    }
}
