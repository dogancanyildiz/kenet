import Foundation

/// A shell command handed down through the environment (`\.openSearch`) or up to the Mac menu
/// bar as a focused value (`\.openSearch`, `\.goToToday`).
///
/// Equal by identity, not by what it runs: the owner makes it once, in `init` or in a model it
/// keeps, and hands the same value to every body. A closure is never equal to the previous one,
/// so a closure made in `body` reads as a change on every update. On the Mac that rebuilt the
/// app's scene (menu commands, Settings, the menu bar extra), the scene rebuilt the window
/// content, and the content made a new closure again: the app kept updating while nothing
/// moved (docs/architecture.md, "Platform düzeni").
struct ShellAction: Equatable, Sendable {
    private let id = UUID()
    private let perform: @MainActor @Sendable () -> Void

    init(_ perform: @escaping @MainActor @Sendable () -> Void) {
        self.perform = perform
    }

    @MainActor func callAsFunction() {
        perform()
    }

    static func == (lhs: ShellAction, rhs: ShellAction) -> Bool {
        lhs.id == rhs.id
    }

    /// Runs nothing: the environment's default, and the stand-in of hosted tests and previews.
    static let nothing = ShellAction {}
}
