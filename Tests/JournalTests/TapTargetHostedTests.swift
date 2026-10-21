#if os(iOS)
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

    /// Touch targets measured as SwiftUI lays them out on iOS (the size a finger meets): the
    /// controls the accessibility audit found below 44 × 44 pt.
    @MainActor @Suite(.timeLimit(.minutes(1)))
    struct TapTargetHostedTests {
        static let minimum = TapTarget.minimumLength - 0.5

        /// Günü kapat and Haftalık inceleme step words (`InkTextButtonStyle`): as wide as a finger.
        @Test(arguments: ["Geri", "İleri", "Atla", "Back", "Next", "Skip"])
        func textButtonIsAtLeastFortyFourPointsWide(_ word: String) {
            let size = Self.size(of: Self.textButton(word))
            #expect(size.width >= Self.minimum, "'\(word)' is \(size)")
            #expect(size.height >= Self.minimum, "'\(word)' is \(size)")
        }

        /// A word wider than the target keeps its own width: the floor only lifts short words.
        @Test func textButtonLongerThanTheTargetKeepsItsWidth() {
            let word = "Günlük yazısını düzenle"
            let button = Self.size(of: Self.textButton(word))
            let text = Self.size(of: Text(verbatim: word).font(.ink.byline))
            #expect(abs(button.width - text.width) < 1, "button \(button), text \(text)")
        }

        /// Today's Günlük yazısı row with the placeholder alone: one line of text in a 44 pt row.
        @Test func journalPlaceholderRowIsAtLeastFortyFourPointsTall() {
            let size = Self.size(of: DayJournalPreview(isLoaded: true, preview: nil), width: 370)
            #expect(size.height >= Self.minimum, "placeholder row is \(size)")
        }

        /// Before the day loads the row draws nothing and takes no room: no invisible target.
        @Test func journalPreviewBeforeLoadTakesNoRoom() {
            let size = Self.size(of: DayJournalPreview(isLoaded: false, preview: nil), width: 370)
            #expect(size.height < 1, "unloaded row is \(size)")
        }

        /// Haftalık inceleme "Çıktıya ekle": the row, not only the switch, is 44 pt tall.
        @Test func weeklyReviewIncludeRowIsAtLeastFortyFourPointsTall() {
            let size = Self.size(of: WeeklyReviewIncludeToggle(isOn: .constant(true)), width: 370)
            #expect(size.height >= Self.minimum, "include row is \(size)")
        }

        private static func textButton(_ word: String) -> some View {
            Button(action: {}, label: { Text(verbatim: word) }).buttonStyle(InkTextButtonStyle())
        }

        /// The view's layout size for the width it is offered (`nil`: its ideal width).
        private static func size<V: View>(of view: V, width: CGFloat? = nil) -> CGSize {
            let host = UIHostingController(
                rootView: view.environment(\.locale, Locale(identifier: "tr_TR"))
                    .environment(\.dynamicTypeSize, .large))
            let proposal = CGSize(width: width ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            return host.sizeThatFits(in: proposal)
        }
    }
#endif
