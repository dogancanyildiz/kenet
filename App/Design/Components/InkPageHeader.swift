import SwiftUI

/// Where the manşet-row icons sit relative to the manşet (unit-tested).
enum InkPageHeaderLayout: Equatable, Sendable {
    /// Manşet on the left, icons on the same row at its right.
    case inline
    /// Accessibility text sizes: icons on their own row above the manşet, right-aligned,
    /// so the 44 pt targets stay clear of the large title.
    case stacked

    static func resolve(dynamicTypeSize: DynamicTypeSize) -> Self {
        dynamicTypeSize.isAccessibilitySize ? .stacked : .inline
    }
}

/// Manşet row without page margins: sans ``PageHeadline`` plus the page's action icons on its right.
///
/// Use this only where the surrounding container already supplies the horizontal page margin
/// (Today's padded stack). Everywhere else use ``InkPageTitle`` (ScrollView / stack) or
/// ``InkPageTitleRow`` (List), which wrap this view and add the margins.
///
/// `actions` holds ``InkHeaderAction`` / ``InkHeaderMenu`` / ``SearchButton`` views, at most
/// ``InkHeaderActionChrome/maximumCount``; search goes last (rightmost).
/// With no actions the view draws exactly what ``PageHeadline`` draws.
struct InkPageHeader<Actions: View>: View {
    private enum Title {
        case key(LocalizedStringKey)
        case verbatim(String)
    }

    private let title: Title
    private let shortTitle: String?
    private let byline: String?
    private var bylineText: Text? = nil
    /// A small view on the title's trailing side (hedef ayrıntısı: the period pill).
    private var titleAccessory: AnyView? = nil
    private let fitsOneLine: Bool
    private let actions: Actions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.inkHeaderBackTitle) private var backTitle
    #if os(iOS)
        @Environment(\.shellKind) private var shellKind
    #endif

    init(
        _ title: LocalizedStringKey, byline: String? = nil, @ViewBuilder actions: () -> Actions
    ) {
        self.title = .key(title)
        self.shortTitle = nil
        self.byline = byline
        self.fitsOneLine = false
        self.actions = actions()
    }

    /// - Parameters:
    ///   - shortTitle: shorter form tried when `fitsOneLine` and the full title is too wide.
    ///   - fitsOneLine: keep the manşet on one line by shrinking (see ``PageHeadline``).
    init(
        verbatim title: String, shortTitle: String? = nil, byline: String? = nil,
        fitsOneLine: Bool = false, @ViewBuilder actions: () -> Actions
    ) {
        self.title = .verbatim(title)
        self.shortTitle = shortTitle
        self.byline = byline
        self.fitsOneLine = fitsOneLine
        self.actions = actions()
    }

    var body: some View {
        if let backTitle = drawnBackTitle {
            subpageBody(backTitle: backTitle)
                .preference(key: InkHeaderBackShownKey.self, value: true)
        } else if Actions.self == EmptyView.self && titleAccessory == nil {
            headline
        } else {
            switch InkPageHeaderLayout.resolve(dynamicTypeSize: dynamicTypeSize) {
            case .inline:
                HStack(alignment: .firstTextBaseline, spacing: InkHeaderActionChrome.spacing) {
                    headline
                    titleAccessory
                    actionGroup
                }
            case .stacked:
                VStack(alignment: .leading, spacing: InkSpacing.row) {
                    HStack(spacing: InkHeaderActionChrome.spacing) {
                        Spacer(minLength: 0)
                        titleAccessory
                        actionGroup
                    }
                    headline
                }
            }
        }
    }

    /// The back item this manşet draws: only on a subpage of the iPhone tab shell. Elsewhere the
    /// system bar keeps its own back button.
    private var drawnBackTitle: Text? {
        #if os(iOS)
            shellKind == .tabs ? backTitle : nil
        #else
            nil
        #endif
    }

    /// Subpage: "‹ <parent>" and the page's icons on one row, the title (title1) below it.
    private func subpageBody(backTitle: Text) -> some View {
        VStack(alignment: .leading, spacing: InkSpacing.row / 2) {
            HStack(spacing: InkHeaderActionChrome.spacing) {
                InkBackButton(title: backTitle)
                Spacer(minLength: 0)
                if Actions.self != EmptyView.self {
                    actionGroup
                }
            }
            HStack(alignment: .center, spacing: InkHeaderActionChrome.spacing) {
                headline
                    .environment(\.inkPageHeadlineIsSubpage, true)
                titleAccessory
            }
        }
    }

    private var actionGroup: some View {
        // Plain buttons in the slot (``SearchButton``) draw as utility icons; ``InkHeaderAction``
        // and ``InkHeaderMenu`` set their own style and are not affected.
        actions.buttonStyle(InkHeaderButtonStyle())
            .environment(\.isInkHeaderActionSlot, true)
    }

    @ViewBuilder private var headline: some View {
        switch title {
        case .key(let key):
            PageHeadline(key, byline: byline).withBylineText(bylineText)
        case .verbatim(let text):
            PageHeadline(
                title: text, shortTitle: shortTitle, byline: byline, fitsOneLine: fitsOneLine
            )
            .withBylineText(bylineText)
        }
    }
}

