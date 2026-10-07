#if DEBUG
    import SwiftUI

    /// Debug gallery for the control patterns (`docs/design.md`, "Denetim kalıpları"):
    /// manşet row with 0 / 1 / 3 icons, tabs, labeled menu, filter field, accent switch.
    /// Fictional sample copy only.
    struct ComponentGalleryPatterns: View {
        enum Period: Hashable { case week, month }
        enum TaskSection: Hashable { case upcoming, undated, done }
        enum Scale: Hashable { case day, week, month, quarter, year }

        @State private var period = Period.week
        @State private var section = TaskSection.upcoming
        @State private var scale = Scale.week
        @State private var emptyFilter = ""
        @State private var filledFilter = "Deniz"
        @State private var isOn = true

        /// Scroll-free stack (no page margin): embeddable in another gallery and in snapshots.
        var body: some View {
            VStack(alignment: .leading, spacing: 28) {
                headerSection
                tabsSection
                menuSection
                filterSection
                toggleSection
            }
            .frame(maxWidth: InkSpacing.macPageWidth, alignment: .leading)
        }

        private var headerSection: some View {
            galleryBlock(title: "InkPageHeader: 0, 1, 3 simge") {
                InkPageHeader(verbatim: "Özetler", byline: "14–20 Eylül")
                InkPageHeader(verbatim: "Günlük") {
                    SearchButton()
                }
                InkPageHeader(verbatim: "Görevler", byline: "6 görev kaldı") {
                    InkHeaderMenu(
                        "Filtre", systemImage: "line.3.horizontal.decrease", isActive: true
                    ) {
                        Button {
                        } label: {
                            Text(verbatim: "project/alpha")
                        }
                    }
                    InkHeaderAction("Düzenle", systemImage: "plus", role: .primary) {}
                    SearchButton()
                }
            }
        }

        private var tabsSection: some View {
            galleryBlock(title: "InkTabs: 2 ve 3 seçenek") {
                InkTabs(
                    selection: $period,
                    items: [
                        InkTabItem("Hafta", value: Period.week),
                        InkTabItem("Ay", value: Period.month),
                    ])
                InkTabs(
                    selection: $section,
                    items: [
                        InkTabItem(verbatim: "Yaklaşan", value: TaskSection.upcoming),
                        InkTabItem(verbatim: "Tarihsiz", value: TaskSection.undated),
                        InkTabItem(verbatim: "Tamamlanan", value: TaskSection.done),
                    ])
            }
        }

        private var menuSection: some View {
            galleryBlock(title: "InkLabeledMenu") {
                InkLabeledMenu(
                    "Ölçek", selection: $scale,
                    sections: [
                        [
                            InkMenuOption(verbatim: "Gün", value: Scale.day),
                            InkMenuOption("Hafta", value: Scale.week),
                            InkMenuOption("Ay", value: Scale.month),
                        ],
                        [
                            InkMenuOption(verbatim: "Çeyrek", value: Scale.quarter),
                            InkMenuOption(verbatim: "Yıl", value: Scale.year),
                        ],
                    ])
            }
        }

        private var filterSection: some View {
            galleryBlock(title: "InkFilterField: boş ve dolu") {
                InkFilterField("Kişi, konum veya metin ara", text: $emptyFilter)
                InkFilterField("Kişi, konum veya metin ara", text: $filledFilter)
            }
        }

        private var toggleSection: some View {
            galleryBlock(title: "Toggle + inkToggle()") {
                Toggle(isOn: $isOn) {
                    Text(verbatim: "Günlük hatırlatma")
                        .font(.ink.content)
                        .foregroundStyle(Color.ink.text)
                }
                .inkToggle()
            }
        }

        private func galleryBlock<Content: View>(
            title: String, @ViewBuilder content: () -> Content
        ) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: title)
                    .font(.ink.section)
                    .foregroundStyle(.ink.secondaryText)
                content()
            }
        }
    }

    /// Debug sample of the two sheet kinds (and the busy editing state). Host inside a
    /// `NavigationStack`, as a real sheet would be.
    struct ComponentGallerySheet: View {
        enum Kind: String, CaseIterable, Sendable {
            /// `List` + `InkPageTitleRow` + `.inkSheet(…, confirm: .create)`.
            case editing
            /// Same, while writing: confirm shows progress and is disabled.
            case busy
            /// `InkSheetScaffold` with "Kapat" only.
            case reading
        }

        var kind: Kind
        @State private var name = "Kitap"
        @State private var reminds = true

        var body: some View {
            switch kind {
            case .editing, .busy:
                List {
                    InkPageTitleRow("Yeni hedef")
                    SectionHeader(title: "Tanım")
                        .inkListRow()
                    InkFilterField("Ad", text: $name)
                        .inkListRow()
                    // No tint of its own: the sheet chrome supplies the accent.
                    Toggle(isOn: $reminds) {
                        Text(verbatim: "Günlük hatırlatma")
                            .font(.ink.content)
                            .foregroundStyle(Color.ink.text)
                    }
                    .inkListRow()
                }
                .listStyle(.plain)
                .inkSheet(
                    "Yeni hedef", confirm: .create, isConfirmEnabled: !name.isEmpty,
                    isBusy: kind == .busy, onCancel: {}, onConfirm: {})
            case .reading:
                InkSheetScaffold(
                    "Görev", byline: "14 Eylül", onClose: {},
                    content: {
                        Text(verbatim: "Haftalık sprint hedeflerini belirle")
                            .font(.ink.content)
                            .foregroundStyle(Color.ink.text)
                    })
            }
        }
    }

    #Preview("ComponentGalleryPatterns") {
        ScrollView {
            ComponentGalleryPatterns().padding(InkSpacing.margin)
        }
        .inkPage()
    }

    #Preview("ComponentGallerySheet") {
        NavigationStack { ComponentGallerySheet(kind: .editing) }
    }
#endif
