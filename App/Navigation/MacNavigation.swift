#if os(macOS)
    import SwiftUI

    /// Lists stay alongside their selection in the desktop's three columns.
    struct MacNavigation: View {
        let store: IndexStore
        @State private var section: DesktopSection? = .today
        @State private var selectedDay: String?
        @State private var selectedEntity: String?

        var body: some View {
            NavigationSplitView {
                List(DesktopSection.allCases, selection: $section) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
                .navigationTitle("Journal")
            } content: {
                switch section ?? .today {
                case .today, .days:
                    List(store.content.days, selection: $selectedDay) { day in
                        DayRow(day: day).tag(day.id)
                    }
                    .navigationTitle("Günlük")
                case .people, .places:
                    List(store.content.entities.filter { $0.kind == entityKind }, selection: $selectedEntity) {
                        entity in
                        EntityRow(entity: entity).tag(entity.id)
                    }
                    .navigationTitle((section ?? .people).title)
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
                        if let day = store.content.days.first(where: { $0.id == selectedDay }) {
                            DayView(store: store, date: day.date)
                        } else {
                            ContentUnavailableView("Bir gün seç", systemImage: "book.closed")
                                .toolbar { SearchButton() }
                        }
                    case .people, .places:
                        if let entity = store.content.entities.first(where: {
                            $0.id == selectedEntity && $0.kind == entityKind
                        }) {
                            EntityView(store: store, entity: entity)
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
