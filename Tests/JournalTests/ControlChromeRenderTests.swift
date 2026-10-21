#if os(macOS)
    import SwiftUI
    import Testing

    @testable import Journal

    /// The control-pattern components draw with the colors their chrome decisions pick: read
    /// from the pixels the views really paint (light appearance, on paper), not from the source
    /// that calls the decision. Each case also checks the color the decision rules out.
    @MainActor @Suite(.timeLimit(.minutes(1)))
    struct ControlChromeRenderTests {
        private let watchdog = HostedTestWatchdog()
        private static let canvas = CGSize(width: 220, height: 64)
        // Lower bounds as a share of the drawn image, about half of what the views fill today:
        // a manşet icon, a tab or mode word (or its underline), a sheet bar word.
        private static let icon = 0.0006
        private static let word = 0.0003
        private static let barWord = 0.00007

        // MARK: - Manşet row icons

        @Test func headerActionColorFollowsRoleActiveAndEnabled() throws {
            let primary = try Self.draw(InkHeaderAction("Ekle", systemImage: "plus", role: .primary) {})
            #expect(primary.share(.accent) >= Self.icon && primary.count(.secondaryText) == 0)

            let utility = try Self.draw(InkHeaderAction("Ekle", systemImage: "plus") {})
            #expect(utility.share(.secondaryText) >= Self.icon && utility.count(.accent) == 0)

            let active = try Self.draw(
                InkHeaderAction("Süz", systemImage: "line.3.horizontal.decrease", isActive: true) {})
            #expect(
                active.share(.accent) >= Self.icon && active.count(.secondaryText) == 0,
                "a non-default filter is accent")

            let disabled = try Self.draw(
                InkHeaderAction("Ekle", systemImage: "plus", role: .primary) {}.disabled(true))
            #expect(disabled.share(.secondaryText) >= Self.icon && disabled.count(.accent) == 0)
        }

        /// The manşet slot draws a plain button (``SearchButton``, shown on the Mac inside the
        /// search sheet) as a utility icon: secondary text and frameless, like the headline row
        /// around it; the headline itself is text-colored.
        @Test func headerSlotDrawsSearchAsAUtilityIcon() throws {
            let size = CGSize(width: 320, height: 80)
            let bare = try Self.draw(InkPageHeader(verbatim: "Gün"), size: size)
            let header = try Self.draw(
                InkPageHeader(verbatim: "Gün") { SearchButton() }
                    .environment(\.isSearchSheet, true)
                    .environment(\.openSearch, {}),
                size: size)
            #expect(
                header.share(.secondaryText) >= bare.share(.secondaryText) + Self.icon,
                "the magnifier is a utility icon")
            #expect(header.count(.accent) == 0)
            #expect(header.share(.text) >= 0.005, "the headline")
        }

        // MARK: - Tabs

        /// Selected word in text color with the accent underline, the others in secondary text.
        @Test func tabWordsFollowSelection() throws {
            let tabs = try Self.draw(
                InkTabs(
                    selection: .constant(1),
                    items: [InkTabItem(verbatim: "Bir", value: 1), InkTabItem(verbatim: "İki", value: 2)]),
                size: CGSize(width: 220, height: 60))
            #expect(tabs.share(.text) >= Self.word, "the selected word")
            #expect(tabs.share(.secondaryText) >= Self.word, "the other word")
            #expect(tabs.share(.accent) >= Self.word, "the underline under the selected word")

            let none = try Self.draw(
                InkTabs(
                    selection: .constant(3),
                    items: [InkTabItem(verbatim: "Bir", value: 1), InkTabItem(verbatim: "İki", value: 2)]),
                size: CGSize(width: 220, height: 60))
            #expect(none.count(.accent) == 0, "no underline without a selected word")
            #expect(none.count(.text) == 0)
        }

        /// The quick-entry capsule's mode words draw through the same tab word: the selected one
        /// in text color over a short accent underline, the other in secondary text.
        @Test func quickEntryModeWordsShareTheTabDrawing() throws {
            let capsule = try Self.draw(
                QuickEntryCapsule(mode: .constant(.event), canSubmit: false, onSubmit: {}) {
                    Color.clear.frame(width: 80, height: 20)
                }, size: CGSize(width: 360, height: 70))
            #expect(capsule.share(.text) >= Self.word, "the selected mode word")
            #expect(capsule.share(.secondaryText) >= Self.word, "the other mode word")
            #expect(capsule.share(.accent) >= Self.word, "the underline under the selected word")
        }

        /// The manşet menu icon (sort, filter) takes the same role colors as the action icons.
        @Test func headerMenuColorFollowsRoleAndActiveState() throws {
            let utility = try Self.draw(
                InkHeaderMenu("Sırala", systemImage: "arrow.up.arrow.down") { Button("Ada göre") {} })
            #expect(utility.share(.secondaryText) >= Self.icon && utility.count(.accent) == 0)
            let active = try Self.draw(
                InkHeaderMenu("Süz", systemImage: "line.3.horizontal.decrease", isActive: true) {
                    Button("Açık") {}
                })
            #expect(active.share(.accent) >= Self.icon && active.count(.secondaryText) == 0)
        }

        // MARK: - Filter field

        /// Well background and the control-line border while not focused.
        @Test func filterFieldDrawsAWellWithAControlBorder() throws {
            let field = try Self.draw(
                InkFilterField("Ara", text: .constant("")).padding(8), size: CGSize(width: 260, height: 64))
            #expect(field.share(.well) >= 0.15, "the well fills the field")
            #expect(field.share(.control) >= 0.01, "the control line around it")
            #expect(field.count(.accent) == 0, "accent only while focused")
        }

        // MARK: - Sheet bar

        /// Mac sheet bar: "Vazgeç" in secondary text, the confirm word in accent; a disabled
        /// "Vazgeç" steps down to the control color and a disabled confirm loses the accent.
        @Test func sheetBarWordsFollowTheirChrome() throws {
            let size = CGSize(width: 520, height: 380)
            let editing = try Self.draw(Color.clear.inkSheet("Düzenle", onConfirm: {}), size: size)
            #expect(editing.share(.accent) >= Self.barWord, "Kaydet")
            #expect(editing.share(.secondaryText) >= Self.barWord, "Vazgeç")

            let locked = try Self.draw(
                Color.clear.inkSheet("Düzenle", isConfirmEnabled: false, isCancelEnabled: false, onConfirm: {}),
                size: size)
            #expect(locked.count(.accent) == 0, "a disabled confirm is not accent")
            #expect(editing.count(.control) == 0)
            #expect(locked.share(.control) >= Self.barWord, "a disabled Vazgeç is drawn in the control color")

            let reading = try Self.draw(Color.clear.inkSheet("Ara", closeIdentifier: nil), size: size)
            #expect(reading.share(.accent) >= Self.barWord, "Kapat")
            #expect(reading.count(.secondaryText) == 0, "no Vazgeç on a read-only sheet")
        }

        // MARK: - Section header

        /// A disclosure header draws its chevron: down when expanded, right when collapsed;
        /// none without `isExpanded`.
        @Test func sectionHeaderDrawsTheDisclosureChevron() throws {
            let size = CGSize(width: 300, height: 50)
            // The chevron sits at the trailing edge; the title is at the leading one.
            let trailing = Int(size.width * RenderedInk.scale * 0.7)
            let plain = try Self.draw(SectionHeader(title: "Bir"), size: size)
            #expect(plain.bounds(of: Color.ink.secondaryText, fromX: trailing) == nil)

            let open = try Self.draw(SectionHeader(title: "Bir", isExpanded: true), size: size)
            let down = try #require(open.bounds(of: Color.ink.secondaryText, fromX: trailing))
            #expect(down.width > down.height, "chevron.down is wider than tall: \(down)")

            let closed = try Self.draw(SectionHeader(title: "Bir", isExpanded: false), size: size)
            let right = try #require(closed.bounds(of: Color.ink.secondaryText, fromX: trailing))
            #expect(right.height > right.width, "chevron.right is taller than wide: \(right)")
        }

        /// "Bir süredir görüşmediklerin" is a disclosure header: its chevron follows the section.
        @Test func unseenPeopleHeaderShowsWhetherItIsOpen() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let size = CGSize(width: 360, height: 60)
            let trailing = Int(size.width * RenderedInk.scale * 0.7)
            func header(expanded: Bool) throws -> RenderedInk.Image {
                try Self.draw(
                    UnseenPeopleSection(store: context.store, people: [], initiallyExpanded: expanded)
                        .environment(IntentNavigation()),
                    size: size)
            }
            let closed = try #require(try header(expanded: false).bounds(of: Color.ink.secondaryText, fromX: trailing))
            #expect(closed.height > closed.width, "chevron.right while closed: \(closed)")
            let open = try #require(try header(expanded: true).bounds(of: Color.ink.secondaryText, fromX: trailing))
            #expect(open.width > open.height, "chevron.down while open: \(open)")
        }

        // MARK: - Support

        private static func draw(_ view: some View, size: CGSize = canvas) throws -> RenderedInk.Image {
            try #require(RenderedInk.image(view, size: size))
        }
    }
#endif
