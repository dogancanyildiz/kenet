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

    @MainActor
    @Test func entityEditDraftCombinesChildDirtyFlags() {
        #expect(!EntityEditorDraft.combine(current: false, next: false))
        #expect(EntityEditorDraft.combine(current: false, next: true))
        #expect(EntityEditorDraft.combine(current: true, next: false))
        #expect(
            UnsavedDraftDecision.requiresPrompt(
                isDirty: EntityEditorDraft.combine(current: false, next: true), isSaving: false))
    }

    @MainActor
    @Test func entityEditDraftKeepsOffscreenFieldDirty() {
        let draft = EntityEditorDraft()
        draft.report(id: "field-a", dirty: true)
        draft.report(id: "field-b", dirty: false)
        #expect(draft.isDirty)
        draft.report(id: "field-a", dirty: false)
        #expect(!draft.isDirty)
    }

    @MainActor
    @Test func removingFieldClearsDraftIds() {
        let draft = EntityEditorDraft()
        draft.report(id: "field:notes", dirty: true)
        draft.report(id: "field:notes.0", dirty: true)
        draft.report(id: "field:other", dirty: true)
        draft.report(id: "typed:birthday", dirty: true)
        draft.report(id: "field:a", dirty: true)
        draft.report(id: "field:a.b", dirty: true)
        #expect(draft.isDirty)
        // Exact ids only: removing "notes" clears its list child, not an unrelated key.
        draft.clear(ids: ["field:notes", "field:notes.0"])
        #expect(draft.isDirty)
        // Removing "a" must not clear dotted YAML key "a.b".
        draft.clear(ids: ["field:a"])
        #expect(draft.isDirty)
        draft.clear(id: "typed:birthday")
        draft.clear(id: "field:other")
        #expect(draft.isDirty)
        draft.clear(id: "field:a.b")
        #expect(!draft.isDirty)
    }

    @Test func failedSaveDoesNotClearCommittedText() {
        var saved = "eski"
        let committed = "yeni"
        EntityEditorSaveMark.commitIfSaved(committed, success: false, into: &saved)
        #expect(saved == "eski")
        #expect(committed != saved)
        EntityEditorSaveMark.commitIfSaved(committed, success: true, into: &saved)
        #expect(saved == "yeni")
    }
}
