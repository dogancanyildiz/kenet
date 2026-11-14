import SwiftUI

extension SupportTier {
    /// The app's own name for the amount; the store's product name is not shown, so the page reads
    /// the same before the products exist in App Store Connect.
    var title: LocalizedStringKey {
        switch self {
        case .small: "Küçük destek"
        case .medium: "Orta destek"
        case .large: "Büyük destek"
        }
    }
}

/// Kenet'i destekle: three voluntary one-time purchases that unlock nothing (docs/decisions.md,
/// 2026-11-13). Pushed from Hakkında on iPhone and iPad; replaces the tab's content on Mac.
struct SupportSettingsView: View {
    let service: SupportService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The thank-you moment: the badge springs in and a ring of light leaves it. Both rest at 1.
    @State private var badgeScale: CGFloat = 1
    @State private var glow: CGFloat = 1
    @State private var thanks = 0
    @ScaledMetric(relativeTo: .body) private var badgeSide: CGFloat = 84

    var body: some View {
        List {
            #if os(iOS)
                InkPageTitleRow("Kenet'i destekle")
            #endif
            Section {
                Text(
                    "Kenet'in bütün özellikleri ücretsizdir. Destek gönüllüdür ve hiçbir özelliği açmaz; yalnız geliştirmenin sürmesine yardım eder."
                )
                .font(.ink.content)
                .foregroundStyle(Color.ink.text)
                .fixedSize(horizontal: false, vertical: true)
                .inkListRow()
                .accessibilityIdentifier("text.settings.support.intro")
                badge
                outcome
                options
                Text("Ödemeyi App Store alır. Destek tek seferliktir ve yenilenmez.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
            }
        }
        .listStyle(.plain)
        .inkPageNavigationTitle("Kenet'i destekle")
        .inkPageScrollColumn()
        .inkPage()
        .accessibilityIdentifier("screen.settings.support")
        .task {
            // Side by side: the products do not wait for the purchase history.
            async let badges: Void = service.refreshBadges()
            await service.pageAppeared()
            await badges
        }
        .onChange(of: service.purchase) { _, purchase in
            guard purchase == .thanked else { return }
            thanks += 1
            // Reduce Motion: the badge is simply there.
            guard !reduceMotion else { return }
            badgeScale = 0.5
            glow = 0
            withAnimation(.spring(duration: 0.55, bounce: 0.45)) { badgeScale = 1 }
            withAnimation(.easeOut(duration: 0.95)) { glow = 1 }
        }
        #if os(iOS)
            .sensoryFeedback(.success, trigger: thanks)
        #endif
    }

    private var badgeCaption: LocalizedStringKey {
        service.purchase == .thanked ? "Teşekkürler. Desteğin Kenet'in gelişmesine yardım ediyor." : "Destekçi"
    }

    /// The supporter badge, once there is one, with the thank-you under it right after a purchase.
    @ViewBuilder private var badge: some View {
        if let level = service.supporterLevel {
            VStack(spacing: 10) {
                SupportBadgeView(kind: .supporter(level), side: min(badgeSide, 120))
                    .scaleEffect(badgeScale)
                    .background {
                        Circle()
                            .stroke(Color.ink.accent, lineWidth: 2)
                            .scaleEffect(1 + 0.9 * glow)
                            .opacity(0.7 * (1 - glow))
                        Circle()
                            .fill(Color.ink.accentSoft)
                            .scaleEffect(1 + 0.6 * glow)
                            .opacity(0.8 * (1 - glow))
                    }
                Text(badgeCaption)
                    .font(.ink.content)
                    .foregroundStyle(Color.ink.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(
                        service.purchase == .thanked
                            ? "status.settings.support.thanks" : "status.settings.support.supporter")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .inkListRow()
        }
    }

    @ViewBuilder private var outcome: some View {
        switch service.purchase {
        case .pending:
            InfoBand(kind: .info, "Satın alma onay bekliyor. Onaylanınca tamamlanır.")
                .inkListRow()
                .accessibilityIdentifier("band.settings.support.pending")
        case .unverified:
            InfoBand(kind: .warning, "Ödeme alındı ama doğrulanamadı. Yeniden satın alman gerekmez.")
                .inkListRow()
                .accessibilityIdentifier("band.settings.support.unverified")
        case .failed:
            InfoBand(kind: .error, "Satın alma tamamlanamadı. Yeniden deneyebilirsin.")
                .inkListRow()
                .accessibilityIdentifier("band.settings.support.failed")
        case .idle, .purchasing, .cancelled, .thanked:
            EmptyView()
        }
    }

    @ViewBuilder private var options: some View {
        switch service.products {
        case .loading:
            HStack(spacing: InkSpacing.row) {
                ProgressView()
                Text("Destek seçenekleri yükleniyor…")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading)
            .accessibilityElement(children: .combine)
            .inkListRow()
            .accessibilityIdentifier("status.settings.support.loading")
        case .unavailable:
            // The retry sits under the band, not inside it: beside the text it squeezes the
            // message into a few letters per line at accessibility sizes.
            InfoBand(kind: .warning, "Destek seçenekleri şu an yüklenemiyor.")
                .inkListRow()
                .accessibilityIdentifier("band.settings.support.unavailable")
            Button("Yeniden dene") { Task { await service.loadProducts() } }
                .buttonStyle(InkTextButtonStyle())
                .inkListRow()
                .accessibilityIdentifier("button.settings.support.retry")
        case .loaded(let products):
            InkCard(padded: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(products.enumerated()), id: \.element.id) { index, product in
                        if index > 0 { InkCardDivider() }
                        row(product)
                    }
                }
            }
            .inkListRow()
        }
    }

    private func row(_ product: SupportProduct) -> some View {
        let isBuying = service.purchase == .purchasing(product.tier)
        return Button {
            Task { await service.buy(product.tier) }
        } label: {
            let layout =
                dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .center, spacing: InkSpacing.row))
            layout {
                Text(product.tier.title)
                    .font(.ink.content)
                    .foregroundStyle(Color.ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                if isBuying {
                    ProgressView()
                } else {
                    Text(verbatim: product.displayPrice)
                        .font(.ink.value)
                        .foregroundStyle(Color.ink.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading)
            .padding(.horizontal, InkSpacing.cardPadding)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(service.purchase.isPurchasing)
        .accessibilityLabel(Text(product.tier.title))
        .accessibilityValue(Text(verbatim: product.displayPrice))
        .accessibilityIdentifier("button.settings.support.\(product.tier.rawValue)")
    }
}
