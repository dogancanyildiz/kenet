import SwiftUI

/// Large tabular number at the design target (48 pt) that scales with Dynamic Type.
struct LargeNumberText: View {
    private let text: Text
    @ScaledMetric(relativeTo: .largeTitle) private var pointSize = InkSize.largeNumber

    init(_ value: some StringProtocol) {
        self.text = Text(verbatim: String(value))
    }

    init(verbatim value: String) {
        self.text = Text(verbatim: value)
    }

    init(_ key: LocalizedStringKey) {
        self.text = Text(key)
    }

    var body: some View {
        text
            .font(.system(size: pointSize, weight: .light, design: .default).monospacedDigit())
            .foregroundStyle(Color.ink.text)
    }
}
