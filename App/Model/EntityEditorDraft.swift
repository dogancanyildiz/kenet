import Foundation
import SwiftUI

/// Sheet-level draft store for unsaved entity-edit field text.
/// Tracks dirty flags by stable field id so Form's lazy rows cannot drop off-screen dirtiness.
@MainActor
@Observable
final class EntityEditorDraft {
    private var dirtyByID: [String: Bool] = [:]

    var isDirty: Bool { dirtyByID.values.contains(true) }

    func report(id: String, dirty: Bool) {
        dirtyByID[id] = dirty
    }

    /// Pure OR helper (not actor-bound) for combine-style tests.
    nonisolated static func combine(current: Bool, next: Bool) -> Bool { current || next }
}

private struct EntityEditorDraftKey: EnvironmentKey {
    static let defaultValue: EntityEditorDraft? = nil
}

extension EnvironmentValues {
    var entityEditorDraft: EntityEditorDraft? {
        get { self[EntityEditorDraftKey.self] }
        set { self[EntityEditorDraftKey.self] = newValue }
    }
}

/// Marks committed editor text only when the write succeeds.
enum EntityEditorSaveMark {
    static func commitIfSaved<Value: Equatable>(
        _ committed: Value, success: Bool, into saved: inout Value
    ) {
        if success { saved = committed }
    }
}
