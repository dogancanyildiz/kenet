import SwiftUI
import VaultFormat
import VaultIndex

/// Günlük list column: manşet, the Özetler and weekly review links under it, the month and the days.
///
/// Mac: the manşet and the two links are the pinned strip; the month and the days scroll in one
/// list under it. Held in a stack above the list, the month too was taller than a short window's
/// column (1000 × 560 or so): the stack overflowed both ways and the manşet went under the
/// toolbar. The links stay out of the list, where a text button in a selectable row is not sure
/// to take a click. iOS (split shell) keeps the stack.
struct MacDaysColumn: View {
    let store: IndexStore
    @Binding var selection: String?
    let openSummaries: () -> Void
    @State private var showsWeeklyReview = false
    @State private var weeklyReviewNotice: WeeklyReviewNotice?
    /// Nil until the first query returns; a reload keeps the previous rows until then.
    @State private var days: [DayOverview]?

    /// As the iPhone list shows them: task counts and first events in, empty days out.
    private var listedDays: [DayOverview] {
        DayOverview.listed(days ?? [], fragments: store.content.fragments)
    }

    var body: some View {
        column
            .weeklyReviewSheet(isPresented: $showsWeeklyReview, store: store) { weeklyReviewNotice = $0 }
            .task(id: DayRangeRequest(from: nil, to: nil, updated: store.lastUpdated)) {
                if let loaded = try? await store.computeDaySummaries() { days = loaded }
            }
    }

    @ViewBuilder private var column: some View {
        #if os(macOS)
            MacDayList(days: listedDays, selection: $selection) {
                InkScrolledMasthead(columnTop)
                    .listRowInsets(EdgeInsets())
                    .columnTopRow()
                if let notice = weeklyReviewNotice {
                    InfoBand(kind: notice.kind, verbatim: notice.text, onDismiss: { weeklyReviewNotice = nil })
                        .listRowInsets(EdgeInsets())
                        .columnTopRow()
                }
                DaysCalendarView(store: store) { selection = VaultLayout.dayPath($0) }
                    .listRowInsets(EdgeInsets())
                    .columnTopRow()
            }
            .inkPinnedMasthead(columnTop, insets: EdgeInsets(), columnWidth: .infinity)
        #else
            VStack(spacing: 0) {
                InkPageTitle("Günlük").macListColumnTitle()
                links
                    // Starts where the manşet above it starts.
                    .padding(.leading, InkSpacing.margin + MacListColumnChrome.rowInset)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Its whole height before the list's: at accessibility sizes the column is short of
                    // height and the stack would otherwise cut the link names.
                    .fixedSize(horizontal: false, vertical: true)
                if let notice = weeklyReviewNotice {
                    InfoBand(kind: notice.kind, verbatim: notice.text, onDismiss: { weeklyReviewNotice = nil })
                }
                DaysCalendarView(store: store) { selection = VaultLayout.dayPath($0) }
                MacDayList(days: listedDays, selection: $selection)
            }
        #endif
    }

    #if os(macOS)
        /// Manşet and links: the strip above the month, in line with the list's rows.
        private var columnTop: some View {
            VStack(alignment: .leading, spacing: 0) {
                InkPageTitleRow("Günlük").pinned
                links
                    .padding(.horizontal, InkSpacing.margin + MacListColumnChrome.rowInset)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    #endif

    private var links: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: openSummaries) {
                Label("Özetler", systemImage: "chart.bar")
            }
            .accessibilityIdentifier("button.summaries")
            // Like the iPhone row: once this week is reviewed, the link says so.
            HStack(alignment: .firstTextBaseline, spacing: InkSpacing.row) {
                Button {
                    showsWeeklyReview = true
                } label: {
                    Label("Haftalık inceleme", systemImage: "checklist")
                }
                .accessibilityIdentifier("button.weeklyReview")
                WeeklyReviewEntryStatus()
            }
        }
        .buttonStyle(InkTextButtonStyle())
    }
}

#if os(macOS)
    extension View {
        /// A row of the Günlük column's top (links, notice, month) inside its list: on paper, no
        /// separator, not a day to select.
        fileprivate func columnTopRow() -> some View {
            listRowSeparator(.hidden)
                .listRowBackground(Color.ink.paper)
                .selectionDisabled()
        }
    }
#endif
