import SwiftUI

/// Thin empty-state: one serif italic sentence and an optional accent text action.
struct EmptyState: View {
    private let message: Text
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    init(
        _ message: LocalizedStringKey,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil
    ) {
        self.message = Text(message)
        self.actionTitle = actionTitle
        self.action = action
    }

    init(
        verbatim message: String,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil
    ) {
        self.message = Text(verbatim: message)
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 12) {
            message
                .font(.ink.placeholder)
                .foregroundStyle(Color.ink.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.ink.byline)
                        .tapTarget()
                }
                .buttonStyle(InkTextButtonStyle())
            }
        }
        .padding(.vertical, 24)
        .accessibilityElement(children: .contain)
    }
}
