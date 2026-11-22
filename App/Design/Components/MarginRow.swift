import SwiftUI

/// Content type selects the typeface (Şafak rule 1): vault words use ``Font.ink.content``;
/// external sources stay on the system body style.
enum MarginRowKind: Sendable {
    /// Vault-sourced copy (events, tasks, goals, diary): ``Font.ink.content``.
    case vault
    /// Non-vault sources (calendar, system): SF Pro body.
    case external

    var contentFont: Font {
        switch self {
        case .vault: .ink.content
        case .external: .body
        }
    }
}

/// Shared edge-column row skeleton for tasks, goals, events, and calendar items.
struct MarginRow<Mark: View, Primary: View, Secondary: View, Trailing: View>: View {
    let kind: MarginRowKind
    @ViewBuilder var mark: () -> Mark
    var time: String? = nil
    @ViewBuilder var primary: () -> Primary
    @ViewBuilder var secondary: () -> Secondary
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var gutter = InkSpacing.gutter

    private var stacksChrome: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        Group {
            if stacksChrome {
                accessibilityLayout
            } else {
                standardLayout
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var standardLayout: some View {
        // Mark stays top-aligned with the block; trailing value aligns to the first line baseline.
        // At xxL and xxxL a time row narrower than a card of a 375 pt screen puts its time above
        // the text; one container either way, so the text keeps its identity.
        let stackingWidth =
            hasMark || time == nil
            ? nil
            : InkSpacing.timeStackingWidth(
                narrowWidth: InkSpacing.narrowCardRowWidth, dynamicTypeSize: dynamicTypeSize)
        let layout =
            stackingWidth == nil
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 10))
            : AnyLayout(
                InkTimeRowLayout(gap: 10, stacksBelowWidth: stackingWidth))
        return layout {
            if !hasMark, let time {
                // Grows past the gutter rather than wrapping (large text, 12-hour times).
                InkTimeColumn(text: time, minWidth: gutter, alignment: .center)
                    .accessibilityElement(children: .contain)
            } else {
                edgeColumn {
                    if hasMark { mark() }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    primary()
                        .font(kind.contentFont)
                    secondary()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing()
            }
        }
    }

    /// Accessibility sizes: the mark sits above the text (design.md "Büyük yazı"). The edge
    /// column scales with the text (`gutter` is ~137 pt at AX5): beside the text it left a
    /// 320 pt row a few letters per line, so words broke mid-word.
    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            if hasMark {
                mark()
                    .accessibilityElement(children: .contain)
            }
            if let time {
                timeLabel(time)
            }
            primary()
                .font(kind.contentFont)
            secondary()
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hasMark: Bool {
        !(Mark.self == EmptyView.self)
    }

    private func edgeColumn<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: gutter, alignment: .center)
            .accessibilityElement(children: .contain)
    }

    /// The time on a line of its own (accessibility sizes). One line: where the row is narrower
    /// than the time (a 12-hour time at AX5 on a 320 pt screen) the time shrinks, it never wraps.
    private func timeLabel(_ time: String) -> some View {
        Text(verbatim: time)
            .font(.ink.time)
            .foregroundStyle(.ink.secondaryText)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

extension MarginRow where Secondary == EmptyView, Trailing == EmptyView {
    init(
        kind: MarginRowKind,
        @ViewBuilder mark: @escaping () -> Mark,
        time: String? = nil,
        @ViewBuilder primary: @escaping () -> Primary
    ) {
        self.kind = kind
        self.mark = mark
        self.time = time
        self.primary = primary
        self.secondary = { EmptyView() }
        self.trailing = { EmptyView() }
    }
}

extension MarginRow where Secondary == EmptyView {
    init(
        kind: MarginRowKind,
        @ViewBuilder mark: @escaping () -> Mark,
        time: String? = nil,
        @ViewBuilder primary: @escaping () -> Primary,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.kind = kind
        self.mark = mark
        self.time = time
        self.primary = primary
        self.secondary = { EmptyView() }
        self.trailing = trailing
    }
}

extension MarginRow where Trailing == EmptyView {
    init(
        kind: MarginRowKind,
        @ViewBuilder mark: @escaping () -> Mark,
        time: String? = nil,
        @ViewBuilder primary: @escaping () -> Primary,
        @ViewBuilder secondary: @escaping () -> Secondary
    ) {
        self.kind = kind
        self.mark = mark
        self.time = time
        self.primary = primary
        self.secondary = secondary
        self.trailing = { EmptyView() }
    }
}

extension MarginRow where Mark == EmptyView, Secondary == EmptyView, Trailing == EmptyView {
    init(kind: MarginRowKind, time: String?, @ViewBuilder primary: @escaping () -> Primary) {
        self.kind = kind
        self.mark = { EmptyView() }
        self.time = time
        self.primary = primary
        self.secondary = { EmptyView() }
        self.trailing = { EmptyView() }
    }
}

extension MarginRow where Mark == EmptyView, Trailing == EmptyView {
    init(
        kind: MarginRowKind, time: String?, @ViewBuilder primary: @escaping () -> Primary,
        @ViewBuilder secondary: @escaping () -> Secondary
    ) {
        self.kind = kind
        self.mark = { EmptyView() }
        self.time = time
        self.primary = primary
        self.secondary = secondary
        self.trailing = { EmptyView() }
    }
}

/// Pure layout decision for unit tests (accessibility sizes stack mark, time and value around
/// content).
enum MarginRowLayout {
    case standard
    case accessibilityStacked

    static func resolve(dynamicTypeSize: DynamicTypeSize) -> Self {
        dynamicTypeSize.isAccessibilitySize ? .accessibilityStacked : .standard
    }
}
