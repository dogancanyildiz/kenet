import Foundation

extension QuickEntryModel {
    /// Append without losing a draft; pin the selected path for same-name entities.
    func prefillMention(_ entity: EntitySummary) {
        guard let known = store.knownEntities.first(where: { $0.file == entity.id }) else { return }
        if !text.isEmpty && text.last?.isWhitespace != true { text += " " }
        let start = text.utf8.count + 1
        text += "@" + known.name + " "
        composer.pin(known, nameRange: start..<(start + known.name.utf8.count))
    }
}
