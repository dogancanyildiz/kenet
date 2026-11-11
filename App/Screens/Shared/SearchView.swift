import SwiftUI
import VaultFormat

struct SearchView: View {
    let store: IndexStore
    @State private var model: SearchModel
    /// Search asked for inside the sheet: ⌘F and a page's magnifier. Made once (``ShellAction``).
    @State private var returnToField: ShellAction
    @FocusState private var searchFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    init(store: IndexStore, initialQuery: String = "") {
        let model = SearchModel(store: store)
        model.query = initialQuery
        self.init(store: store, model: model)
    }

    /// The caller keeps the model (and with it the pages open in the sheet).
    init(store: IndexStore, model: SearchModel) {
        self.store = store
        _model = State(initialValue: model)
        _returnToField = State(initialValue: ShellAction { [model] in model.returnToField() })
    }

    var body: some View {
        NavigationStack(path: $model.path) {
            VStack(spacing: 0) {
                InkPageTitle("Ara")
                searchField
                    .padding(.horizontal, InkSpacing.margin)
                    .padding(.bottom, 8)
                scopeChips
                if model.isSearching { ProgressView().padding(.bottom, 8) }
                if let error = model.errorText {
                    Text(verbatim: error).foregroundStyle(.ink.danger).padding()
                }
                resultList
            }
            .inkPageColumn()
            .inkSheet("Ara", closeIdentifier: "button.search.close")
            .navigationDestination(for: SearchDestination.self) { destination in
                switch destination {
                case .entity(let file):
                    if let entity = store.content.entities.first(where: { $0.id == file }) {
                        EntityView(store: store, entity: entity)
                    } else {
                        ContentUnavailableView("Sonuç artık mevcut değil", systemImage: "doc.questionmark")
                    }
                case .day(let date): DayView(store: store, date: date)
                case .note(let file): SearchNoteView(store: store, file: file)
                }
            }
        }
        // Nested destinations (notes) use this so "Kapat" closes the sheet, not only the push.
        .inkSheetDismissAction { dismiss() }
        #if os(macOS)
            .frame(minWidth: 520, idealWidth: 650, minHeight: 460, idealHeight: 650)
            .focusedSceneValue(\.openSearch, returnToField)
        #endif
        .searchSheetContext(returnToField)
        .onChange(of: model.path) { _, path in if path.isEmpty { searchFocused = true } }
        .onChange(of: model.fieldFocusRequests) { searchFocused = true }
        .onChange(of: store.vaultURL) { _, _ in model.reloadHistory() }
        .task { searchFocused = true }
        .task(id: store.vaultURL) { model.reloadHistory() }
        .task(id: SearchRequest(query: model.query, root: store.vaultURL, updated: store.lastUpdated)) {
            await model.search(debounce: true)
        }
    }

