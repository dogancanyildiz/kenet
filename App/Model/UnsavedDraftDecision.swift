import Foundation

/// Whether leaving a journal editor would throw away typed text without asking.
enum UnsavedDraftDecision {
    /// Dirty text that is not mid-save must prompt before leave, vault switch, or day change.
    static func requiresPrompt(isDirty: Bool, isSaving: Bool) -> Bool {
        isDirty && !isSaving
    }

    /// Immediate leave is safe only when there is nothing to lose.
    static func canLeaveImmediately(isDirty: Bool, isSaving: Bool) -> Bool {
        !requiresPrompt(isDirty: isDirty, isSaving: isSaving)
    }
}

/// User choice from the unsaved-journal prompt (Kaydet / At / Vazgeç).
enum UnsavedDraftLeaveChoice: Equatable {
    case save
    case discard
    case stay
}
