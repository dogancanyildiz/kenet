import SwiftUI
import VaultFormat

struct ProjectView: View {
    let store: IndexStore
    let name: String
    @State private var actions: TasksModel
    /// Nil until the first query returns; a reload keeps the previous rows until then.
    @State private var tasks: [TaskRow]?
    @State private var detailRow: TaskRow?
    @Environment(\.locale) private var locale
    init(store: IndexStore, name: String) {
        self.store = store
        self.name = name
        _actions = State(initialValue: TasksModel(store: store))
    }
    private var masthead: InkPageTitleRow<some View> {
        InkPageTitleRow(verbatim: name, byline: byline) { SearchButton() }
    }

    /// screens.md: "3 açık · 5 bitti" under the masthead, once the first answer is in.
    private var byline: String? {
        guard let tasks else { return nil }
        let model = ProjectModel(store: store, name: name, tasks: tasks)
        return String(
            format: PresentationLocalization.string(localized: "%1$d açık · %2$d bitti", locale: locale),
            model.openCount, model.completed.count)
    }

    var body: some View {
        List {
            InkScrolledMasthead(masthead)
            // The page's sections wait for the first answer: no count reads 0 while it loads.
            if let tasks { sections(ProjectModel(store: store, name: name, tasks: tasks)) }
            if let error = actions.errorText {
                InfoBand(kind: .error, verbatim: error)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.ink.paper)
            }
        }
        .listStyle(.plain)
        .inkPage()
        .inkPageScrollColumn()
        .inkPinnedMasthead(masthead)
        .inkPageNavigationTitle(verbatim: name)
        .taskDetailSheet(store: store, row: $detailRow)
        .task(id: ProjectTasksRequest(name: name, updated: store.lastUpdated)) {
            if let loaded = try? await store.computeProjectTasks(name) { tasks = loaded }
        }
    }

    @ViewBuilder private func sections(_ model: ProjectModel) -> some View {
        // Progress card: completed / (open + completed); cancelled tasks stay out of the ratio.
        let total = model.openCount + model.completed.count
        Section {
            InkCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("İlerleme").font(.ink.section).foregroundStyle(.ink.text)
                        Spacer()
                        Text(
                            verbatim: String(
                                format: PresentationLocalization.string(
                                    localized: "%1$d/%2$d görev", locale: locale),
                                model.completed.count, total)
                        )
                        .font(.ink.value).monospacedDigit().foregroundStyle(.ink.secondaryText)
                    }
                    InkProgress(kind: .fraction(total == 0 ? 0 : Double(model.completed.count) / Double(total)))
                }
            }
            .accessibilityElement(children: .combine)
            .inkListRow()
            if let day = model.lastActivity {
                labeled("Son etkinlik") {
                    Text(LocalDay.instant(for: day), format: .dateTime.day().month().year())
                        .font(.ink.value)
                        .foregroundStyle(.ink.text)
                }
                .inkListRow()
            }
        }
        // Drawing: one "Açık görevler" title, the groups under it as small labels.
        let open = model.openSections(asOf: actions.day, calendar: actions.calendar)
        if !open.isEmpty {
            Section {
                SectionHeader(
                    title: PresentationLocalization.string(localized: "Açık görevler", locale: locale),
                    count: model.openCount
                )
                .inkListRow()
                ForEach(open) { section in
                    groupLabel(section)
                        .inkListRow()
                    rows(section.rows)
                }
            }
        }
        Section {
            SectionHeader(
                title: PresentationLocalization.string(localized: "Tamamlanan", locale: locale),
                count: model.completed.count
            )
            .inkListRow()
            rows(model.completed)
        }
        if !model.entities.isEmpty {
            Section {
                SectionHeader(
                    title: PresentationLocalization.string(localized: "Kişiler ve Konumlar", locale: locale)
                )
                .inkListRow()
                ForEach(model.entities) { entity in
                    NavigationLink {
                        EntityView(store: store, entity: entity)
                    } label: {
                        EntityRow(entity: entity)
                            // The 36 pt badge row is shorter than the 44 pt touch target.
                            .frame(minHeight: TapTarget.minimumLength)
                            .contentShape(Rectangle())
                    }
                    .inkListRow()
                }
            }
        }
        // screens.md: related days come last, newest first; a row opens that day.
        if !model.relatedDays.isEmpty {
            Section {
                SectionHeader(
                    title: PresentationLocalization.string(localized: "İlgili günler", locale: locale),
                    count: model.relatedDays.count
                )
                .inkListRow()
                InkCard(padded: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(model.relatedDays.enumerated()), id: \.element) { index, day in
                            NavigationLink {
                                DayView(store: store, date: day)
                            } label: {
                                HStack {
                                    Text(LocalDay.instant(for: day), format: .dateTime.day().month(.abbreviated).year())
                                        .font(.ink.content).foregroundStyle(.ink.text)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.ink.meta).foregroundStyle(.ink.tertiaryText)
                                        .accessibilityHidden(true)
                                }
                                .padding(.horizontal, InkSpacing.cardPadding)
                                .frame(minHeight: TapTarget.minimumLength)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < model.relatedDays.count - 1 { InkCardDivider() }
                        }
                    }
                }
                .inkListRow()
            }
        }
    }

    /// A group's small label and count; "Devreden" in the warning color, as its rows' meta line.
    private func groupLabel(_ section: ProjectOpenSection) -> some View {
        let title = PresentationLocalization.string(
            localized: String.LocalizationValue(section.kind.catalogKey), locale: locale)
        let count = section.rows.count.formatted(.number.grouping(.never).locale(locale))
        let color = section.kind == .carriedOver ? Color.ink.warning : Color.ink.secondaryText
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: title)
                .font(.ink.meta.weight(.semibold))
            Spacer(minLength: 0)
            Text(verbatim: count)
                .font(.ink.meta.monospacedDigit())
                .fixedSize()
                .layoutPriority(1)
        }
        .foregroundStyle(color)
        // A list row is at least 44 pt tall: the label sits at its foot, next to its own card.
        .frame(minHeight: TapTarget.minimumLength - 2 * InkListRowInsets.vertical, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(title), \(count)"))
        .accessibilityAddTraits(.isHeader)
        // A section title to the tests and the audit, like ``SectionHeader``'s.
        .accessibilityIdentifier(SectionHeader.titleIdentifier)
    }

    private func labeled<Value: View>(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value)
        -> some View
    {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.ink.meta)
                .foregroundStyle(.ink.secondaryText)
            Spacer(minLength: 8)
            value()
        }
    }

    private func rows(_ rows: [TaskRow]) -> some View {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            TasksListRow(
                store: store, row: row, day: actions.day,
                isOverdue: row.due.map { $0 < actions.day } ?? false,
                isBusy: actions.busy.contains(row.id), allowsReopening: true,
                openDetail: { detailRow = row }
            ) { Task { await actions.toggle(row) } }
            .inkListRow(cardSegment: .position(index, of: rows.count))
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
    }
}
