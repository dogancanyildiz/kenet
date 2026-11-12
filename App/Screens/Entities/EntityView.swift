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
    /// What a chip or a timeline row opens: pushed from outside the list, so rows draw no
    /// disclosure arrow (a `NavigationLink` in a list row adds one).
    @State private var pushed: EntityPagePush?
    /// Optional: hosts without a calendar (some tests) draw no calendar section.
    @Environment(CalendarService.self) private var calendar: CalendarService?
    @State private var calendarModel = EntityCalendarModel()

    /// `model`: the page's file model; nil builds one for `entity`. A test hands its own in to rename
    /// the file as the edit sheet does and watch the page follow the new path.
    init(
        store: IndexStore, entity: EntitySummary, onRenamed: @escaping (String) -> Void = { _ in },
        onDeleted: ((String) -> Void)? = nil, model: EntityDetailModel? = nil
    ) {
        self.store = store
        self.entity = entity
        self.onRenamed = onRenamed
        self.onDeleted = onDeleted
        _model = State(initialValue: model ?? EntityDetailModel(store: store, path: entity.id))
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

    private var calendarNames: CalendarPersonNames {
        CalendarPersonNames(fullName: current.name, aliases: model.aliases)
    }

    private var kindLabel: String {
        EntityTypeChoices.choices(store.entityTypes, language: locale.language.languageCode?.identifier ?? "en")
            .first { $0.id == current.kind }?.name
            ?? current.kind
    }

    private var lastSeen: CalendarDate? {
        store.entityUsageByFile[model.path]?.lastDate
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
        .navigationDestination(item: $pushed) { push in
            switch push {
            case .graph: GraphView(store: store, focus: model.path)
            case .dayGraph(let date): GraphView(store: store, scope: .day(date))
            case .day(let date): DayView(store: store, date: date)
            case .entity(let entity): EntityView(store: store, entity: entity)
            }
        }
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
        .task(
            id: EntityCalendarLoadKey(
                fullName: current.name, aliases: model.aliases, changes: calendar?.changeCount ?? 0,
                canRead: calendar?.authorization.canRead ?? false)
        ) {
            // The same gate as the day pages: a test or a tour never reads the real calendar.
            guard current.kind == "person", let calendar, AppLaunchPolicy.allowsCalendarLoad() else { return }
            await calendarModel.load(calendar: calendar, names: calendarNames, now: clockNow())
        }
        .preference(
            key: ImportantDatesReadyKey.self,
            value: !showsImportantDates || (model.isLoaded && importantDates.hasLoaded)
        )
        .preference(key: UnlinkedMentionsReadyKey.self, value: unlinkedMentions.hasLoaded)
    }

    @ViewBuilder private var headRows: some View {
        // Şafak chip row under the manşet: the next anniversary and "Graph'ta göster". The kind
        // is already in the künye.
        if (showsImportantDates && importantDates.nearest(file: model.path) != nil) || isGraphNode {
            // A chip row; stacked when the two chips do not fit side by side.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { headChips }
                VStack(alignment: .leading, spacing: 0) { headChips }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .inkListRow()
        }
        // docs/screens.md order: the Son görüşme / Son ziyaret card sits right under the manşet.
        if ["person", "place"].contains(current.kind), timeline != nil {
            InkCard {
                EntityInsightsCard(
                    store: store, entity: current, timeline: timeline ?? [], lastDay: lastDay,
                    open: { pushed = .entity($0) })
            }
            .inkListRow()
        }
        fieldsCard
    }

    @ViewBuilder private var headChips: some View {
        if showsImportantDates {
            EntityImportantDatesChip(file: model.path, model: importantDates)
                .fixedSize()
        }
        if isGraphNode {
            // A button, not a list `NavigationLink`: a link in a list row draws a disclosure arrow.
            Button {
                pushed = .graph
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "point.3.connected.trianglepath.dotted").accessibilityHidden(true)
                    Text("Graph'ta göster").lineLimit(1)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.ink.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.ink.accentSoft, in: Capsule())
                .fixedSize()
                .frame(minHeight: TapTarget.minimumLength)
                // `minHeight` alone grows to whatever height the row offers.
                .fixedSize()
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
    }

    /// People, places and custom types are graph nodes; a custom type's node is switched on.
    private var isGraphNode: Bool { Self.showsGraphLink(kind: current.kind, types: store.entityTypes) }

    /// Pure rule (unit-tested): the kinds the Graph draws, from the same type choices as its
    /// filter menu (`GraphView`), so the page never opens a Graph without its node.
    static func showsGraphLink(kind: String, types: EntityTypeCatalog) -> Bool {
        EntityTypeChoices.choices(types).contains { $0.id == kind }
    }

    @ViewBuilder private var readingContent: some View {
        if isGraphNode {
            EntityRelationsHost(store: store, path: model.path).id(model.path)
        }
        EntityOpenTasksView(store: store, rows: openTasks).id(model.path)
        if current.kind == "person", calendar != nil {
            EntityCalendarSection(
                names: calendarNames,
                birthday: PersonBirthday.find(in: model.fields.map { ($0.key, $0.value) }),
                model: calendarModel)
        }
        UnlinkedMentionsSection(model: unlinkedMentions).id(model.path)
        timelineSection
        notesSection
    }

    /// One key–value card (Şafak drawing): distinguishing name, template fields, then the other
    /// frontmatter keys in secondary ink, and the incoming link count. Key left, value right.
    @ViewBuilder private var fieldsCard: some View {
        let grouped = EntityReadPresentation.fieldRows(
            fields: model.fields, schemaKeys: schemaKeys, locale: locale)
        InkCard(padded: false) {
            VStack(alignment: .leading, spacing: 0) {
                if let qualifier = current.qualifier {
                    kvRow(
                        PresentationLocalization.string(localized: "Ayırt edici", locale: locale), qualifier,
                        valueFont: .subheadline.weight(.medium))
                    InkCardDivider()
                }
                if model.unreadableFrontmatter {
                    Text("Frontmatter okunamıyor.")
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                        .frame(minHeight: 40, alignment: .leading)
                    InkCardDivider()
                } else {
                    ForEach(grouped.known) { row in
                        kvRow(
                            row.label, row.value.isEmpty ? "\u{2014}" : row.value,
                            valueFont: .subheadline.weight(.medium))
                        InkCardDivider()
                    }
                    ForEach(grouped.other) { row in
                        kvRow(
                            row.key, row.value.isEmpty ? "\u{2014}" : row.value, valueFont: .subheadline,
                            valueColor: .ink.secondaryText)
                        InkCardDivider()
                    }
                }
                kvRow(
                    PresentationLocalization.string(localized: "Gelen bağlantılar", locale: locale),
                    current.incomingLinks.formatted(.number),
                    valueFont: .subheadline.monospacedDigit())
                if !model.aliasesEditable, !model.aliasesSource.isEmpty {
                    Text(verbatim: model.aliasesSource).font(.ink.meta).foregroundStyle(.ink.secondaryText)
                        .textSelection(.enabled)
                        .padding(.bottom, 8)
                }
                if let result = model.renameResult { EntityRenameSummary(result: result).padding(.bottom, 8) }
            }
            .padding(.horizontal, padding)
        }
        .inkListRow()
    }

    @ScaledMetric(relativeTo: .body) private var padding = InkSpacing.cardPadding

    @ViewBuilder private var timelineSection: some View {
        let timeline = self.timeline ?? []
        Section {
            SectionHeader(
                title: PresentationLocalization.string(localized: "Zaman akışı", locale: locale),
                counter: timeline.isEmpty
                    ? nil : PresentationLocalization.string(localized: "\(timeline.count) gün", locale: locale)
            ).inkListRow()
            if timeline.isEmpty {
                Text("Henüz günlük kaydı yok.")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                    .inkListRow()
            }
            // Şafak drawing: one card per record, the day and time on the card's second line; no
            // day heads. The day's graph moves to the card's context menu.
            ForEach(timeline) { day in
                ForEach(day.rows) { row in
                    Button {
                        pushed = .day(day.date)
                    } label: {
                        timelineRow(row, date: day.date)
                    }
                    .buttonStyle(.borderless)
                    .contextMenu {
                        Button {
                            pushed = .dayGraph(day.date)
                        } label: {
                            Label("Günün grafiği", systemImage: "point.3.connected.trianglepath.dotted")
                        }
                    }
                    .accessibilityAction(named: Text("Günün grafiği")) { pushed = .dayGraph(day.date) }
                    .inkListRow()
                }
            }
        }
    }

    /// Card row of the timeline: icon box (calendar for an event, pencil for journal text), the
    /// linked text, under it "19 Eyl Cmt · 10:30" or "19 Eyl Cmt · günlük yazısı", a chevron.
    private func timelineRow(_ row: EntityTimelineRow, date: CalendarDate) -> some View {
        let isEvent = row.kind == "event"
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: isEvent ? "calendar" : "pencil")
                .font(.footnote)
                .foregroundStyle(isEvent ? Color.ink.accent : Color.ink.secondaryText)
                .frame(width: badgeSide, height: badgeSide)
                .background(
                    isEvent ? Color.ink.accentSoft : Color.ink.well,
                    in: RoundedRectangle(cornerRadius: InkCorner.xs, style: .continuous)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                LinkedTextView(text: row.text, store: store)
                    .font(.subheadline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: timelineMeta(row, date: date))
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.ink.tertiaryText)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
        .modifier(InkCardModifier(cornerRadius: InkCorner.md))
        .contentShape(Rectangle())
    }

    /// "19 Eyl Cmt · 10:30" for a timed event, "19 Eyl Cmt · günlük yazısı" for journal text; the
    /// year only outside the current year.
    private func timelineMeta(_ row: EntityTimelineRow, date: CalendarDate) -> String {
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated).weekday(.abbreviated)
        if date.year != LocalDay.today().year { style = style.year() }
        let day = LocalDay.instant(for: date).formatted(style.locale(locale))
        if row.kind == "event" {
            return row.time.map { day + " · " + $0 } ?? day
        }
        return PresentationLocalization.string(localized: "\(day) · günlük yazısı", locale: locale)
    }

    @ScaledMetric(relativeTo: .body) private var badgeSide: CGFloat = 32
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder private var notesSection: some View {
        Section {
            SectionHeader(title: PresentationLocalization.string(localized: "Serbest notlar", locale: locale))
                .inkListRow()
            let display = VaultDisplayText.multiline(model.body)
            if display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(verbatim: "\u{2014}")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                    .inkListRow()
            } else {
                InkCard {
                    Text(verbatim: display).font(.ink.content).inkJournalParagraph()
                        .foregroundStyle(.ink.text).textSelection(.enabled)
                }.inkListRow()
            }
        }
    }

    /// Key–value row of the fields card: the key in secondary ink on the left, the value on the right.
    private func kvRow(
        _ label: String, _ value: String, valueFont: Font, valueColor: Color = .ink.text
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: label)
                .font(.subheadline)
                .foregroundStyle(.ink.secondaryText)
                .accessibilityIdentifier("entity.labeledRow.label")
            Spacer(minLength: 12)
            Text(verbatim: value)
                .font(valueFont)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .accessibilityIdentifier("entity.labeledRow.value")
        }
        .padding(.vertical, 10)
        .frame(minHeight: 40)
    }
}

/// A page the entity page pushes onto its stack.
enum EntityPagePush: Hashable {
    case graph
    case dayGraph(CalendarDate)
    case day(CalendarDate)
    case entity(EntitySummary)
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

private struct EntityRelationsHost: View {
    @State private var model: EntityRelationsModel
    init(store: IndexStore, path: String) {
        _model = State(initialValue: EntityRelationsModel(store: store, path: path))
    }
    var body: some View {
        EntityRelationsSection(model: model)
            .task(id: model.store.lastUpdated) { await model.load() }
    }
}