extension InkPageHeader {
    /// A styled byline (bold count, warning carried-over part) in place of the plain one.
    func byline(_ text: Text?) -> Self {
        var copy = self
        copy.bylineText = text
        return copy
    }

    /// A small view beside the title: on its trailing side on a subpage, before the icons
    /// elsewhere.
    func titleAccessory(_ view: some View) -> Self {
        var copy = self
        copy.titleAccessory = AnyView(view)
        return copy
    }
}

extension PageHeadline {
    fileprivate func withBylineText(_ text: Text?) -> Self {
        var copy = self
        if let text { copy.bylineText = text }
        return copy
    }
}

extension InkPageHeader where Actions == EmptyView {
    init(_ title: LocalizedStringKey, byline: String? = nil) {
        self.init(title, byline: byline) { EmptyView() }
    }

    init(
        verbatim title: String, shortTitle: String? = nil, byline: String? = nil,
        fitsOneLine: Bool = false
    ) {
        self.init(
            verbatim: title, shortTitle: shortTitle, byline: byline, fitsOneLine: fitsOneLine
        ) { EmptyView() }
    }
}

/// The subpage back item in the iPhone tab shell: "‹ <parent page>" in accent, 44 pt tall.
/// It replaces the system bar's glass back button (the bar is hidden on such a page).
struct InkBackButton: View {
    let title: Text
    /// `false`: only "‹" in a round chip (drawing: day screen); VoiceOver still reads the title.
    var showsTitle = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            if showsTitle {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                        .accessibilityHidden(true)
                    title
                        .lineLimit(1)
                }
                .font(.body)
                .foregroundStyle(.ink.accent)
                .frame(minHeight: TapTarget.minimumLength)
                .contentShape(Rectangle())
            } else {
                Image(systemName: "chevron.left")
                    .fontWeight(.semibold)
                    .foregroundStyle(.ink.text)
                    .inkHeaderIconChip()
                    .tapTarget()
            }
        }
        .buttonStyle(.plain)
        .inkPointerHighlight()
        .accessibilityLabel(title)
        .accessibilityHint(Text("Geri"))
        .accessibilityIdentifier("button.back")
    }
}

/// A subpage's navigation row for a page that does not use ``InkPageHeader`` (the day screen):
/// the back item on the left, `center` in the middle (the month picker), the page's icons on the
/// right. In the iPhone tab shell it hides the system bar the same way (``InkHeaderBackShownKey``);
/// elsewhere it draws only `center` and the icons, and the system bar keeps its back button.
/// The page applies ``View/inkPageNavigationTitle(_:)`` around it, which supplies the parent's
/// title.
struct InkNavigationRow<Center: View, Actions: View>: View {
    /// `false`: the back item is a round "‹" chip without the parent's name (day screen).
    var backShowsTitle = true
    @ViewBuilder var center: () -> Center
    @ViewBuilder var actions: () -> Actions
    @Environment(\.inkHeaderBackTitle) private var backTitle
    #if os(iOS)
        @Environment(\.shellKind) private var shellKind
    #endif

    private var drawnBackTitle: Text? {
        #if os(iOS)
            shellKind == .tabs ? backTitle : nil
        #else
            nil
        #endif
    }

    var body: some View {
        ZStack {
            center()
            HStack(spacing: InkHeaderActionChrome.spacing) {
                if let drawnBackTitle {
                    InkBackButton(title: drawnBackTitle, showsTitle: backShowsTitle)
                }
                Spacer(minLength: 0)
                actions()
                    .buttonStyle(InkHeaderButtonStyle())
                    .environment(\.isInkHeaderActionSlot, true)
            }
        }
        .preference(key: InkHeaderBackShownKey.self, value: drawnBackTitle != nil)
    }
}
