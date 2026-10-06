import Foundation

/// Pure completion-toggle decision for ``TasksListRow`` (testable without SwiftUI).
struct TasksListRowCompletion: Equatable, Sendable {
    /// Whether the checkbox, row tap, and VoiceOver action may call `complete`.
    var canToggleCompletion: Bool
    /// String Catalog key for the box / VoiceOver action name.
    var boxAccessibilityLabelKey: String

    /// - Parameter completed: Caller cue that the row is already treated as done in the list
    ///   (Today's optimistic completion). Must stay `false` when the only closed signal is
    ///   `row.isClosed` and `allowsReopening` is true — otherwise reopen is blocked.
    static func resolve(
        isClosed: Bool,
        completed: Bool,
        allowsReopening: Bool,
        isBusy: Bool,
        canAddEvent: Bool
    ) -> Self {
        let blocked = (isClosed && !allowsReopening) || completed || isBusy || !canAddEvent
        let labelKey = isClosed && allowsReopening ? "Görevi yeniden aç" : "Görevi tamamla"
        return Self(canToggleCompletion: !blocked, boxAccessibilityLabelKey: labelKey)
    }
}
