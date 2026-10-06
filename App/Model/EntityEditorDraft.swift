import Foundation

/// Tracks unsaved text in entity edit editors (scalar/typed/aliases/add-field).
enum EntityEditorDraft {
    /// Preference / reduce helper: any child reporting dirty makes the sheet dirty.
    static func combine(current: Bool, next: Bool) -> Bool { current || next }
}
