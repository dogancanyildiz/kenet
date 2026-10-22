import SwiftUI
import VaultFormat

#if canImport(JournalingSuggestions)
    @preconcurrency import JournalingSuggestions
#endif

/// The quick entry's way into the system's journaling suggestions (iPhone): an icon at the end of
/// the empty field. The bar presents the picker with ``View/suggestionsPicker(isPresented:onPick:)``.
struct SuggestionsButton: View {
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.ink.secondaryText)
                .tapTarget()
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text("Öneriler"))
        .accessibilityHint(Text("Sistemin günlük önerilerinden birini seç"))
        .accessibilityIdentifier("button.journalingSuggestions")
    }
}

extension View {
    /// Presents the system picker where the framework exists; elsewhere it adds nothing. The pick
    /// arrives copied into a ``SuggestionPick``.
    func suggestionsPicker(
        isPresented: Binding<Bool>, onPick: @escaping @MainActor (SuggestionPick) -> Void
    ) -> some View {
        modifier(SuggestionsPickerPresenter(isPresented: isPresented, onPick: onPick))
    }
}

private struct SuggestionsPickerPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let onPick: @MainActor (SuggestionPick) -> Void

    func body(content: Content) -> some View {
        #if canImport(JournalingSuggestions)
            content.journalingSuggestionsPicker(
                isPresented: $isPresented,
                onCompletion: { suggestion in
                    let pick = await SuggestionPick.make(from: suggestion)
                    await MainActor.run { onPick(pick) }
                })
        #else
            content
        #endif
    }
}

/// The one-line note over the field: the day another day's moment is written to, the lines that
/// wait and the photos that were left out.
enum SuggestionCopy {
    static func note(
        day: CalendarDate? = nil, today: CalendarDate? = nil, remaining: Int, skippedMedia: Int, locale: Locale
    ) -> String? {
        let bundle = PresentationLocalization.bundle(locale)
        var parts: [String] = []
        if let day {
            let resolved = PresentationLocalization.resolvedLocale(locale)
            var style = Date.FormatStyle(locale: resolved).day().month(.abbreviated)
            if day.year != today?.year { style = style.year() }
            let date = LocalDay.instant(for: day).formatted(style)
            parts.append(String(localized: "\(date) için.", bundle: bundle, locale: locale))
        }
        if remaining > 0 {
            parts.append(String(localized: "Sırada \(remaining) öneri satırı var.", bundle: bundle, locale: locale))
        }
        if skippedMedia > 0 {
            parts.append(String(localized: "Fotoğraf ve videolar yazılmaz.", bundle: bundle, locale: locale))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
