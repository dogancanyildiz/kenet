import SwiftUI

/// One choice of an ``InkLabeledMenu``.
struct InkMenuOption<Value: Hashable>: Identifiable {
    fileprivate enum Title {
        case key(LocalizedStringKey)
        case verbatim(String)
    }

    let value: Value
    fileprivate let title: Title
    let systemImage: String?

    var id: Value { value }

    init(_ title: LocalizedStringKey, value: Value, systemImage: String? = nil) {
        self.title = .key(title)
        self.value = value
        self.systemImage = systemImage
    }

    init(verbatim title: String, value: Value, systemImage: String? = nil) {
        self.title = .verbatim(title)
        self.value = value
        self.systemImage = systemImage
    }

    fileprivate var text: Text {
        switch title {
        case .key(let key): Text(key)
        case .verbatim(let text): Text(verbatim: text)
        }
    }
}

/// Pure helpers for ``InkLabeledMenu`` (unit-tested).
enum InkLabeledMenuChrome {
    /// Below this many options the pattern asks for ``InkTabs`` instead.
    static let minimumCount = InkTabsChrome.maximumCount + 1

    /// The option shown as the current value; `nil` when the selection is not among the options.
    static func selected<Value: Hashable>(
        _ selection: Value, in sections: [[InkMenuOption<Value>]]
    ) -> InkMenuOption<Value>? {
        for section in sections {
            if let match = section.first(where: { $0.value == selection }) { return match }
        }
        return nil
    }
}

/// "Pick one" for four or more options: on the left a secondary-colored label ("Dönem",
/// "Grupla"), then the selected value and a down chevron in accent. Tapping opens the system
/// menu with a checkmark on the current choice.
///
/// Left-aligned and full width by default; pass `expands: false` to hug the content (two menus
/// on one row). Draws no horizontal page margin of its own.
/// VoiceOver reads label and value as one element with a "double-tap to choose" hint.
struct InkLabeledMenu<Value: Hashable>: View {
    private let label: LocalizedStringKey
    @Binding private var selection: Value
    private let sections: [[InkMenuOption<Value>]]
    private let expands: Bool
    private let identifier: String?
    @Environment(\.isEnabled) private var isEnabled

    init(
        _ label: LocalizedStringKey, selection: Binding<Value>, options: [InkMenuOption<Value>],
        expands: Bool = true, identifier: String? = nil
    ) {
        self.init(
            label, selection: selection, sections: [options], expands: expands,
            identifier: identifier)
    }

    /// Each inner array is one group; groups are separated by a divider in the menu.
    init(
        _ label: LocalizedStringKey, selection: Binding<Value>,
        sections: [[InkMenuOption<Value>]], expands: Bool = true, identifier: String? = nil
    ) {
        self.label = label
        _selection = selection
        self.sections = sections
        self.expands = expands
        self.identifier = identifier
    }

    private var selected: InkMenuOption<Value>? {
        InkLabeledMenuChrome.selected(selection, in: sections)
    }

    var body: some View {
        Menu {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, options in
                Picker(selection: $selection) {
                    ForEach(options) { option in
                        if let systemImage = option.systemImage {
                            Label {
                                option.text
                            } icon: {
                                Image(systemName: systemImage)
                            }
                            .tag(option.value)
                        } else {
                            option.text.tag(option.value)
                        }
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
            }
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) { labelParts(wraps: false) }
                VStack(alignment: .leading, spacing: 2) { labelParts(wraps: true) }
            }
            .font(Font.ink.byline)
            .tapTarget()
            .frame(maxWidth: expands ? .infinity : nil, alignment: .leading)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(Text(label))
        .accessibilityValue(selected?.text ?? Text(verbatim: ""))
        .accessibilityHint(Text("Seçmek için çift dokun"))
        .inkAccessibilityIdentifier(identifier)
    }

    @ViewBuilder private func labelParts(wraps: Bool) -> some View {
        let valueColor = isEnabled ? Color.ink.accent : Color.ink.secondaryText
        Text(label)
            .foregroundStyle(Color.ink.secondaryText)
            .fixedSize(horizontal: !wraps, vertical: true)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            (selected?.text ?? Text(verbatim: ""))
                .fixedSize(horizontal: !wraps, vertical: true)
            Image(systemName: "chevron.down")
                .imageScale(.small)
                .accessibilityHidden(true)
        }
        .foregroundStyle(valueColor)
    }
}
