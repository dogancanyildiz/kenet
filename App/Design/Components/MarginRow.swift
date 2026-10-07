import SwiftUI

/// Content type selects the typeface (Mürekkep rule 1): vault words are serif; external sources are sans.
enum MarginRowKind: Sendable {
    /// Vault-sourced copy (events, tasks, goals, journal): New York via ``Font.ink.content``.
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
        HStack(alignment: .top, spacing: 10) {
            edgeColumn {
                if hasMark {
                    mark()
                } else if let time {
                    timeLabel(time)
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

    private var accessibilityLayout: some View {
        HStack(alignment: .top, spacing: 10) {
            if hasMark {
                edgeColumn { mark() }
            }
            VStack(alignment: .leading, spacing: 4) {
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
    }

    private var hasMark: Bool {
        !(Mark.self == EmptyView.self)
    }

    private func edgeColumn<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: gutter, alignment: .center)
            .accessibilityElement(children: .contain)
    }

    private func timeLabel(_ time: String) -> some View {
        Text(verbatim: time)
            .font(.ink.time)
            .foregroundStyle(.ink.secondaryText)
            .monospacedDigit()
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

/// Pure layout decision for unit tests (accessibility sizes stack time/value around content).
enum MarginRowLayout {
    case standard
    case accessibilityStacked

    static func resolve(dynamicTypeSize: DynamicTypeSize) -> Self {
        dynamicTypeSize.isAccessibilitySize ? .accessibilityStacked : .standard
    }
}