    private var searchField: some View {
        InkFilterField(
            "Kişi, konum veya metin ara", text: $model.query, isFocused: $searchFocused,
            identifier: "field.search", clearIdentifier: "button.search.clear"
        )
        .onSubmit {
            if let selected = model.selected {
                open(selected)
            } else {
                model.rememberQuery()
            }
        }
        #if os(macOS)
            .onKeyPress(.downArrow) {
                model.moveSelection(by: 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                model.moveSelection(by: -1)
                return .handled
            }
        #endif
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            List {
                if model.isEmpty {
                    Section {
                        SectionHeader(title: PresentationLocalization.string(localized: "Son aramalar", locale: locale))
                            .inkListRow()
                        ForEach(model.recentQueries, id: \.self) { query in
                            Button {
                                model.query = query
                                searchFocused = true
                            } label: {
                                MarginRow(kind: .external, time: nil) {
                                    Text(verbatim: query)
                                        .foregroundStyle(.ink.text)
                                }
                            }
                            .buttonStyle(.plain)
                            .inkListRow()
                        }
                    }
                } else if model.visibleResults.isEmpty && !model.isSearching && model.errorText == nil {
                    EmptyState("Sonuç bulunamadı")
                        .inkListRow()
                } else {
                    ForEach(SearchGroup.allCases) { group in
                        let items = model.visibleResults.filter { $0.group == group }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                groupHeader(group.title, count: items.count)
                                InkCard(padded: false) {
                                    // Each row after the first carries its rule on its own top
                                    // edge, so every pair of rows is parted alike (drawing); the
                                    // selected row's tint stays inside the card's corners.
                                    VStack(spacing: 0) {
                                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                            resultRow(item)
                                                .overlay(alignment: .top) {
                                                    if index > 0 { InkCardDivider() }
                                                }
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous))
                                }
                            }
                            .inkListRow()
                        }
                    }
                }
            }
            .listStyle(.plain)
            .inkPage()
            .onChange(of: model.selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    /// Thin scope capsules (Şafak çizimi, ~28 pt); the tap area stays 44 pt around them. The
    /// selected one is accent-soft; with "Renksiz ayırt et" it also carries a checkmark.
    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SearchScope.allCases) { item in
                    scopeChip(item)
                }
            }
            .padding(.horizontal, InkSpacing.margin)
        }
        .padding(.bottom, 4)
    }

    private func scopeChip(_ item: SearchScope) -> some View {
        TagChip(
            title: item.title, isSelected: model.scope == item, onTap: { model.scope = item },
            accentSelection: true)
    }

    /// Result group title (Şafak drawing): small grey "Kişiler" with its count at the trailing edge,
    /// lighter than a page's section titles so the results lead.
    private func groupHeader(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: title)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(SectionHeader.titleIdentifier)
            Spacer(minLength: 8)
            Text(count.formatted(.number.grouping(.never).locale(locale)))
                .monospacedDigit()
                .accessibilityIdentifier(SectionHeader.counterIdentifier)
        }
        .font(.ink.meta.weight(.semibold))
        .foregroundStyle(Color.ink.secondaryText)
        .padding(.top, 4)
    }

    /// Kind mark of a result row: a person or place as its initials badge ("BT"); other entities,
    /// events, notes on an accent-soft tile; a task as its empty box.
    @ViewBuilder
    private func resultMark(_ item: SearchItem) -> some View {
        if case .entity(let file) = item.destination, item.group != .entities,
            let entity = store.content.entities.first(where: { $0.id == file })
        {
            EntityInitialBadge(entity: entity)
        } else {
            resultSymbol(item.group)
        }
    }

    @ViewBuilder
    private func resultSymbol(_ group: SearchGroup) -> some View {
        let symbol: String? =
            switch group {
            case .people: "person"
            case .places: "mappin"
            case .entities: "tag"
            case .events: "calendar"
            case .notes: "doc.text"
            case .tasks: nil
            }
        if let symbol {
            Image(systemName: symbol)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.ink.accent)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.ink.accentSoft)
                )
        } else {
            Circle()
                .strokeBorder(Color.ink.control, lineWidth: InkStroke.control)
                .frame(width: 22, height: 22)
                .frame(width: 30, height: 30)
        }
    }

    /// Matches drawn on a soft accent wash instead of in bold (Şafak çizimi).
    private func highlighted(_ text: String) -> AttributedString {
        var result = SearchHighlight.text(text, query: model.query)
        for run in result.runs where run.inlinePresentationIntent == .stronglyEmphasized {
            result[run.range].inlinePresentationIntent = nil
            result[run.range].backgroundColor = Color.ink.accentSoft
        }
        return result
    }

    private func resultRow(_ item: SearchItem) -> some View {
        Button {
            open(item)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                resultMark(item)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(highlighted(item.title))
                        .foregroundStyle(.ink.text)
                        .lineLimit(3)
                    let detail = detailText(item)
                    if !detail.isEmpty {
                        Text(highlighted(detail))
                            .font(.ink.meta)
                            .foregroundStyle(.ink.secondaryText)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if Self.showsChevron(item.group) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.ink.tertiaryText)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: TapTarget.minimumLength, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, InkSpacing.cardPadding)
        .padding(.vertical, 6)
        .background(item.id == model.selectedID ? Color.ink.accentSoft : Color.clear)
        .accessibilityElement(children: .contain)
        .id(item.id)
    }

    /// The row's second line in the drawing's form. A person or place: "Kişi · son görülme 19 Eyl",
    /// plus the matched alias when the name itself does not show the query. An event or a task:
    /// "19 Eyl Cmt" (the year only outside the current year). Notes keep their name.
    private func detailText(_ item: SearchItem) -> String {
        switch item.destination {
        case .entity(let file):
            var parts = [kindLabel(item.group, file: file)]
            let query = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !item.detail.isEmpty, !query.isEmpty,
                item.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) == nil
            {
                parts.append(item.detail)
            }
            if let last = store.entityUsage.first(where: { $0.file == file })?.lastDate {
                parts.append(
                    PresentationLocalization.string(
                        localized: "son görülme \(dayText(last, weekday: false))", locale: locale))
            }
            return parts.joined(separator: " · ")
        case .day(let day):
            return dayText(day, weekday: true)
        case .note:
            return item.detail
        }
    }

    private func kindLabel(_ group: SearchGroup, file: String) -> String {
        switch group {
        case .people: return PresentationLocalization.string(localized: "Kişi", locale: locale)
        case .places: return PresentationLocalization.string(localized: "Konum", locale: locale)
        default:
            let kind = store.content.entities.first { $0.id == file }?.kind ?? ""
            return EntityTypeChoices.choices(store.entityTypes).first { $0.id == kind }?.name ?? kind
        }
    }

    /// "19 Eyl Cmt" or "19 Eyl" ("Sep 19, 2025" style with the year outside the current year).
    private func dayText(_ day: CalendarDate, weekday: Bool) -> String {
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        if weekday { style = style.weekday(.abbreviated) }
        if day.year != LocalDay.today().year { style = style.year() }
        return LocalDay.instant(for: day).formatted(style.locale(locale))
    }

    /// Rows that open a page of their own (a person, a place, a note) end in "›"; events and tasks
    /// open their day.
    private static func showsChevron(_ group: SearchGroup) -> Bool {
        switch group {
        case .people, .places, .entities, .notes: true
        case .events, .tasks: false
        }
    }

    private func open(_ item: SearchItem) {
        if let destination = model.activate(item) {
            searchFocused = false
            model.path.append(destination)
        }
    }
}

extension View {
    /// What search means on a page opened inside the search sheet: back to the results. Mac draws
    /// the manşet magnifier only in this context (``SearchButton``): the window's toolbar search
    /// is behind the sheet.
    func searchSheetContext(_ showResults: ShellAction) -> some View {
        environment(\.isSearchSheet, true)
            .environment(\.openSearch, showResults)
    }
}

private struct SearchRequest: Hashable {
    let query: String
    let root: URL?
    let updated: Date?
}
