import SwiftUI

/// Empty-state inside a section card: icon badge, sentence, optional accent text action.
struct EmptyState: View {
    private let message: Text
    var systemImage: String = "tray"
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    init(
        _ message: LocalizedStringKey,
        systemImage: String = "tray",
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil
    ) {
        self.message = Text(message)
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    init(
        verbatim message: String,
        systemImage: String = "tray",
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil
    ) {
        self.message = Text(verbatim: message)
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        InkCard {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.ink.secondaryText)
                    .frame(width: 44, height: 44)
                    .background(Color.ink.well, in: Circle())
                    .accessibilityHidden(true)
                message
                    .font(.ink.placeholder)
                    .foregroundStyle(Color.ink.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("emptyState")
                if let actionTitle, let action {
                    Button(action: action) {
                        Text(actionTitle)
                            .font(.ink.byline)
                            .tapTarget()
                    }
                    .buttonStyle(InkTextButtonStyle())
                }
            }
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .contain)
    }
}
