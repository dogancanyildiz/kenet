import Testing

@testable import Journal

struct UnsavedDraftDecisionTests {
    @Test func dirtyTextRequiresPromptUnlessSaving() {
        #expect(UnsavedDraftDecision.requiresPrompt(isDirty: true, isSaving: false))
        #expect(!UnsavedDraftDecision.canLeaveImmediately(isDirty: true, isSaving: false))

        #expect(!UnsavedDraftDecision.requiresPrompt(isDirty: false, isSaving: false))
        #expect(UnsavedDraftDecision.canLeaveImmediately(isDirty: false, isSaving: false))

        #expect(!UnsavedDraftDecision.requiresPrompt(isDirty: true, isSaving: true))
        #expect(UnsavedDraftDecision.canLeaveImmediately(isDirty: true, isSaving: true))

        #expect(!UnsavedDraftDecision.requiresPrompt(isDirty: false, isSaving: true))
    }

    @Test func journalEditorDirtyMatchesByteDifference() {
        // Mirrors JournalEditorModel.isDirty without a vault: leave must ask when bytes differ.
        let original = "Deniz eski satır.\n"
        let draft = "Deniz yeni satır.\n"
        let isDirty = !draft.utf8.elementsEqual(original.utf8)
        #expect(isDirty)
        #expect(UnsavedDraftDecision.requiresPrompt(isDirty: isDirty, isSaving: false))
        #expect(!UnsavedDraftDecision.requiresPrompt(isDirty: false, isSaving: false))
    }

    @Test func leaveChoicesAreDistinct() {
        #expect(UnsavedDraftLeaveChoice.save != .discard)
        #expect(UnsavedDraftLeaveChoice.discard != .stay)
        #expect(UnsavedDraftLeaveChoice.stay != .save)
    }
}
