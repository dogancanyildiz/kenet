import SwiftUI

/// Dawn glow only on Today's scroll content (past days stay flat).
struct TodayGlowBackground: ViewModifier {
    var isToday: Bool

    func body(content: Content) -> some View {
        if isToday {
            content.inkGlow()
        } else {
            content
        }
    }
}

/// A past-day schedule card's frame: surface and a hairline, `accentSoft` and an accent rule while
/// selected.
struct ScheduleCardChrome: ViewModifier {
    let isSelected: Bool
    let hairline: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(InkSpacing.cardPadding)
            .background {
                RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                    .fill(isSelected ? Color.ink.accentSoft : Color.ink.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                    .stroke(isSelected ? Color.ink.accent : Color.ink.rule, lineWidth: hairline)
            }
            .contentShape(Rectangle())
    }
}

/// A "Program" row's frame (drawing `j-mac2`): a well with a hairline and a 4 pt coloured bar on
/// the leading edge; a finished task is dashed on the paper; the selected row takes the accent.
struct ProgramRowChrome: ViewModifier {
    let bar: Color
    let isSelected: Bool
    let isFinished: Bool
    let hairline: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: InkCorner.xs, style: .continuous)
        content
            .padding(.vertical, 10)
            .padding(.leading, 22)
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, minHeight: TapTarget.minimumLength, alignment: .leading)
            .background {
                shape.fill(isSelected ? Color.ink.accentSoft : (isFinished ? Color.clear : Color.ink.well))
            }
            .overlay {
                if isFinished && !isSelected {
                    shape.stroke(Color.ink.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                } else {
                    shape.stroke(isSelected ? Color.ink.accent : Color.ink.rule, lineWidth: hairline)
                }
            }
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(bar)
                    .frame(width: 4)
                    .padding(.vertical, 10)
                    .padding(.leading, 8)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
    }
}

/// Mac Today desk: the page and, when the detail is wide enough, the right panel beside it. The
/// page keeps its identity when the panel comes and goes. Elsewhere the page alone.
struct TodayDeskColumns: ViewModifier {
    let panel: AnyView?

    func body(content: Content) -> some View {
        #if os(macOS)
            HStack(spacing: 0) {
                content
                if let panel { panel }
            }
        #else
            content
        #endif
    }
}

#if os(iOS)
    /// Today hides the navigation bar; a past day adds nothing of its own.
    struct TodayHiddenBar: ViewModifier {
        let isToday: Bool

        @ViewBuilder func body(content: Content) -> some View {
            if isToday {
                content.toolbar(.hidden, for: .navigationBar)
            } else {
                content
            }
        }
    }
#endif

/// Pages pushed from a past day show its short date on their back item ("‹ 17 Eyl", drawing);
/// the destinations sit outside the day's own title modifier, so they would read the tab's name.
struct DayBackTitle: ViewModifier {
    let title: String?

    @ViewBuilder func body(content: Content) -> some View {
        if let title {
            content.environment(\.inkBackTitle, Text(verbatim: title))
        } else {
            content
        }
    }
}
