import SwiftUI
import VaultFormat
import VaultIndex

struct EntityView: View {
    let store: IndexStore
    let entity: EntitySummary
    let onRenamed: (String) -> Void
    /// Runs after the edit sheet deleted the file and closed. Nil: the page dismisses itself
    /// (pops its stack or closes its sheet); the Mac detail column clears its selection instead.
    let onDeleted: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var deletion = DefinitionDeletionModel()
    @Environment(\.locale) private var locale
    @Environment(\.clockNow) private var clockNow
    @State private var model: EntityDetailModel
    @State private var importantDates: ImportantDatesModel
    @State private var unlinkedMentions: UnlinkedMentionsModel
    @State private var isEditing = false
    /// Nil until the first query returns; a reload keeps the previous days until then.
    @State private var timeline: [EntityTimelineDay]?
    /// The last encounter's day, loaded with `timeline` so the insight card opens complete.
    @State private var lastDay: DaySummary?
    /// Open tasks linking here, loaded with `timeline`, by due day, priority, file and line.
    @State private var openTasks: [TaskRow] = []

    init(
        store: IndexStore, entity: EntitySummary, onRenamed: @escaping (String) -> Void = { _ in },
        onDeleted: ((String) -> Void)? = nil
    ) {
        self.store = store
        self.entity = entity
        self.onRenamed = onRenamed
        self.onDeleted = onDeleted
        _model = State(initialValue: EntityDetailModel(store: store, path: entity.id))
        _importantDates = State(initialValue: ImportantDatesModel(store: store))
        _unlinkedMentions = State(initialValue: UnlinkedMentionsModel(store: store))
    }

    private var current: EntitySummary {
        if let current = store.content.entities.first(where: { $0.id == model.path }) { return current }
        guard let name = model.renamedName else { return entity }
        return EntitySummary(
            id: model.path, kind: entity.kind, name: name, qualifier: model.renamedQualifier,
            aliases: model.aliases, incomingLinks: 0)
    }

    private var kindLabel: String {
        EntityTypeChoices.choices(store.entityTypes, language: locale.language.languageCode?.identifier ?? "en")
            .first { $0.id == current.kind }?.name
            ?? current.kind
    }

    private var lastSeen: CalendarDate? {
        store.entityUsage.first { $0.file == model.path }?.lastDate
    }

    /// People and custom types. Places and goals have no anniversary line.
    private var showsImportantDates: Bool {
        current.kind == "person" || store.entityTypes.types.contains { $0.id == current.kind }
    }

    private var schemaKeys: Set<String> {
        Set(store.entityTypes.allTypes.first { $0.id == current.kind }?.fields.map(\.key) ?? [])
    }

    /// The manşet row carries the page actions, so it is there before the file loads.
    private var masthead: InkPageTitleRow<some View> {
        InkPageTitleRow(
            verbatim: current.name,
            byline: model.isLoaded
                ? EntityReadPresentation.byline(
                    kindLabel: kindLabel, aliases: model.aliases, lastSeen: lastSeen, locale: locale)
                : nil
        ) {
            if model.isLoaded && model.canEdit {
                InkHeaderAction(
                    "Düzenle", systemImage: "pencil", role: .primary, identifier: "button.entity.edit"
                ) { isEditing = true }
            }
            SearchButton()
        }
    }

    var body: some View {
        List {
            Section {
                InkScrolledMasthead(masthead)
                if model.isLoaded {
                    headRows
                } else if model.errorText == nil {
                    ProgressView("Yükleniyor…")
                        .inkListRow()
                } else {
                    Button("Yeniden dene") { Task { await model.load() } }
                        .buttonStyle(InkTextButtonStyle())
                        .inkListRow()
                }
            }
            if model.isLoaded, timeline != nil {
                readingContent
            }
            if let error = model.errorText {
                Text(verbatim: error).font(.ink.meta).foregroundStyle(.ink.danger)
                    .inkListRow()
            }
        }
        .listStyle(.plain)
        .inkPage()
        .inkPageScrollColumn()
        .inkPinnedMasthead(masthead)
        .environment(\.entityLookup, LinkedTextInk.lookup(entities: store.content.entities))
        .inkPageNavigationTitle(verbatim: current.name)
        .sheet(
            isPresented: $isEditing,
            onDismiss: {
                // "Varlığı sil" closes the sheet first; the page goes once the sheet is down.
                guard deletion.isDeleted else { return }
                if let onDeleted { onDeleted(model.path) } else { dismiss() }
            }
        ) {
            EntityEditSheet(store: store, model: model, entity: current, deletion: deletion)
        }
        .onChange(of: model.path) { _, path in onRenamed(path) }
        .task(id: store.lastUpdated) { await model.load() }
        .task(id: EntityTimelineRequest(path: model.path, updated: store.lastUpdated)) {
            guard let days = try? await store.computeEntityTimeline(for: model.path) else { return }
            var day: DaySummary?
            let today = LocalDay.today(at: clockNow())
            if let last = EntityInsights.lastDay(in: days, today: today) {
                guard let loaded = try? await store.computeDay(on: last) else { return }
                day = loaded
            }
            guard
                let tasks = try? await store.computeTaskGroups(today: today, scope: TaskScope(linkedTo: model.path))
            else { return }
            // A request replaced meanwhile must not write its older answer over the newer one.
            guard !Task.isCancelled else { return }
            timeline = days
            lastDay = day
            openTasks = tasks.open
        }
        // A list row that draws nothing is never mounted, so these queries cannot live on the row.
        .background {
            EntityImportantDatesLoader(model: importantDates, file: model.path, enabled: showsImportantDates)
        }
        .background {
            UnlinkedMentionsLoader(model: unlinkedMentions, file: model.path)
        }
        .preference(
            key: ImportantDatesReadyKey.self,
            value: !showsImportantDates || (model.isLoaded && importantDates.hasLoaded)
        )
        .preference(key: UnlinkedMentionsReadyKey.self, value: unlinkedMentions.hasLoaded)
    }

