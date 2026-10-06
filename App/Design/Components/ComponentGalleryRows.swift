import SwiftUI
import VaultFormat

#if DEBUG
    /// DEBUG gallery for the page row family (all states, overdue stack, long text).
    struct ComponentGalleryRows: View {
        var body: some View {
            ScrollView {
                content
            }
            .inkPage()
        }

        /// Scroll-free stack for ImageRenderer probes and previews.
        var content: some View {
            VStack(alignment: .leading, spacing: 28) {
                pageHeadlineSection
                sectionHeaderSection
                taskBoxSection
                goalRingSection
                linkedTextSection
                taskRowsSection
                goalRowsSection
                eventAndCalendarSection
                stressSection
            }
            .padding(InkSpacing.margin)
            .frame(maxWidth: InkSpacing.macPageWidth, alignment: .leading)
            .background(Color.ink.paper)
        }

        private var pageHeadlineSection: some View {
            galleryBlock(title: "PageHeadline") {
                PageHeadline(
                    title: "20 Eylül Cumartesi",
                    byline: "3 olay · 4 görev ve 2 hedef kaldı")
                PageHeadline(title: "Ece Yalın")
            }
        }

        private var sectionHeaderSection: some View {
            galleryBlock(title: "SectionHeader") {
                SectionHeader(title: "Görevler", count: 4)
                SectionHeader(title: "Olaylar")
            }
        }

        private var taskBoxSection: some View {
            galleryBlock(title: "TaskBox") {
                HStack(spacing: 16) {
                    labeledBox("boş", TaskBoxState(status: .todo, priority: nil))
                    labeledBox("!", TaskBoxState(status: .todo, priority: .medium))
                    labeledBox("!!", TaskBoxState(status: .todo, priority: .high))
                    labeledBox("devam", TaskBoxState(status: .inProgress, priority: nil))
                    labeledBox("devam !", TaskBoxState(status: .inProgress, priority: .medium))
                    labeledBox("devam !!", TaskBoxState(status: .inProgress, priority: .high))
                    labeledBox("tamam", TaskBoxState(status: .done, priority: .high))
                }
            }
        }

        private var goalRingSection: some View {
            galleryBlock(title: "GoalRing") {
                HStack(spacing: 16) {
                    GoalRing(progress: 0, isBoolean: true)
                    GoalRing(progress: 1, isBoolean: true)
                    GoalRing(progress: 0.35)
                    GoalRing(progress: 0.7)
                    GoalRing(progress: 1)
                }
            }
        }

        private var linkedTextSection: some View {
            galleryBlock(title: "InkLinkedText") {
                InkLinkedText(
                    segments: [
                        .init(text: "Kahve ", kind: .plain),
                        .init(
                            text: "Ece Yalın", kind: .person, target: "Ece Yalın",
                            path: "people/Ece Yalın.md"),
                        .init(text: " ile ", kind: .plain),
                        .init(text: "Ev", kind: .place, target: "Ev", path: "places/Ev.md"),
                        .init(text: "'de, sonra ", kind: .plain),
                        .init(text: "Bilinmeyen", kind: .unresolved, target: "Bilinmeyen"),
                        .init(text: ".", kind: .plain),
                    ])
            }
        }

        private var taskRowsSection: some View {
            galleryBlock(title: "InkTaskRow") {
                InkTaskRow(
                    title: "Süt al",
                    state: TaskBoxState(status: .todo, priority: .medium))
                InkTaskRow(
                    title: "Raporu bitir",
                    state: TaskBoxState(status: .todo, priority: .high),
                    overdueDate: Calendar.current.date(
                        from: DateComponents(year: 2026, month: 9, day: 30)))
                InkTaskRow(
                    title: "Devam eden yazı",
                    state: TaskBoxState(status: .inProgress, priority: .medium))
                InkTaskRow(
                    title: "Tamamlanan görev",
                    state: TaskBoxState(status: .done, priority: nil))
            }
        }

        private var goalRowsSection: some View {
            galleryBlock(title: "InkGoalRow") {
                InkGoalRow(
                    name: "Su", progress: 0.5, valueText: "1 / 2 L",
                    onIncrement: {})
                InkGoalRow(name: "Meditasyon", progress: 0, isBoolean: true, onIncrement: {})
                InkGoalRow(name: "Kitap", progress: 1, valueText: "30 / 30", onIncrement: {})
            }
        }

        private var eventAndCalendarSection: some View {
            galleryBlock(title: "InkEventRow / InkCalendarRow") {
                InkEventRow(
                    time: "11:00",
                    segments: [
                        .init(text: "Ev", kind: .place, target: "Ev", path: "places/Ev.md"),
                        .init(text: "'de dinlenme", kind: .plain),
                    ])
                InkCalendarRow(time: "14:30", title: "Tasarım incelemesi")
            }
        }

        private var stressSection: some View {
            galleryBlock(title: "Stres: on devreden + uzun metin") {
                ForEach(0..<10, id: \.self) { index in
                    InkTaskRow(
                        title: "Devreden görev \(index + 1)",
                        state: TaskBoxState(
                            status: .todo,
                            priority: index % 3 == 0 ? .high : (index % 2 == 0 ? .medium : nil)),
                        overdueDate: Calendar.current.date(
                            byAdding: .day, value: -(index + 1), to: Date()))
                }
                InkTaskRow(
                    title:
                        "Çok uzun bir görev metni: market listesine ekmek, süt, yumurta, zeytin ve "
                        + "haftalık plan için not defterini de almayı unutma lütfen",
                    state: TaskBoxState(status: .todo, priority: .high),
                    overdueDate: Calendar.current.date(
                        from: DateComponents(year: 2026, month: 9, day: 28)))
                InkEventRow(
                    time: "16:45",
                    segments: [
                        .init(
                            text:
                                "Uzun olay: arkadaşlarla sahilde yürüyüş, sonra sergi ve akşam yemeği",
                            kind: .plain)
                    ])
            }
        }

        private func labeledBox(_ label: String, _ state: TaskBoxState) -> some View {
            VStack(spacing: 6) {
                TaskBox(state: state)
                Text(verbatim: label)
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
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

    #Preview("ComponentGalleryRows") {
        ComponentGalleryRows()
    }
#endif
