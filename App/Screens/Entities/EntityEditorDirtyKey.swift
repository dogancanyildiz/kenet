import SwiftUI

/// Bubbles dirty draft state from field editors up to ``EntityEditSheet``.
struct EntityEditorDirtyKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = EntityEditorDraft.combine(current: value, next: nextValue())
    }
}
