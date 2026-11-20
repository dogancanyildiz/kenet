import SwiftUI

/// Where the manşet-row icons sit relative to the manşet (unit-tested).
enum InkPageHeaderLayout: Equatable, Sendable {
    /// Manşet on the left, icons on the same row at its right.
    case inline
    /// Accessibility text sizes: icons on their own row above the manşet, right-aligned,
    /// so the 44 pt targets stay clear of the large title. Icons wider than the row together
    /// continue on a second row (``InkStackedHeaderRows``).
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
    /// Accessibility identifier of the title and byline element (UI tests read the künye there).
    private var headlineIdentifier: String? = nil
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
            // One layout holds the same three children at every text size, so the manşet and its
            // künye stay the same view while the text grows: the accessibility audit reads a text
            // that changes views as it grows (if/else, switch) as clipped (``SectionHeader``).
            let layout =
                switch InkPageHeaderLayout.resolve(dynamicTypeSize: dynamicTypeSize) {
                case .inline:
                    AnyLayout(
                        HStackLayout(alignment: .firstTextBaseline, spacing: InkHeaderActionChrome.spacing))
                case .stacked:
                    AnyLayout(InkStackedHeaderLayout())
                }
            layout {
                headline
                titleAccessory
                actionGroup
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
        // Accessibility sizes: icons that do not fit beside the back item go under it, so the
        // parent's name wraps between words, not letter by letter ("Gör / evl / er" at 320 pt).
        let row =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(InkBackRowLayout())
            : AnyLayout(HStackLayout(spacing: InkHeaderActionChrome.spacing))
        // The title accessory (hedef ayrıntısı: the period pill) goes under the title there: beside
        // it the pill was cut ("G… · 20…").
        let titleRow =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: InkHeaderActionChrome.spacing))
            : AnyLayout(HStackLayout(alignment: .center, spacing: InkHeaderActionChrome.spacing))
        return VStack(alignment: .leading, spacing: InkSpacing.row / 2) {
            row {
                InkBackButton(title: backTitle)
                Spacer(minLength: 0)
                if Actions.self != EmptyView.self {
                    actionGroup
                }
            }
            titleRow {
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
        if let headlineIdentifier {
            headlineText.accessibilityIdentifier(headlineIdentifier)
        } else {
            headlineText
        }
    }

    @ViewBuilder private var headlineText: some View {
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

    /// Names the title and byline element, which reads as one ("Görevler, 14 açık").
    func headlineIdentifier(_ identifier: String) -> Self {
        var copy = self
        copy.headlineIdentifier = identifier
        return copy
    }

    /// A small view beside the title: on its trailing side on a subpage (under the title at
    /// accessibility text sizes), before the icons elsewhere.
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

/// Icon rows of the stacked manşet (unit-tested): which icons share a row.
enum InkStackedHeaderRows {
    /// Gap between two icon rows, and between two icons (``InkHeaderActionChrome/spacing``).
    static let spacing = InkHeaderActionChrome.spacing

    /// Icons fill a row in order; one that does not fit starts the next row. Three chips at the
    /// largest text size are wider than a 320 pt screen: on one row the first one left the screen.
    static func resolve(widths: [CGFloat], available: CGFloat?) -> [Range<Int>] {
        guard !widths.isEmpty else { return [] }
        guard let available else { return [0..<widths.count] }
        var rows: [Range<Int>] = []
        var start = 0
        var used: CGFloat = 0
        for (index, width) in widths.enumerated() {
            let next = index == start ? width : used + spacing + width
            if index > start && next > available {
                rows.append(start..<index)
                start = index
                used = width
            } else {
                used = next
            }
        }
        rows.append(start..<widths.count)
        return rows
    }
}

/// Icons of a manşet at accessibility text sizes, measured at their own size and set on as many
/// right-aligned rows as the width needs.
private struct InkHeaderIconRows {
    private struct Row {
        var items: Range<Int>
        var width: CGFloat
        var height: CGFloat
    }

    private let sizes: [CGSize]
    private let rows: [Row]
    /// Width of the widest row.
    let width: CGFloat
    /// Height of all rows with the gaps between them; zero without icons.
    let height: CGFloat
    var isEmpty: Bool { rows.isEmpty }
    var isOneRow: Bool { rows.count == 1 }

    init(_ icons: LayoutSubviews, width available: CGFloat?) {
        let spacing = InkStackedHeaderRows.spacing
        let sizes = icons.map { $0.sizeThatFits(.unspecified) }
        let rows = InkStackedHeaderRows.resolve(widths: sizes.map(\.width), available: available).map { items in
            let row = sizes[items]
            return Row(
                items: items,
                width: row.reduce(0) { $0 + $1.width } + spacing * CGFloat(items.count - 1),
                height: row.reduce(0) { max($0, $1.height) })
        }
        self.sizes = sizes
        self.rows = rows
        width = rows.reduce(0) { max($0, $1.width) }
        height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
    }

    /// Places the rows from `top` down, each ending at `trailing`.
    func place(_ icons: LayoutSubviews, top: CGFloat, trailing: CGFloat) {
        let spacing = InkStackedHeaderRows.spacing
        var y = top
        for row in rows {
            var x = trailing - row.width
            for index in row.items {
                let size = sizes[index]
                icons[icons.startIndex + index].place(
                    at: CGPoint(x: x, y: y + row.height / 2), anchor: .leading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }
}

/// The manşet at accessibility text sizes: the first subview (the manşet and its künye) takes the
/// full width below; every other subview (title accessory, icons) sits above it, right-aligned,
/// on as many rows as the width needs.
private struct InkStackedHeaderLayout: Layout {
    /// Height of the icon rows and the gap under them.
    private func top(_ icons: InkHeaderIconRows) -> CGFloat {
        icons.isEmpty ? 0 : icons.height + InkSpacing.row
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let headline = subviews.first else { return .zero }
        let icons = InkHeaderIconRows(subviews.dropFirst(), width: proposal.width)
        let headlineSize = headline.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(
            width: proposal.width ?? max(headlineSize.width, icons.width),
            height: top(icons) + headlineSize.height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        guard let headline = subviews.first else { return }
        let icons = InkHeaderIconRows(subviews.dropFirst(), width: bounds.width)
        icons.place(subviews.dropFirst(), top: bounds.minY, trailing: bounds.maxX)
        let top = top(icons)
        headline.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + top), anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: max(bounds.height - top, 0)))
    }
}

/// A subpage's navigation row at accessibility text sizes. Subviews: the back item, a spacer
/// (the row is an `HStack` at the other sizes), then the icons. The icons stay beside the back
/// item while its title fits one line there; otherwise the back item takes the full width and
/// the icons go under it, right-aligned.
private struct InkBackRowLayout: Layout {
    private struct Measured {
        var back: CGSize
        var icons: InkHeaderIconRows
        var isOneRow: Bool
        var height: CGFloat {
            if isOneRow { return max(back.height, icons.height) }
            return back.height + InkStackedHeaderRows.spacing + icons.height
        }
    }

    private func measure(_ subviews: Subviews, width: CGFloat?) -> Measured {
        let icons = InkHeaderIconRows(subviews.dropFirst(2), width: width)
        let ideal = subviews[0].sizeThatFits(.unspecified)
        guard let width else { return Measured(back: ideal, icons: icons, isOneRow: true) }
        if icons.isEmpty {
            let back = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
            return Measured(back: back, icons: icons, isOneRow: true)
        }
        if icons.isOneRow, ideal.width + InkStackedHeaderRows.spacing + icons.width <= width {
            return Measured(back: ideal, icons: icons, isOneRow: true)
        }
        let back = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
        return Measured(back: back, icons: icons, isOneRow: false)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count >= 2 else { return .zero }
        let measured = measure(subviews, width: proposal.width)
        let ideal = measured.back.width + InkStackedHeaderRows.spacing + measured.icons.width
        return CGSize(width: proposal.width ?? ideal, height: measured.height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        guard subviews.count >= 2 else { return }
        let measured = measure(subviews, width: bounds.width)
        let back = ProposedViewSize(measured.back)
        subviews[1].place(at: bounds.origin, proposal: .zero)
        if measured.isOneRow {
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: back)
            measured.icons.place(
                subviews.dropFirst(2), top: bounds.midY - measured.icons.height / 2, trailing: bounds.maxX)
        } else {
            subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: back)
            measured.icons.place(
                subviews.dropFirst(2), top: bounds.minY + measured.back.height + InkStackedHeaderRows.spacing,
                trailing: bounds.maxX)
        }
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
                    // No line limit: a long name or a large text size wraps the title, never
                    // cuts it (audit "Text clipped"); one line otherwise.
                    title
                        .fixedSize(horizontal: false, vertical: true)
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
        // Each slot is one subview, empty or not (``InkNavigationRowLayout``). The back item and
        // the icons stop growing at the day manşet's cap, so they fit a 320 pt screen at every
        // text size; the middle item keeps the full size.
        InkNavigationRowLayout {
            HStack(spacing: 0) {
                if let drawnBackTitle {
                    InkBackButton(title: drawnBackTitle, showsTitle: backShowsTitle)
                }
            }
            .dynamicTypeSize(...InkDayHeaderLayout.largestActionSize)
            HStack(spacing: 0) { center() }
            HStack(spacing: InkHeaderActionChrome.spacing) {
                actions()
                    .buttonStyle(InkHeaderButtonStyle())
                    .environment(\.isInkHeaderActionSlot, true)
            }
            .dynamicTypeSize(...InkDayHeaderLayout.largestActionSize)
        }
        .preference(key: InkHeaderBackShownKey.self, value: drawnBackTitle != nil)
    }
}

/// Where the middle item of a navigation row sits (unit-tested).
enum InkNavigationRowArrangement: Equatable, Sendable {
    /// In the middle of the row, the back item and the icons at its ends (the drawing).
    case centered
    /// In the middle of the room left between the back item and the icons: the row's own middle
    /// would put it under one of them.
    case between
    /// On its own row below: the three do not fit one row.
    case below

    /// Smallest gap between the middle item and a neighbor.
    static let gap = InkHeaderActionChrome.spacing
    /// Gap between the two rows of ``below``.
    static let rowSpacing: CGFloat = 4

    static func resolve(width: CGFloat, leading: CGFloat, center: CGFloat, trailing: CGFloat) -> Self {
        guard center > 0 else { return .centered }
        if (width - center) / 2 >= max(leading, trailing) + gap { return .centered }
        return taken(leading) + center + taken(trailing) <= width ? .between : .below
    }

    /// A side's width with its gap; an empty side takes none.
    static func taken(_ side: CGFloat) -> CGFloat { side > 0 ? side + gap : 0 }
}

/// Lays out a navigation row's three slots (back item, middle item, icons) so the middle item
/// never runs under the icons at a large text size or on a narrow screen.
private struct InkNavigationRowLayout: Layout {
    private struct Measured {
        var leading: CGSize
        var center: CGSize
        var trailing: CGSize
        var arrangement: InkNavigationRowArrangement
        var sidesHeight: CGFloat { max(leading.height, trailing.height) }
        var height: CGFloat {
            switch arrangement {
            case .centered, .between: max(sidesHeight, center.height)
            case .below: sidesHeight + InkNavigationRowArrangement.rowSpacing + center.height
            }
        }
    }

    private func measure(_ subviews: Subviews, width: CGFloat?) -> Measured {
        let leading = subviews[0].sizeThatFits(.unspecified)
        var center = subviews[1].sizeThatFits(.unspecified)
        let trailing = subviews[2].sizeThatFits(.unspecified)
        guard let width else {
            return Measured(leading: leading, center: center, trailing: trailing, arrangement: .between)
        }
        let arrangement = InkNavigationRowArrangement.resolve(
            width: width, leading: leading.width, center: center.width, trailing: trailing.width)
        if arrangement == .below {
            // Its own row: wider than the row, it wraps instead of leaving the screen.
            center = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
        }
        return Measured(leading: leading, center: center, trailing: trailing, arrangement: arrangement)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let measured = measure(subviews, width: proposal.width)
        let ideal =
            InkNavigationRowArrangement.taken(measured.leading.width) + measured.center.width
            + InkNavigationRowArrangement.taken(measured.trailing.width)
        return CGSize(width: proposal.width ?? ideal, height: measured.height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        guard subviews.count == 3 else { return }
        let measured = measure(subviews, width: bounds.width)
        let stacked = measured.arrangement == .below
        let sidesMidY = stacked ? bounds.minY + measured.sidesHeight / 2 : bounds.midY
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: sidesMidY), anchor: .leading,
            proposal: ProposedViewSize(measured.leading))
        subviews[2].place(
            at: CGPoint(x: bounds.maxX, y: sidesMidY), anchor: .trailing,
            proposal: ProposedViewSize(measured.trailing))
        let center = ProposedViewSize(measured.center)
        switch measured.arrangement {
        case .centered:
            subviews[1].place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: center)
        case .between:
            let start = bounds.minX + InkNavigationRowArrangement.taken(measured.leading.width)
            let end = bounds.maxX - InkNavigationRowArrangement.taken(measured.trailing.width)
            subviews[1].place(at: CGPoint(x: (start + end) / 2, y: bounds.midY), anchor: .center, proposal: center)
        case .below:
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.maxY), anchor: .bottomLeading, proposal: center)
        }
    }
}
