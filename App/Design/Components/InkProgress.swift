import SwiftUI

/// Progress chrome: indeterminate (inline), determinate (line + tabular counter), or fraction (line only).
struct InkProgress: View {
    enum Kind {
        /// Small inline status while work runs without a known total (e.g. index refresh).
        case indeterminate(label: LocalizedStringKey)
        /// Line progress with `completed` of `total` (e.g. vault import).
        case determinate(completed: Int, total: Int, label: LocalizedStringKey?)
        /// Line progress from a 0...1 (or over-1) ratio; no "n/total" counter.
        case fraction(Double, label: LocalizedStringKey? = nil)
    }

    var kind: Kind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch kind {
        case .indeterminate(let label):
            indeterminate(label: label)
        case .determinate(let completed, let total, let label):
            determinate(completed: completed, total: total, label: label)
        case .fraction(let value, let label):
            fractionBar(value: value, label: label)
        }
    }

    private func indeterminate(label: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            if reduceMotion {
                Image(systemName: "ellipsis")
                    .font(.footnote)
                    .foregroundStyle(Color.ink.secondaryText)
                    .accessibilityHidden(true)
            } else {
                IndeterminateMark()
                    .accessibilityHidden(true)
            }
            Text(label)
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private func determinate(completed: Int, total: Int, label: LocalizedStringKey?) -> some View {
        let fraction = InkProgressMath.fraction(completed: completed, total: total)
        let safeTotal = max(total, 1)
        let clamped = min(max(completed, 0), safeTotal)
        return VStack(alignment: .leading, spacing: 6) {
            if let label {
                Text(label)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
            }
            bar(fraction: fraction)
            Text(InkProgressMath.counterText(completed: clamped, total: safeTotal))
                .font(.ink.value)
                .foregroundStyle(Color.ink.secondaryText)
                .monospacedDigit()
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(InkProgressMath.counterText(completed: clamped, total: safeTotal)))
    }

    private func fractionBar(value: Double, label: LocalizedStringKey?) -> some View {
        let fraction = InkProgressMath.fraction(value)
        return VStack(alignment: .leading, spacing: 6) {
            if let label {
                Text(label)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
            }
            bar(fraction: fraction)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: InkProgressMath.percentText(fraction)))
    }

    private func bar(fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.ink.well)
                Capsule()
                    .fill(Color.ink.accent)
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(height: 4)
    }
}

/// Small accent arc used instead of `ProgressView` so the mark always uses ink tokens.
private struct IndeterminateMark: View {
    @State private var rotating = false

    var body: some View {
        Circle()
            .trim(from: 0.15, to: 0.85)
            .stroke(Color.ink.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    rotating = true
                }
            }
    }
}
