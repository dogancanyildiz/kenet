import SwiftUI

/// A meta line of parts with a separator between them ("iş · Son görüşme 3 gün önce · 9 bağ")
/// that wraps at a part boundary when the width runs out, never inside a part that fits a line.
///
/// Subviews alternate part, separator, part, …. A separator is drawn only between two parts of
/// the same line: where the line breaks it is placed in no space, so none is left at a line's
/// end or start. The separator must collapse when it is proposed zero (``InkMetaSeparator``).
/// A part wider than the whole line wraps inside the line's width.
struct InkSeparatedFlowLayout: Layout {
    /// Extra room between a part and a separator; ``InkMetaSeparator`` brings its own spaces.
    var spacing: CGFloat = 0
    var lineSpacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = lines.reduce(0) { $0 + $1.height } + CGFloat(max(0, lines.count - 1)) * lineSpacing
        return CGSize(width: lines.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        var shown: Set<Int> = []
        for line in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for (offset, index) in line.parts.enumerated() {
                if offset > 0 {
                    let separator = subviews[index - 1]
                    let size = separator.sizeThatFits(.unspecified)
                    separator.place(
                        at: CGPoint(x: x, y: y + line.height / 2), anchor: .leading, proposal: ProposedViewSize(size))
                    shown.insert(index - 1)
                    x += size.width + spacing
                }
                let size = partSize(subviews[index], width: bounds.width)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + line.height / 2), anchor: .leading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
        // A separator at a line break (and a trailing one without a part after it) takes no space.
        for index in subviews.indices where !index.isMultiple(of: 2) && !shown.contains(index) {
            subviews[index].place(at: bounds.origin, anchor: .topLeading, proposal: .zero)
        }
    }

    private struct Line {
        /// Indices of the line's parts (even subviews).
        var parts: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// A part never gets more than the whole width; a longer one wraps inside it.
    private func partSize(_ subview: LayoutSubview, width: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard ideal.width > width else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    /// A part longer than a whole line wraps on lines of its own: wrapped it is narrower again,
    /// and beside another part it would read as a column ("iş · Son görüşme 57 / gün önce").
    private func wraps(_ subview: LayoutSubview, width: CGFloat) -> Bool {
        subview.sizeThatFits(.unspecified).width > width
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for index in subviews.indices where index.isMultiple(of: 2) {
            let size = partSize(subviews[index], width: width)
            if line.parts.isEmpty {
                line = Line(parts: [index], width: size.width, height: size.height)
                continue
            }
            let separator = subviews[index - 1].sizeThatFits(.unspecified)
            let extended = line.width + spacing + separator.width + spacing + size.width
            let alone = wraps(subviews[index], width: width) || wraps(subviews[line.parts[0]], width: width)
            if alone || extended > width {
                lines.append(line)
                line = Line(parts: [index], width: size.width, height: size.height)
            } else {
                line.parts.append(index)
                line.width = extended
                line.height = max(line.height, size.height, separator.height)
            }
        }
        if !line.parts.isEmpty { lines.append(line) }
        return lines
    }
}

/// The " · " between two parts of a meta line, spaces included so that the gap follows the text
/// size as it does inside one text. Proposed zero it takes no space and draws nothing,
/// which is how ``InkSeparatedFlowLayout`` drops it at a line break. Decoration: the line's own
/// label carries the separator for VoiceOver.
struct InkMetaSeparator: View {
    var body: some View {
        Collapsing {
            Text(verbatim: " · ").fixedSize()
        }
        .clipped()
        .accessibilityHidden(true)
    }

    /// The content at its ideal size, or no size at all when the proposal is zero.
    private struct Collapsing: Layout {
        private func isCollapsed(_ proposal: ProposedViewSize) -> Bool {
            proposal.width == 0 && proposal.height == 0
        }

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            guard !isCollapsed(proposal), let content = subviews.first else { return .zero }
            return content.sizeThatFits(.unspecified)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            // Collapsed, the content stays at its own size and the caller's clip leaves nothing of it.
            subviews.first?.place(
                at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: .unspecified)
        }
    }
}
