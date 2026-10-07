import SwiftUI

/// Pure state rules for ``InkFilterField`` (unit-tested).
enum InkFilterFieldChrome {
    /// Border: accent while focused, control line otherwise.
    static func borderToken(isFocused: Bool) -> InkButtonChrome.Token {
        isFocused ? .accent : .control
    }

    /// The clear button shows only while there is text.
    static func showsClear(text: String) -> Bool { !text.isEmpty }
}

/// In-page filter / search field: well background, control-line border (accent while focused),
/// serif text, italic serif placeholder, and a clear button while there is text.
/// It is the Search page's field as a component.
///
/// Draws no horizontal page margin of its own. Submission, key presses and keyboard traits
/// are added from outside (`.onSubmit`, `.onKeyPress`, `.submitLabel`,
/// `.autocorrectionDisabled()`); they reach the inner `TextField`.
struct InkFilterField: View {
    private let prompt: LocalizedStringKey
    @Binding private var text: String
    private let externalFocus: FocusState<Bool>.Binding?
    private let identifier: String?
    private let clearIdentifier: String?
    private let showsClearButton: Bool
    @FocusState private var internalFocus: Bool

    /// - Parameters:
    ///   - prompt: placeholder; also the field's accessibility label.
    ///   - isFocused: bind a caller-owned `@FocusState` to read or move focus; omit otherwise.
    ///   - identifier: accessibility identifier of the text field (e.g. `field.search`).
    ///   - clearIdentifier: accessibility identifier of the clear button.
    ///   - showsClearButton: `false` for a form field (a labeled value, not a search): the
    ///     clear button never appears and the text keeps the full width.
    init(
        _ prompt: LocalizedStringKey, text: Binding<String>,
        isFocused: FocusState<Bool>.Binding? = nil, identifier: String? = nil,
        clearIdentifier: String? = nil, showsClearButton: Bool = true
    ) {
        self.prompt = prompt
        _text = text
        externalFocus = isFocused
        self.identifier = identifier
        self.clearIdentifier = clearIdentifier
        self.showsClearButton = showsClearButton
    }

    private var focus: FocusState<Bool>.Binding { externalFocus ?? $internalFocus }
    private var showsClear: Bool {
        showsClearButton && InkFilterFieldChrome.showsClear(text: text)
    }

    var body: some View {
        TextField(prompt, text: $text, prompt: Text(prompt).font(.ink.placeholder))
            .textFieldStyle(.plain)
            .font(.ink.content)
            .foregroundStyle(.ink.text)
            .focused(focus)
            .inkAccessibilityIdentifier(identifier)
            .padding(.leading, 12)
            .padding(.trailing, showsClear ? InkFilterFieldMetrics.clearSlot : 12)
            .padding(.vertical, 10)
            .background(
                Color.ink.well,
                in: RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
                    .strokeBorder(
                        InkButtonChrome.color(
                            for: InkFilterFieldChrome.borderToken(isFocused: focus.wrappedValue)),
                        lineWidth: InkStroke.control)
            )
            .overlay(alignment: .trailing) {
                if showsClear {
                    Button {
                        text = ""
                        focus.wrappedValue = true
                    } label: {
                        Label("Temizle", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(Color.ink.secondaryText)
                            // The icon stops growing at AX2 so it stays inside its slot.
                            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                            .frame(minWidth: InkFilterFieldMetrics.clearSlot)
                            .tapTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Temizle")
                    .inkAccessibilityIdentifier(clearIdentifier)
                }
            }
    }
}

private enum InkFilterFieldMetrics {
    /// Trailing space kept free for the clear button so text never runs under it.
    static let clearSlot: CGFloat = 36
}
