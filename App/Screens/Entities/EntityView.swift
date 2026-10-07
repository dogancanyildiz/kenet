import SwiftUI
import VaultFormat

struct EntityView: View {
    let store: IndexStore
    let entity: EntitySummary
    let onRenamed: (String) -> Void
    @Environment(\.locale) private var locale
    @State private var model: EntityDetailModel
    @State private var isEditing = false

    init(store: IndexStore, entity: EntitySummary, onRenamed: @escaping (String) -> Void = { _ in }) {
        self.store = store
        self.entity = entity
        self.onRenamed = onRenamed
        _model = State(initialValue: EntityDetailModel(store: store, path: entity.id))
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

    private var schemaKeys: Set<String> {
        Set(store.entityTypes.allTypes.first { $0.id == current.kind }?.fields.map(\.key) ?? [])
    }

    var body: some View {
        List {
            Section {
                // The manşet row carries the page actions, so it is there before the file loads.
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
            if model.isLoaded {
                readingContent
            }
            if let error = model.errorText {
                Text(verbatim: error).font(.ink.meta).foregroundStyle(.ink.danger)
                    .inkListRow()
            }
        }
        .listStyle(.plain)
        .inkPage()
        .inkPageColumn()
        .environment(\.entityLookup, LinkedTextInk.lookup(entities: store.content.entities))
        .inkPageNavigationTitle(verbatim: current.name)
        .sheet(isPresented: $isEditing) {
            EntityEditSheet(store: store, model: model, entity: current)
        }
        .onChange(of: model.path) { _, path in onRenamed(path) }
        .task(id: store.lastUpdated) { await model.load() }
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
            EntityInsightsCard(store: store, entity: current)
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
        EntityOpenTasksView(store: store, path: model.path).id(model.path)
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
        let timeline = store.content.entityTimeline[model.path] ?? []
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
