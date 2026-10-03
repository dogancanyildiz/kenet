#if os(macOS)
    import SwiftUI
    import VaultFormat

    /// Lists stay alongside their selection in the desktop's three columns.
    struct MacNavigation: View {
        let store: IndexStore
        @State private var section: DesktopSection? = .today
        @State private var selectedDay: String?
        @State private var selectedEntity: String?
        @State private var selectedSummary: EntitySummary?
        @State private var entityRouteID = UUID()
        @State private var entityOrder = EntityOrdering.name
        @State private var entitySearch = ""

        var body: some View {
            NavigationSplitView {
                List(DesktopSection.allCases, selection: $section) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
                .navigationTitle("Journal")
            } content: {
                switch section ?? .today {
                case .today, .days:
                    VStack(spacing: 0) {
                        DaysCalendarView(store: store) { selectedDay = "journal/\($0).md" }
                        List(store.content.days, selection: $selectedDay) { day in
                            DayRow(day: day).tag(day.id)
                        }
                    }.navigationTitle("Günlük")
                case .people, .places:
                    VStack(spacing: 0) {
                        EntityListControls(order: $entityOrder, search: $entitySearch)
                        List(
                            EntityListQuery.entities(
                                in: store.content, usage: store.entityUsage, kind: entityKind,
                                search: entitySearch, order: entityOrder), selection: entitySelection
                        ) { entity in
                            EntityRow(entity: entity).tag(entity.id)
                        }
                    }.navigationTitle((section ?? .people).title)
                case .notes:
                    List { EmptyView() }
                        .overlay { Text("Notlar sonraki sürümde").foregroundStyle(.secondary) }
                        .navigationTitle("Notlar")
                }
            } detail: {
                NavigationStack {
                    switch section ?? .today {
                    case .today:
                        TodayView(store: store)
                    case .days:
                        if let path = selectedDay,
                            let day = CalendarDate(String(path.dropFirst("journal/".count).dropLast(3)))
                        {
                            DayView(store: store, date: day).id(day)
                        } else {
                            ContentUnavailableView("Bir gün seç", systemImage: "book.closed")
                                .toolbar { SearchButton() }
                        }
                    case .people, .places:
                        if let entity = selectedSummary, entity.kind == entityKind {
                            EntityView(store: store, entity: entity) { path in
                                selectedEntity = path
                                selectedSummary = store.content.entities.first { $0.id == path } ?? selectedSummary
                            }.id(entityRouteID)
                        } else {
                            ContentUnavailableView("Bir varlık seç", systemImage: "person.2")
                                .toolbar { SearchButton() }
                        }
                    case .notes:
                        ContentUnavailableView("Notlar sonraki sürümde", systemImage: "note.text")
                            .toolbar { SearchButton() }
                    }
                }
                .id(section)
            }
            .onChange(of: selectedDay) { _, value in
                if value != nil { section = .days }
            }
            .focusedSceneValue(
                \.goToToday,
                {
                    section = .today
                    selectedDay = nil
                })
        }

        private var entitySelection: Binding<String?> {
            Binding(
                get: { selectedEntity },
                set: { path in
                    selectedEntity = path
                    selectedSummary = store.content.entities.first { $0.id == path }
                    entityRouteID = UUID()
                })
        }

        private var entityKind: String { section == .places ? "place" : "person" }
    }

    struct TodayNavigationKey: FocusedValueKey {
        typealias Value = () -> Void
    }

    extension FocusedValues {
        var goToToday: (() -> Void)? {
            get { self[TodayNavigationKey.self] }
            set { self[TodayNavigationKey.self] = newValue }
        }
    }

    private enum DesktopSection: String, CaseIterable, Identifiable {
        case today, days, people, places, notes
        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .today: "Bugün"
            case .days: "Günlük"
            case .people: "Kişiler"
            case .places: "Konumlar"
            case .notes: "Notlar"
            }
        }

        var symbol: String {
            switch self {
            case .today: "sun.max"
            case .days: "book.closed"
            case .people: "person.2"
            case .places: "mappin.and.ellipse"
            case .notes: "note.text"
            }
        }
    }
#endif
