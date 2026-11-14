import SwiftUI

/// The app's web pages, in one place: addresses from decisions.md (2026-10-21, kullanıcı kararı
/// 72). Turkish pages at the root, English under `/en/`; the language follows the app's language
/// (``PresentationLocalization``), not the device region.
enum AppLinks {
    static func privacyPolicy(locale: Locale) -> URL {
        isEnglish(locale)
            ? URL(string: "https://kenet.app/en/privacy")! : URL(string: "https://kenet.app/gizlilik")!
    }

    static func support(locale: Locale) -> URL {
        isEnglish(locale)
            ? URL(string: "https://kenet.app/en/support")! : URL(string: "https://kenet.app/destek")!
    }

    /// Turkish is the catalog's source language; every other app language gets the English page.
    private static func isEnglish(_ locale: Locale) -> Bool {
        PresentationLocalization.resolvedLocale(locale).language.languageCode?.identifier != "tr"
    }
}

/// The app's version as "1.0.0 (383)": marketing version and build number from the bundle.
enum AppVersionText {
    static func text(bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let build, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }
}

/// Hakkında: version, privacy policy, support, the third-party licenses, and voluntary support. Pushed from the
/// iPhone and iPad hub; a Settings tab on Mac (``MacAboutSettingsPage``).
struct AboutSettingsView: View {
    @Environment(\.locale) private var locale
    /// Nil where no store is wired in (previews, snapshot hosts): the row is then left out.
    @Environment(SupportService.self) private var support: SupportService?
    #if os(macOS)
        /// The Settings tab swaps its content; a push would shift the tab strip's highlight.
        var openLicenses: () -> Void = {}
        var openSupport: () -> Void = {}
    #endif

    var body: some View {
        List {
            #if os(iOS)
                InkPageTitleRow("Hakkında")
            #endif
            Section {
                InkCard(padded: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        LabeledContent("Sürüm") {
                            Text(verbatim: AppVersionText.text())
                                .font(.ink.value)
                                .foregroundStyle(Color.ink.secondaryText)
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: InkButtonChrome.minimumHeight)
                        .padding(.horizontal, InkSpacing.cardPadding)
                        InkCardDivider()
                        // Links open in the browser (Safari), outside the app.
                        Link(destination: AppLinks.privacyPolicy(locale: locale)) {
                            InkDisclosureRowLabel("Gizlilik politikası", symbol: "arrow.up.right")
                        }
                        .inkDisclosureRow("Gizlilik politikası")
                        .accessibilityIdentifier("link.settings.about.privacy")
                        InkCardDivider()
                        Link(destination: AppLinks.support(locale: locale)) {
                            InkDisclosureRowLabel("Yardım", symbol: "arrow.up.right")
                        }
                        .inkDisclosureRow("Yardım")
                        .accessibilityIdentifier("link.settings.about.support")
                        InkCardDivider()
                        licensesRow
                        if let support {
                            InkCardDivider()
                            supportRow(support)
                        }
                    }
                }
                .inkListRow()
                Text("Kenet verini yalnız kendi dosyalarında tutar; hiçbir veri toplamaz ya da göndermez.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
            }
        }
        .listStyle(.plain)
        .inkPageNavigationTitle("Hakkında")
        .inkPageScrollColumn()
        .inkPage()
    }

    /// Opens the support page. The purchase itself happens there, never from this row.
    @ViewBuilder private func supportRow(_ support: SupportService) -> some View {
        #if os(macOS)
            Button(action: openSupport) {
                InkDisclosureRowLabel("Kenet'i destekle")
            }
            .inkDisclosureRow("Kenet'i destekle")
            .accessibilityIdentifier("button.settings.about.supportKenet")
        #else
            NavigationLink {
                SupportSettingsView(service: support)
            } label: {
                InkDisclosureRowLabel("Kenet'i destekle")
            }
            .inkDisclosureRow("Kenet'i destekle")
            .accessibilityIdentifier("button.settings.about.supportKenet")
        #endif
    }

    @ViewBuilder private var licensesRow: some View {
        #if os(macOS)
            Button(action: openLicenses) {
                InkDisclosureRowLabel("Üçüncü taraf lisansları")
            }
            .inkDisclosureRow("Üçüncü taraf lisansları")
            .accessibilityIdentifier("button.settings.about.licenses")
        #else
            NavigationLink {
                ThirdPartyLicensesView()
            } label: {
                InkDisclosureRowLabel("Üçüncü taraf lisansları")
            }
            .inkDisclosureRow("Üçüncü taraf lisansları")
            .accessibilityIdentifier("button.settings.about.licenses")
        #endif
    }
}
