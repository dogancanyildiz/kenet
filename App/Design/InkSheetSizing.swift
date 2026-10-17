/// Presentation policy for the iOS shell. Mac presenters keep their existing sizing.
enum InkSheetSizing: Equatable, Sendable {
    case form, fittedForm, detents, plain

    static func resolve(shell: ShellKind, fitsContent: Bool, usesPhoneDetents: Bool = true) -> Self {
        if shell == .split { return fitsContent ? .fittedForm : .form }
        return usesPhoneDetents ? .detents : .plain
    }
}
