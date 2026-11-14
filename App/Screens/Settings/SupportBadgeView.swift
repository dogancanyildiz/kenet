import SwiftUI

/// A badge the app gives as thanks; it unlocks nothing.
enum SupportBadgeKind: Hashable, Sendable {
    case supporter(SupportTier)
    case tester

    var title: LocalizedStringKey {
        switch self {
        case .supporter: "Destekçi"
        case .tester: "Test ekibi"
        }
    }

    /// What a tap on the badge says.
    var message: LocalizedStringKey {
        switch self {
        case .supporter: "Kenet'i destekledin. Teşekkürler."
        case .tester: "Kenet'i yayından önce denedin. Teşekkürler."
        }
    }

    var accessibilityLabel: LocalizedStringKey {
        switch self {
        case .supporter(.small): "Destekçi rozeti, küçük"
        case .supporter(.medium): "Destekçi rozeti, orta"
        case .supporter(.large): "Destekçi rozeti, büyük"
        case .tester: "Test ekibi rozeti"
        }
    }

    var identifier: String {
        switch self {
        case .supporter(let tier): "badge.support.supporter.\(tier.rawValue)"
        case .tester: "badge.support.tester"
        }
    }
}

/// The badge drawing, derived from the app icon's two interlocked links (halka). Small: one
/// link. Medium: both links. Large: both links on a filled ground with a soft glow (the ground's
/// tokens differ in dark, see below). Test team: one dashed link. Shapes only, no image file; colors are palette tokens.
struct SupportBadgeView: View {
    let kind: SupportBadgeKind
    var side: CGFloat = 40
    @Environment(\.colorScheme) private var colorScheme

    private var stroke: CGFloat { side * 0.11 }

    var body: some View {
        ZStack {
            switch kind {
            case .supporter(.small):
                link(angle: -45, color: Color.ink.accent)
            case .supporter(.medium):
                link(angle: 45, color: Color.ink.text)
                link(angle: -45, color: Color.ink.accent)
            case .supporter(.large) where colorScheme == .dark:
                // Dark: the accent is a light pink, and dark links on a pink disc run together.
                // The ground is the dark plum with an accent rim; the links are opaque and take
                // the medium badge's two tones, so the interlock reads at 40 pt. The glow is the
                // disc's shadow: it lies outside the ground and never over the links.
                Circle()
                    .fill(Color.ink.accentSoft)
                    .shadow(color: Color.ink.accent.opacity(0.45), radius: side * 0.14)
                Circle()
                    .strokeBorder(Color.ink.accent, lineWidth: max(1, side * 0.035))
                link(angle: 45, color: Color.ink.text, inset: side * 0.1)
                link(angle: -45, color: Color.ink.accent, inset: side * 0.1)
            case .supporter(.large):
                Circle()
                    .fill(Color.ink.accent)
                    .shadow(color: Color.ink.accent.opacity(0.45), radius: side * 0.14)
                link(angle: 45, color: Color.ink.onAccent.opacity(0.55), inset: side * 0.17)
                link(angle: -45, color: Color.ink.onAccent, inset: side * 0.17)
            case .tester:
                link(angle: -45, color: Color.ink.accent, dash: [stroke * 1.1, stroke * 0.9])
            }
        }
        .frame(width: side, height: side)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(kind.accessibilityLabel))
        .accessibilityAddTraits(.isImage)
    }

    /// One link of the icon: a stadium ring lying on a diagonal.
    private func link(angle: Double, color: Color, inset: CGFloat = 0, dash: [CGFloat] = []) -> some View {
        let length = side - inset * 2
        return Capsule()
            .strokeBorder(color, style: StrokeStyle(lineWidth: stroke, lineCap: .butt, dash: dash))
            .frame(width: length, height: length * 0.58)
            .rotationEffect(.degrees(angle))
    }
}

/// The earned badges at the top of Hakkında: one row each, so both fit side by side with their
/// names at any text size. A tap shows the badge's thanks under its name.
struct SupportBadgesCard: View {
    let service: SupportService
    @State private var opened: SupportBadgeKind?
    @ScaledMetric(relativeTo: .body) private var badgeSide: CGFloat = 40

    private var kinds: [SupportBadgeKind] {
        var kinds: [SupportBadgeKind] = []
        if let level = service.supporterLevel { kinds.append(.supporter(level)) }
        if service.isTester { kinds.append(.tester) }
        return kinds
    }

    var body: some View {
        if !kinds.isEmpty {
            InkCard(padded: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(kinds, id: \.self) { kind in
                        row(kind)
                    }
                }
            }
        }
    }

    private func row(_ kind: SupportBadgeKind) -> some View {
        Button {
            opened = opened == kind ? nil : kind
        } label: {
            HStack(alignment: .center, spacing: InkSpacing.row) {
                SupportBadgeView(kind: kind, side: min(badgeSide, 64))
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.ink.content)
                        .foregroundStyle(Color.ink.text)
                    if opened == kind {
                        Text(kind.message)
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading)
            .padding(.horizontal, InkSpacing.cardPadding)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(kind.accessibilityLabel))
        .accessibilityValue(Text(kind.message))
        .accessibilityIdentifier(kind.identifier)
    }
}
