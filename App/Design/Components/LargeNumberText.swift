import SwiftUI

/// Large tabular number at the design target (48 pt) that scales with Dynamic Type.
struct LargeNumberText: View {
    private let text: Text
    var weight: Font.Weight = .light
    @ScaledMetric(relativeTo: .largeTitle) private var pointSize = InkSize.largeNumber

    init(_ value: some StringProtocol, weight: Font.Weight = .light) {
        self.text = Text(verbatim: String(value))
        self.weight = weight
    }

    init(verbatim value: String, weight: Font.Weight = .light) {
        self.text = Text(verbatim: value)
        self.weight = weight
    }

    init(_ key: LocalizedStringKey, weight: Font.Weight = .light) {
        self.text = Text(key)
        self.weight = weight
    }

    var body: some View {
        text
            .font(.system(size: pointSize, weight: weight, design: .default).monospacedDigit())
            .foregroundStyle(Color.ink.text)
    }
}
