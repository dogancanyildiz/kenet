import SwiftUI

extension InfoBandKind {
    var foreground: Color {
        switch self {
        case .info: Color.ink.secondaryText
        case .warning: Color.ink.warning
        case .error: Color.ink.danger
        }
    }
}

/// Info / warning / error band. Not a card: hairline rules or a leading mark; no shadow.
struct InfoBand: View {
    var kind: InfoBandKind
    private let message: Text
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    @Environment(\.displayScale) private var displayScale

    init(
        kind: InfoBandKind,
        _ message: LocalizedStringKey,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.kind = kind
        self.message = Text(message)
        self.actionTitle = actionTitle
        self.action = action
        self.onDismiss = onDismiss
    }

    init(
        kind: InfoBandKind,
        verbatim message: String,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.kind = kind
        self.message = Text(verbatim: message)
        self.actionTitle = actionTitle
        self.action = action
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            rule
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let mark = kind.markSystemImage {
                    Image(systemName: mark)
                        .font(.footnote)
                        .foregroundStyle(kind.foreground)
                        .accessibilityHidden(true)
                }
                message
                    .font(.ink.meta)
                    .foregroundStyle(kind.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let actionTitle, let action {
                    Button(action: action) {
                        Text(actionTitle)
                            .font(.ink.meta)
                            .tapTarget()
                    }
                    .buttonStyle(InkTextButtonStyle())
                }
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.ink.secondaryText)
                            .tapTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Kapat"))
                }
            }
            .padding(.horizontal, InkSpacing.margin)
            .padding(.vertical, 10)
            rule
        }
        .accessibilityElement(children: .contain)
    }

    private var rule: some View {
        Rectangle()
            .fill(Color.ink.rule)
            .frame(height: InkStroke.hairline(scale: displayScale))
    }
}
