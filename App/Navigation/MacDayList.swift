import SwiftUI
import VaultIndex

/// Günlük column. Selection chrome lives here so the day row and its tests share one list.
/// `top`: rows above the days (the Mac column's links and month), not selectable.
struct MacDayList<Top: View>: View {
    let days: [DayOverview]
    @Binding var selection: String?
    @ViewBuilder var top: Top

    var body: some View {
        List(selection: $selection) {
            top
            ForEach(days) { day in
                DayRow(day: day)
                    .inkListRow(columnSelected: selection == day.id)
                    .tag(day.id)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .inkColumnListFocus()
    }
}

extension MacDayList where Top == EmptyView {
    init(days: [DayOverview], selection: Binding<String?>) {
        self.init(days: days, selection: selection) { EmptyView() }
    }
}
