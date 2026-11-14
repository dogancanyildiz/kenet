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
/// link. Medium: both links. Large: the medium badge inside a circular frame. Test team: one
/// dashed link. Shapes only, no image file; colors are palette tokens, the same in both themes.
struct SupportBadgeView: View {
    let kind: SupportBadgeKind
    var side: CGFloat = 40

    /// The large badge's rim, as a share of the side: 2.2 pt at 40 pt.
    static let rimWidth: CGFloat = 0.055
    /// The links inside the rim, against the medium badge's: leaves 0.085 of the side between
    /// the links' ends and the rim.
    static let framedLinksScale: CGFloat = 0.72

    private var stroke: CGFloat { side * 0.11 }

    var body: some View {
        ZStack {
            switch kind {
            case .supporter(.small):
                link(angle: -45, color: Color.ink.accent)
            case .supporter(.medium):
                links
            case .supporter(.large):
                // The medium badge in a frame, the same in both themes. The links keep their
                // proportions and shrink to leave clear room inside the rim; the faint glow is
                // the rim's own shadow.
                Circle()
                    .strokeBorder(Color.ink.accent, lineWidth: side * Self.rimWidth)
                    .shadow(color: Color.ink.accent.opacity(0.35), radius: side * 0.07)
                links.scaleEffect(Self.framedLinksScale)
            case .tester:
                link(angle: -45, color: Color.ink.accent, dash: [stroke * 1.1, stroke * 0.9])
            }
        }
        .frame(width: side, height: side)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(kind.accessibilityLabel))
        .accessibilityAddTraits(.isImage)
    }

    /// The medium badge's drawing: the icon's two interlocked links.
    private var links: some View {
        ZStack {
            link(angle: 45, color: Color.ink.text)
            link(angle: -45, color: Color.ink.accent)
        }
        .frame(width: side, height: side)
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
