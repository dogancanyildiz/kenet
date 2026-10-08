import SwiftUI

/// What a manşet-row icon does; decides its color (`docs/design.md`, "Denetim kalıpları" 2).
enum InkHeaderActionRole: Equatable, Sendable {
    /// Search, sort, filter, Settings: secondary text color.
    case utility
    /// Opens a record or changes content (add, edit): accent.
    case primary
}

/// Pure color and count rules for manşet-row icons (unit-tested; the views below call these).
enum InkHeaderActionChrome {
    /// A manşet row holds at most this many icons. The components do not block a fourth;
    /// anything beyond becomes a row at the top of the page (e.g. the Summaries row in Journal).
    static let maximumCount = 3

    /// Gap between neighboring icons, and between the manşet and the first icon.
    static let spacing: CGFloat = 4

    /// Smallest pointer target for one manşet icon on Mac (pt). iPhone uses
    /// ``TapTarget/minimumLength`` through ``tapTarget()``, which stays a no-op on Mac.
    static let macMinimumSide: CGFloat = 28

    /// `isActive` marks a sort/filter that differs from its default: the icon turns accent.
    static func token(
        role: InkHeaderActionRole, isActive: Bool = false, isEnabled: Bool = true,
        isPressed: Bool = false
    ) -> InkButtonChrome.Token {
        guard isEnabled else { return .secondaryText }
        if isPressed { return .text }
        if isActive { return .accent }
        switch role {
        case .utility: return .secondaryText
        case .primary: return .accent
        }
    }

    static func fits(count: Int) -> Bool { count <= maximumCount }
}

/// Frameless icon button for the manşet row. Place inside the `actions` slot of
/// ``InkPageTitle`` / ``InkPageTitleRow`` / ``InkPageHeader``.
///
/// Order is fixed: search is the rightmost icon (``SearchButton``), screen icons sit to its left.
/// The label is required: it is the VoiceOver name (and the Mac tooltip); the icon alone shows.
struct InkHeaderAction: View {
    private let label: LocalizedStringKey
    private let systemImage: String
    private let role: InkHeaderActionRole
    private let isActive: Bool
    private let identifier: String?
    private let action: () -> Void

    init(
        _ label: LocalizedStringKey, systemImage: String, role: InkHeaderActionRole = .utility,
        isActive: Bool = false, identifier: String? = nil, action: @escaping () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.role = role
        self.isActive = isActive
        self.identifier = identifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(InkHeaderButtonStyle(role: role, isActive: isActive))
        .accessibilityLabel(label)
        .inkHelp(label)
        .inkAccessibilityIdentifier(identifier)
    }
}

/// Manşet-row icon that opens a system menu (sort, filter). Same look as ``InkHeaderAction``;
/// `content` is ordinary `Menu` content (`Button`, `Picker`, `Toggle`, `Section`, `Divider`).
/// Pass `isActive: true` while the choice differs from the default.
struct InkHeaderMenu<Content: View>: View {
    private let label: LocalizedStringKey
    private let systemImage: String
    private let role: InkHeaderActionRole
    private let isActive: Bool
    private let identifier: String?
    private let content: Content
    @Environment(\.isEnabled) private var isEnabled

    init(
        _ label: LocalizedStringKey, systemImage: String, role: InkHeaderActionRole = .utility,
        isActive: Bool = false, identifier: String? = nil, @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.systemImage = systemImage
        self.role = role
        self.isActive = isActive
        self.identifier = identifier
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            Label(label, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .inkHeaderIconMetrics()
                .foregroundStyle(
                    InkButtonChrome.color(
                        for: InkHeaderActionChrome.token(
                            role: role, isActive: isActive, isEnabled: isEnabled))
                )
                .tapTarget()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(label)
        .inkHelp(label)
        .inkAccessibilityIdentifier(identifier)
    }
}

extension View {
    /// Applies an accessibility identifier only when one is given (never an empty one).
    @ViewBuilder func inkAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }

    /// Mac pointer tooltip. No-op on iOS, where `.help` would add a duplicate VoiceOver hint.
    @ViewBuilder func inkHelp(_ label: LocalizedStringKey) -> some View {
        #if os(macOS)
            help(label)
        #else
            self
        #endif
    }
}
