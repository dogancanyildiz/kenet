import Summaries
import SwiftUI
import VaultFormat

#if os(macOS)
    /// Mac Today detail shell: ``TodayView`` / ``DayView`` content with the desk chrome. DayView
    /// draws the hour grid and the 300 pt panel (or its sections folded under the grid when the
    /// detail is narrow) from its own loaded day; the shell measures the width, loads "Bu gün
    /// geçmişte" and owns the quick-entry bar.
    struct TodayDeskView: View {
        let store: IndexStore
        @Environment(IntentNavigation.self) private var intentNavigation: IntentNavigation?
        @Environment(ShellNavigationState.self) private var navigation: ShellNavigationState?

        @State private var onThisDay: OnThisDayModel
        @State private var detailWidth: CGFloat = 0

        init(store: IndexStore) {
            self.store = store
            _onThisDay = State(initialValue: OnThisDayModel(store: store))
        }

        var body: some View {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                desk(today: LocalDay.today(at: context.date))
            }
        }

        private func desk(today: CalendarDate) -> some View {
            TodayView(store: store)
                .environment(
                    \.todayDeskChrome,
                    TodayDeskChrome(
                        showsPanel: TodayDeskPlan.showsPanel(detailWidth: detailWidth),
                        onThisDay: onThisDay.entry)
                )
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: {
                    detailWidth = $0
                }
                .safeAreaInset(edge: .bottom) {
                    QuickEntryBar(
                        store: store, isEnabled: true, day: nil,
                        focusRequest: intentNavigation?.focusRequest, acceptsPeopleMentions: true,
                        drafts: navigation
                    )
                    .id("today")
                }
                .task(id: DayRequest(date: today, updated: store.lastUpdated)) {
                    await onThisDay.load(today: today)
                }
        }
    }
#endif
