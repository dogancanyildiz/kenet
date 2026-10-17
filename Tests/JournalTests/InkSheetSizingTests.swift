import Testing

@testable import Journal

struct InkSheetSizingTests {
    struct Case: Sendable {
        let shell: ShellKind
        let fitsContent: Bool
        let usesPhoneDetents: Bool
        let expected: InkSheetSizing
    }

    @Test(arguments: [
        Case(shell: .split, fitsContent: true, usesPhoneDetents: true, expected: .fittedForm),
        Case(shell: .split, fitsContent: false, usesPhoneDetents: true, expected: .form),
        Case(shell: .split, fitsContent: true, usesPhoneDetents: false, expected: .fittedForm),
        Case(shell: .split, fitsContent: false, usesPhoneDetents: false, expected: .form),
        Case(shell: .tabs, fitsContent: true, usesPhoneDetents: true, expected: .detents),
        Case(shell: .tabs, fitsContent: false, usesPhoneDetents: true, expected: .detents),
        Case(shell: .tabs, fitsContent: true, usesPhoneDetents: false, expected: .plain),
        Case(shell: .tabs, fitsContent: false, usesPhoneDetents: false, expected: .plain),
    ])
    func presentation(_ row: Case) {
        #expect(
            InkSheetSizing.resolve(
                shell: row.shell, fitsContent: row.fitsContent, usesPhoneDetents: row.usesPhoneDetents)
                == row.expected)
    }
}
