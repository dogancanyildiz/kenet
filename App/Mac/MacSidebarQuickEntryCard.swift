import SwiftUI

#if os(macOS)
    /// Bottom of the Mac sidebar: large "+", "Hızlı giriş", and the registered global shortcut.
    /// Tapping opens the quick-entry panel (`MacQuickEntryController`).
    struct MacSidebarQuickEntryCard: View {
        @Environment(\.macQuickEntry) private var quickEntry
        @Environment(\.locale) private var locale

        var body: some View {
            Button {
                quickEntry?.open()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.ink.onAccent)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.ink.accent))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hızlı giriş")
                            .font(.ink.byline.weight(.semibold))
                            .foregroundStyle(Color.ink.text)
                        Text(verbatim: shortcutCaption)
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                        .fill(Color.ink.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                                .stroke(Color.ink.line, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, MacSidebarChrome.fillInset)
            .padding(.bottom, 10)
            .accessibilityIdentifier("sidebar.quickEntry")
            .accessibilityLabel("Hızlı giriş")
            .accessibilityHint(Text(verbatim: shortcutCaption))
        }

        private var shortcutCaption: String {
            let display = quickEntry?.shortcutDisplay ?? HotKeyShortcut.defaultShortcut.display
            return Self.caption(display: display, locale: locale)
        }

        /// "⌃⌥Space ile her uygulamadan" in the view's language: `String(localized:)` alone
        /// reads the process language, not `\.locale` (fark3 Y8).
        static func caption(display: String, locale: Locale) -> String {
            String(
                localized: "\(display) ile her uygulamadan",
                bundle: PresentationLocalization.bundle(locale),
                locale: PresentationLocalization.resolvedLocale(locale))
        }
    }

    /// Bridge from `KenetApp`'s `MacQuickEntryController` into the sidebar card.
    struct MacQuickEntryBridge {
        var shortcutDisplay: String
        var open: @MainActor () -> Void
    }

    private struct MacQuickEntryKey: EnvironmentKey {
        static let defaultValue: MacQuickEntryBridge? = nil
    }

    extension EnvironmentValues {
        var macQuickEntry: MacQuickEntryBridge? {
            get { self[MacQuickEntryKey.self] }
            set { self[MacQuickEntryKey.self] = newValue }
        }
    }
#endif
