import SwiftUI

/// A card row that opens a page: the title, an optional value on the right, and "›" (drawing:
/// Ayarlar hub, Mac Kasa "Varlık tipleri · 3 özel tip"). It tells a link row from a plain
/// information row. Use it as the label of a `NavigationLink` (iOS) or a `Button` (Mac tab swap),
/// then apply ``View/inkDisclosureRow(_:value:)`` on the link or button.
struct InkDisclosureRowLabel: View {
    let title: Text
    var value: Text? = nil
    /// The trailing mark: "›" opens a page, "↗" (`arrow.up.right`) leaves the app (a web link).
    var symbol = "chevron.right"

    init(_ title: LocalizedStringKey, value: Text? = nil, symbol: String = "chevron.right") {
        self.title = Text(title)
        self.value = value
        self.symbol = symbol
    }

    var body: some View {
        HStack(alignment: .center, spacing: InkSpacing.row) {
            title
                .foregroundStyle(Color.ink.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let value {
                value
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Image(systemName: symbol)
                .font(.ink.weekday)
                .foregroundStyle(Color.ink.secondaryText)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading)
        .padding(.horizontal, InkSpacing.cardPadding)
        .contentShape(Rectangle())
    }
}

extension View {
    /// The link or button around an ``InkDisclosureRowLabel``: plain style (the label colors
    /// itself), and VoiceOver reads the title as the label and the value as its value.
    func inkDisclosureRow(_ title: LocalizedStringKey, value: Text? = nil) -> some View {
        self
            .buttonStyle(.plain)
            .accessibilityLabel(Text(title))
            .modifier(InkDisclosureValue(value: value))
    }
}

private struct InkDisclosureValue: ViewModifier {
    let value: Text?

    @ViewBuilder func body(content: Content) -> some View {
        if let value {
            content.accessibilityValue(value)
        } else {
            content
        }
    }
}
