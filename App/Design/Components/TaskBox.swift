import SwiftUI
import VaultFormat

/// Visual state for the Mürekkep task checkbox (owner change: priority lives inside the box).
struct TaskBoxState: Equatable, Sendable {
    var status: TaskStatus
    var priority: TaskPriority?

    var isCompleted: Bool { status.isClosed }
    var isCancelled: Bool { status == .cancelled }
    var isInProgress: Bool { status == .inProgress }

    /// Glyph drawn inside an open / in-progress box (`nil` when empty, completed, or cancelled).
    var priorityGlyph: String? {
        guard !isCompleted else { return nil }
        switch priority {
        case .medium: return "!"
        case .high: return "!!"
        case .low, .other, .none: return nil
        }
    }

    var usesHighPriorityStroke: Bool {
        !isCompleted && priority == .high
    }
}

/// 22 pt rounded square task mark. Scales with Dynamic Type; hit target stays ≥ 44 pt.
struct TaskBox: View {
    let state: TaskBoxState
    var action: (() -> Void)? = nil
    /// Spoken label; reopen flow passes "Görevi yeniden aç".
    var accessibilityLabelKey: LocalizedStringKey = "Görevi tamamla"

    @ScaledMetric(relativeTo: .body) private var boxSide = InkSize.taskBox
    @Environment(\.legibilityWeight) private var legibilityWeight

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    box
                        .tapTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(accessibilityLabelKey))
                .accessibilityAddTraits(.isToggle)
                .accessibilityValue(Text(verbatim: accessibilityValueText))
            } else {
                box
                    .accessibilityElement()
                    .accessibilityLabel(Text(accessibilityLabelKey))
                    .accessibilityValue(Text(verbatim: accessibilityValueText))
            }
        }
    }

    private var box: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(fillColor)
            if state.isInProgress && !state.isCompleted {
                // Bottom half filled; priority glyph stays in the open top half so "!" / "!!"
                // remain legible on paper (open detail from design.md).
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: corner,
                    bottomTrailingRadius: corner, topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(Color.ink.secondaryText)
                .frame(height: boxSide / 2)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            }
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(strokeColor, lineWidth: strokeWidth)
            if state.isCancelled {
                Capsule()
                    .fill(Color.ink.paper)
                    .frame(height: max(2, boxSide * 0.12))
                    .padding(.horizontal, boxSide * 0.12)
            } else if state.isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: boxSide * 0.45, weight: .semibold))
                    .foregroundStyle(Color.ink.paper)
            } else if let glyph = state.priorityGlyph {
                Text(verbatim: glyph)
                    .font(.system(size: glyphSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ink.text)
                    .tracking(glyph == "!!" ? -0.8 : 0)
                    .offset(y: state.isInProgress ? -boxSide * 0.18 : 0)
            }
        }
        .frame(width: boxSide, height: boxSide)
        .accessibilityHidden(true)
    }

    private var corner: CGFloat { InkSize.taskBoxCorner * (boxSide / InkSize.taskBox) }

    private var strokeWidth: CGFloat {
        state.usesHighPriorityStroke ? InkStroke.highPriority : InkStroke.control
    }

    private var strokeColor: Color {
        if state.isCompleted { return Color.ink.secondaryText }
        if state.usesHighPriorityStroke { return Color.ink.text }
        return Color.ink.control
    }

    private var fillColor: Color {
        state.isCompleted ? Color.ink.secondaryText : Color.clear
    }

    /// Rule 9: never below 12 pt on iOS; "!!" may tighten tracking to fit the 22 pt box.
    private var glyphSize: CGFloat {
        let base = state.priorityGlyph == "!!" ? boxSide * 0.38 : boxSide * 0.48
        let scaled = legibilityWeight == .bold ? base * 1.05 : base
        return max(12, scaled)
    }

    private var accessibilityValueText: String {
        VoiceOverCopy.taskBoxValue(state: state, locale: .current)
    }
}
