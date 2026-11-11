import SwiftUI

/// Empty-state inside a section card: icon badge, sentence, optional accent text action.
struct EmptyState: View {
    private let message: Text
    var systemImage: String = "tray"
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil
    /// `false` draws the content without its own card, for a card that already holds it (the
    /// phone timeline's empty period under the chart's axis).
    var isCarded = true

    init(
        _ message: LocalizedStringKey,
        systemImage: String = "tray",
        actionTitle: LocalizedStringKey? = nil,
        isCarded: Bool = true,
        action: (() -> Void)? = nil
    ) {
        self.message = Text(message)
        self.isCarded = isCarded
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
        Group {
            if isCarded {
                InkCard { content }
            } else {
                content.padding(.horizontal, InkSpacing.cardPadding)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var content: some View {
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
}
