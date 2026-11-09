import SwiftUI
import VaultFormat

/// Reverse chronological summaries lead into the shared day layout.
struct DaysView: View {
    let store: IndexStore
    var previewSelectedDay: CalendarDate? = nil
    @Environment(\.clockNow) private var clockNow
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    @Environment(ShellNavigationState.self) private var navigation: ShellNavigationState?
    @State private var selectedDay: CalendarDate?
    @State private var showsSummaries = false
    @State private var showsWeeklyReview = false
    @State private var weeklyReviewNotice: WeeklyReviewNotice?
    /// Nil until the first query returns; a reload keeps the previous rows until then.
    @State private var days: [DayOverview]?

    private var today: CalendarDate {
        LocalDay.today(at: clockNow())
    }

    private var visibleDays: [DayOverview]? {
        guard let days else { return nil }
        return DayOverview.listed(days, fragments: store.content.fragments)
    }

    var body: some View {
        List {
            InkPageTitleRow("Günlük") {
                SearchButton()
            }
            topChipsRow
                .inkListRow()
            if let notice = weeklyReviewNotice {
                InfoBand(kind: notice.kind, verbatim: notice.text, onDismiss: { weeklyReviewNotice = nil })
                    .inkListRow()
            }
            Section {
                DaysCalendarView(
                    store: store, selected: selectedDay ?? previewSelectedDay
                ) { selectedDay = $0 }
                .inkListRow()
            }
            ForEach(visibleDays ?? []) { day in
                Button {
                    selectedDay = day.date
                } label: {
                    DayRow(day: day, isToday: day.date == today, showsCard: true)
                }
                .buttonStyle(.plain)
                .inkListRow()
            }
            if visibleDays?.isEmpty == true {
                EmptyState("Henüz gün yok")
                    .inkListRow()
            }
        }
        .listStyle(.plain)
        .inkPage()
        .inkGlow()
        .inkPageScrollColumn()
        .navigationDestination(isPresented: $showsSummaries) { SummariesView(store: store) }
        .navigationDestination(item: $selectedDay) { day in
            DayView(
                store: store, date: day,
                onReplaceDay: { selectedDay = $0 },
                onReturnToToday: {
                    selectedDay = nil
                    #if os(macOS)
                        navigation?.goToToday(shell: .split)
                    #else
                        navigation?.todayPath = NavigationPath()
                        navigation?.goToToday(shell: .tabs)
                    #endif
                })
        }
        .weeklyReviewSheet(isPresented: $showsWeeklyReview, store: store) { weeklyReviewNotice = $0 }
        .task(id: DayRangeRequest(from: nil, to: nil, updated: store.lastUpdated)) {
            if let loaded = try? await store.computeDaySummaries() { days = loaded }
        }
        .inkRootPageNavigationTitle("Günlük")
        .accessibilityIdentifier("screen.days")
    }

    @ViewBuilder
    private var topChipsRow: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        layout {
            Button {
                showsSummaries = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar")
                        .font(.ink.meta)
                        .foregroundStyle(.ink.accent)
                        .accessibilityHidden(true)
                    Text("Özetler")
                        .font(.body)
                        .foregroundStyle(.ink.text)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.ink.surface)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.ink.rule, lineWidth: InkStroke.hairline(scale: displayScale))
                )
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("button.summaries")

            Button {
                showsWeeklyReview = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .font(.ink.meta)
                        .foregroundStyle(.ink.accent)
                        .accessibilityHidden(true)
                    Text("Haftalık inceleme")
                        .font(.body)
                        .foregroundStyle(.ink.text)
                    WeeklyReviewEntryStatus()
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.ink.surface)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.ink.rule, lineWidth: InkStroke.hairline(scale: displayScale))
                )
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("button.weeklyReview")
        }
        .padding(.vertical, 2)
    }
}

struct DayRow: View {
    let day: DayOverview
    var isToday: Bool = false
    var showsCard: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if showsCard {
                InkCard {
                    rowContent
                }
            } else {
                rowContent
                    .padding(.vertical, 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: VoiceOverCopy.dayRowLabel(day)))
    }

    @ViewBuilder
    private var rowContent: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            VStack(spacing: 1) {
                Text(day.date.day, format: .number)
                    .font(.ink.dayName)
                    .monospacedDigit()
                    .foregroundStyle(isToday ? .ink.accent : .ink.text)
                Text(LocalDay.instant(for: day.date), format: .dateTime.weekday(.abbreviated))
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
            }
            .frame(minWidth: dynamicTypeSize.isAccessibilitySize ? nil : 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if isToday {
                        Text("Bugün")
                            .font(.ink.meta)
                            .foregroundStyle(.ink.accent)
                        Text(verbatim: "·")
                            .font(.ink.meta)
                            .foregroundStyle(.ink.secondaryText)
                    }
                    // The list runs back across months: each row names its own month.
                    Text(LocalDay.instant(for: day.date), format: .dateTime.month(.wide).year())
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                    Text(verbatim: "·")
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                    Text("\(day.eventCount) olay · \(day.taskCount) görev")
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                }
                if let preview = day.displayPreview {
                    Text(verbatim: VaultDisplayText.line(preview))
                        .font(.ink.contentSmall)
                        .foregroundStyle(.ink.text)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
