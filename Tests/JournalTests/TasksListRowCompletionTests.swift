import Testing

@testable import Journal

struct TasksListRowCompletionTests {
    @Test func reopenableClosedRowAllowsToggleWhenCompletedFlagIsFalse() {
        let action = TasksListRowCompletion.resolve(
            isClosed: true, completed: false, allowsReopening: true, isBusy: false, canAddEvent: true)
        #expect(action.canToggleCompletion)
        // Catalog key (not localized display); callers pass it as LocalizedStringKey.
        #expect(action.boxAccessibilityLabelKey == "Görevi yeniden aç")
    }

    @Test func completedFlagBlocksReopenEvenWhenAllowsReopening() {
        // Documents the regression: callers that pass `completed: row.isClosed` make this fail.
        let action = TasksListRowCompletion.resolve(
            isClosed: true, completed: true, allowsReopening: true, isBusy: false, canAddEvent: true)
        #expect(!action.canToggleCompletion)
        #expect(action.boxAccessibilityLabelKey == "Görevi yeniden aç")
    }

    @Test func openRowUsesCompleteLabel() {
        let action = TasksListRowCompletion.resolve(
            isClosed: false, completed: false, allowsReopening: true, isBusy: false, canAddEvent: true)
        #expect(action.canToggleCompletion)
        #expect(action.boxAccessibilityLabelKey == "Görevi tamamla")
    }

    @Test func closedWithoutReopeningCannotToggle() {
        let action = TasksListRowCompletion.resolve(
            isClosed: true, completed: false, allowsReopening: false, isBusy: false, canAddEvent: true)
        #expect(!action.canToggleCompletion)
        #expect(action.boxAccessibilityLabelKey == "Görevi tamamla")
    }

    @Test func busyOrReadOnlyBlocksToggle() {
        #expect(
            !TasksListRowCompletion.resolve(
                isClosed: false, completed: false, allowsReopening: true, isBusy: true,
                canAddEvent: true
            ).canToggleCompletion)
        #expect(
            !TasksListRowCompletion.resolve(
                isClosed: false, completed: false, allowsReopening: true, isBusy: false,
                canAddEvent: false
            ).canToggleCompletion)
    }
}
