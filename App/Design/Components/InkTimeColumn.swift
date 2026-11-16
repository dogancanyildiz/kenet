import SwiftUI

/// A time in a row's leading column: one line at every text size and in every locale, never
/// wrapped and never truncated. The column is as wide as the widest time the locale writes
/// (a 12-hour time carries its day period) and never narrower than ``minWidth``, so the rows of
/// one list line up whatever their own time is. Up to ``minWidth`` it draws as a fixed column did.
struct InkTimeColumn: View {
    let text: String
    var font: Font = .ink.time
    /// The column's width while the time fits in it.
    var minWidth: CGFloat
    /// Where the time sits in a column wider than itself.
    var alignment: Alignment = .leading
    /// `false` sizes the column to its own text (a time on a line of its own).
    var reservesWidestTime = true

    @Environment(\.locale) private var locale

    var body: some View {
        ZStack(alignment: .trailing) {
            if reservesWidestTime {
                let samples = EventTimeFormat.widestSamples(locale: locale)
                label(samples.morning).hidden()
                label(samples.evening).hidden()
            }
            label(text)
                .foregroundStyle(Color.ink.secondaryText)
        }
        .frame(minWidth: minWidth, alignment: alignment)
    }

    private func label(_ string: String) -> some View {
        Text(verbatim: string)
            .font(font)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }
}