    @ViewBuilder private var headRows: some View {
        if !model.aliasesEditable, !model.aliasesSource.isEmpty {
            Text(verbatim: model.aliasesSource)
                .font(.ink.meta)
                .foregroundStyle(.ink.secondaryText)
                .textSelection(.enabled)
                .inkListRow()
        }
        if let qualifier = current.qualifier {
            labeledRow(String(localized: "Ayırt edici"), qualifier, valueFont: .ink.content)
                .inkListRow()
        }
        labeledRow(
            String(localized: "Gelen bağlantılar"),
            current.incomingLinks.formatted(.number),
            valueFont: .ink.value
        )
        .inkListRow()
        if showsImportantDates {
            EntityImportantDatesRow(file: model.path, model: importantDates)
        }
        if let result = model.renameResult {
            EntityRenameSummary(result: result)
                .inkListRow()
        }
    }

    @ViewBuilder private var readingContent: some View {
        if ["person", "place"].contains(current.kind) {
            Section {
                NavigationLink {
                    GraphView(store: store, focus: model.path)
                } label: {
                    Text("Graph'ta göster")
                        .font(.body)
                        .foregroundStyle(.ink.accent)
                }
                .inkListRow()
            }
            EntityInsightsCard(store: store, entity: current, timeline: timeline ?? [], lastDay: lastDay)
        }
        if model.unreadableFrontmatter {
            Section {
                Text("Frontmatter okunamıyor.")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                    .inkListRow()
            }
        } else {
            fieldSections
        }
        EntityOpenTasksView(store: store, rows: openTasks).id(model.path)
        UnlinkedMentionsSection(model: unlinkedMentions).id(model.path)
        timelineSection
        notesSection
    }

    @ViewBuilder private var fieldSections: some View {
        let grouped = EntityReadPresentation.fieldRows(
            fields: model.fields, schemaKeys: schemaKeys, locale: locale)
        if !grouped.known.isEmpty {
            Section {
                SectionHeader(title: String(localized: "Alanlar"))
                    .inkListRow()
                ForEach(grouped.known) { row in
                    labeledRow(row.label, row.value.isEmpty ? "\u{2014}" : row.value, valueFont: .ink.content)
                        .inkListRow()
                }
            }
        }
        if !grouped.other.isEmpty {
            Section {
                SectionHeader(title: String(localized: "Diğer alanlar"))
                    .inkListRow()
                ForEach(grouped.other) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.key)
                            .font(.ink.meta)
                            .foregroundStyle(.ink.secondaryText)
                        Text(verbatim: row.value.isEmpty ? "\u{2014}" : row.value)
                            .font(.ink.content)
                            .foregroundStyle(.ink.secondaryText)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                    .inkListRow()
                }
            }
        }
    }

    @ViewBuilder private var timelineSection: some View {
        let timeline = self.timeline ?? []
        Section {
            SectionHeader(title: String(localized: "Zaman akışı"), count: timeline.count)
                .inkListRow()
            if timeline.isEmpty {
                Text("Henüz günlük kaydı yok.")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                    .inkListRow()
            }
            ForEach(timeline) { day in
                Text(LocalDay.instant(for: day.date), format: .dateTime.day().month().year())
                    .font(.ink.section)
                    .foregroundStyle(.ink.text)
                    .inkListRow()
                ForEach(day.rows) { row in
                    NavigationLink {
                        DayView(store: store, date: day.date)
                    } label: {
                        LinkedTextView(text: row.text, store: store)
                    }
                    .inkListRow()
                }
            }
        }
    }

    @ViewBuilder private var notesSection: some View {
        Section {
            SectionHeader(title: String(localized: "Serbest notlar"))
                .inkListRow()
            let display = VaultDisplayText.multiline(model.body)
            if display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(verbatim: "\u{2014}")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                    .inkListRow()
            } else {
                Text(verbatim: display)
                    .font(.ink.content)
                    .inkJournalParagraph()
                    .foregroundStyle(.ink.text)
                    .textSelection(.enabled)
                    .inkListRow()
            }
        }
    }

    private func labeledRow(_ label: String, _ value: String, valueFont: Font) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: label)
                .font(.ink.meta)
                .foregroundStyle(.ink.secondaryText)
            Spacer(minLength: 12)
            Text(verbatim: value)
                .font(valueFont)
                .foregroundStyle(.ink.text)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

/// The confirmation captures the requested path; failed deletes keep the detail open.
@MainActor @Observable
final class DefinitionDeletionModel {
    var confirmation = DestructiveConfirmation<String>()
    private(set) var isDeleting = false
    private(set) var isDeleted = false
    private(set) var errorText: String?

    func request(path: String) {
        guard !isDeleting, !isDeleted else { return }
        confirmation.request(path)
    }

    func delete(store: IndexStore, path: String, goal: Bool) async -> Bool {
        guard !isDeleting, !isDeleted else { return false }
        isDeleting = true
        errorText = nil
        defer { isDeleting = false }
        do {
            if goal { try await store.deleteGoal(path: path) } else { try await store.deleteEntity(path: path) }
            isDeleted = true
            return true
        } catch {
            errorText = String(localized: "Dosya silinemedi. Kasayı kontrol edip yeniden dene.")
            return false
        }
    }
}
