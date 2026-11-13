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
        .task { await service.pageAppeared() }
    }

    @ViewBuilder private var outcome: some View {
        switch service.purchase {
        case .thanked:
            InfoBand(kind: .info, "Teşekkürler. Desteğin Kenet'in gelişmesine yardım ediyor.")
                .inkListRow()
                .accessibilityIdentifier("band.settings.support.thanks")
        case .pending:
            InfoBand(kind: .info, "Satın alma onay bekliyor. Onaylanınca tamamlanır.")
                .inkListRow()
                .accessibilityIdentifier("band.settings.support.pending")
        case .failed:
            InfoBand(kind: .error, "Satın alma tamamlanamadı. Yeniden deneyebilirsin.")
                .inkListRow()
                .accessibilityIdentifier("band.settings.support.failed")
        case .idle, .purchasing, .cancelled:
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
