import SwiftUI

/// Pure rules for the tab family (unit-tested; ``InkTabs`` and the quick-entry mode words
/// both draw through ``View/inkTabWord(isSelected:size:)``).
enum InkTabsChrome {
    /// Tabs answer "pick one of two or three". Four or more options use ``InkLabeledMenu``.
    /// ``InkTabs`` does not block a longer list; this constant is the rule tests check against.
    static let maximumCount = 3
    static let minimumCount = 2

    static func fits(count: Int) -> Bool { (minimumCount...maximumCount).contains(count) }

    /// Selected word: text color; the others: secondary text.
    static func token(isSelected: Bool) -> InkButtonChrome.Token {
        isSelected ? .text : .secondaryText
    }

    /// Underline under the selected word only.
    static func underlineToken(isSelected: Bool) -> InkButtonChrome.Token? {
        isSelected ? .accent : nil
    }

    /// Gap between words on the page-size tab row.
    static let pageSpacing: CGFloat = 20

    /// Smallest side of one tab word: the touch target on iOS; a compact row for the Mac pointer.
    #if os(iOS)
        static let minimumWordLength: CGFloat = TapTarget.minimumLength
    #else
        static let minimumWordLength: CGFloat = 28
    #endif
}

/// Word size of a tab row.
enum InkTabWordSize: Equatable, Sendable {
    /// Under the manşet (``InkTabs``).
    case page
    /// Inside the quick-entry capsule (Olay | Görev); carries its own short underline.
    case compact
}

/// One tab option: a value and its word.
struct InkTabItem<Value: Hashable>: Identifiable {
    fileprivate enum Title {
        case key(LocalizedStringKey)
        case verbatim(String)
    }

    let value: Value
    fileprivate let title: Title
    /// Optional per-tab accessibility identifier.
    let identifier: String?

    var id: Value { value }

    init(_ title: LocalizedStringKey, value: Value, identifier: String? = nil) {
        self.title = .key(title)
        self.value = value
        self.identifier = identifier
    }

    init(verbatim title: String, value: Value, identifier: String? = nil) {
        self.title = .verbatim(title)
        self.value = value
        self.identifier = identifier
    }
}

/// "Pick one" for two or three options: left-aligned words on a rule; the selected word is in
/// text color, semibold, underlined in accent. Place directly under the manşet.
///
/// Draws no horizontal page margin of its own: put it in a padded container or give it
/// `.padding(.horizontal, InkSpacing.margin)` / `.inkListRow()`.
/// At accessibility text sizes the words stack vertically when they no longer fit one row.
struct InkTabs<Value: Hashable>: View {
    @Binding private var selection: Value
    private let items: [InkTabItem<Value>]
    private let identifier: String?
    private let accessibilityLabelPrefix: String?
    @Environment(\.displayScale) private var displayScale

    /// - Parameters:
    ///   - identifier: accessibility identifier of the tab container.
    ///   - accessibilityLabelPrefix: what the tabs belong to when the same words repeat on a
    ///     page (one tab row per goal); each tab is then read as "prefix, word".
    init(
        selection: Binding<Value>, items: [InkTabItem<Value>], identifier: String? = nil,
        accessibilityLabelPrefix: String? = nil
    ) {
        _selection = selection
        self.items = items
        self.identifier = identifier
        self.accessibilityLabelPrefix = accessibilityLabelPrefix
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: InkTabsChrome.pageSpacing) { words(wraps: false) }
                VStack(alignment: .leading, spacing: 0) { words(wraps: true) }
            }
            Rectangle()
                .fill(Color.ink.rule)
                .frame(height: InkStroke.hairline(scale: displayScale))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
        .inkAccessibilityIdentifier(identifier)
    }

    private func words(wraps: Bool) -> some View {
        ForEach(items) { item in
            let selected = item.value == selection
            Button {
                selection = item.value
            } label: {
                // The underline is as wide as the word and sits on the rule; the word stays
                // left-aligned inside its 44 pt target so the first tab starts at the margin.
                title(item)
                    .inkTabWord(isSelected: selected, size: .page)
                    .fixedSize(horizontal: !wraps, vertical: true)
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(
                                InkTabsChrome.underlineToken(isSelected: selected)
                                    .map(InkButtonChrome.color(for:)) ?? Color.clear
                            )
                            .frame(height: InkSize.modeUnderline)
                    }
                    .frame(
                        minWidth: InkTabsChrome.minimumWordLength,
                        minHeight: InkTabsChrome.minimumWordLength, alignment: .bottomLeading
                    )
                    .tapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .inkAccessibilityIdentifier(item.identifier)
            .modifier(InkTabLabelPrefix(prefix: accessibilityLabelPrefix))
        }
    }

    private func title(_ item: InkTabItem<Value>) -> Text {
        switch item.title {
        case .key(let key): Text(key)
        case .verbatim(let text): Text(verbatim: text)
        }
    }
}

/// Reads a tab as "prefix, word": the prefix is put in front of the button's own label.
private struct InkTabLabelPrefix: ViewModifier {
    var prefix: String?

    func body(content: Content) -> some View {
        if let prefix {
            content.accessibilityLabel { word in
                Text(verbatim: prefix)
                word
            }
        } else {
            content
        }
    }
}

extension View {
    /// Shared drawing of one tab word (font, weight, color). `.compact` also draws the short
    /// underline of the quick-entry capsule; ``InkTabs`` draws its own on the rule.
    func inkTabWord(isSelected: Bool, size: InkTabWordSize) -> some View {
        modifier(InkTabWordModifier(isSelected: isSelected, size: size))
    }
}

private struct InkTabWordModifier: ViewModifier {
    var isSelected: Bool
    var size: InkTabWordSize

    func body(content: Content) -> some View {
        let color = InkButtonChrome.color(for: InkTabsChrome.token(isSelected: isSelected))
        switch size {
        case .page:
            content
                .font(Font.ink.byline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(color)
        case .compact:
            content
                .font(isSelected ? Font.ink.section : Font.ink.meta)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(color)
                .fixedSize()
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(
                            InkTabsChrome.underlineToken(isSelected: isSelected)
                                .map(InkButtonChrome.color(for:)) ?? Color.clear
                        )
                        .frame(height: InkSize.modeUnderline)
                        .offset(y: 4)
                }
        }
    }
}
