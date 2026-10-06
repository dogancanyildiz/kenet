import Foundation

/// Pure completion-toggle decision for ``TasksListRow`` (testable without SwiftUI).
/// Call sites must use ``make(from:allowsReopening:isBusy:canAddEvent:)`` so closed state
/// comes only from ``TaskRow.isClosed`` — there is no separate `completed` flag to mis-wire.
struct TasksListRowCompletion: Equatable, Sendable {
    /// Whether the checkbox, row tap, and VoiceOver action may call `complete`.
    var canToggleCompletion: Bool
    /// String Catalog key for the box / VoiceOver action name.
    var boxAccessibilityLabelKey: String

    /// Factory used by ``TasksListRow`` (Tasks and Project screens).
    static func make(
        from row: TaskRow,
        allowsReopening: Bool,
        isBusy: Bool,
        canAddEvent: Bool
    ) -> Self {
        resolve(
            isClosed: row.isClosed,
            allowsReopening: allowsReopening,
            isBusy: isBusy,
            canAddEvent: canAddEvent)
    }

    static func resolve(
        isClosed: Bool,
        allowsReopening: Bool,
        isBusy: Bool,
        canAddEvent: Bool
    ) -> Self {
        let blocked = (isClosed && !allowsReopening) || isBusy || !canAddEvent
        let labelKey = isClosed && allowsReopening ? "Görevi yeniden aç" : "Görevi tamamla"
        return Self(canToggleCompletion: !blocked, boxAccessibilityLabelKey: labelKey)
    }
}
