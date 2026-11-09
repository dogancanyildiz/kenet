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

/// Card-shaped info / warning / error band with a leading icon.
struct InfoBand: View {
    var kind: InfoBandKind
    private let message: Text
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    @ScaledMetric(relativeTo: .body) private var padding = InkSpacing.cardPadding

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
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: kind.markSystemImage)
                .font(.body)
                .foregroundStyle(kind.foreground)
                .frame(width: 22, alignment: .center)
                .accessibilityHidden(true)
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
        .padding(padding)
        .background {
            RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                .fill(Color.ink.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                .stroke(Color.ink.rule, lineWidth: InkStroke.rule)
        }
        .accessibilityElement(children: .contain)
    }
}
