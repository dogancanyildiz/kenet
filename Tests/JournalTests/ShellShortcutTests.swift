import SwiftUI
import Testing

@testable import Journal

@MainActor
struct ShellShortcutTests {
    @Test func tabShortcutSelectsTodayAndClearsTheHistoricalDay() {
        let navigation = ShellNavigationState()
        navigation.selectedTab = .tasks
        navigation.selectedDay = "2026-10-01"

        navigation.goToToday(shell: .tabs)

        #expect(navigation.selectedTab == .today)
        #expect(navigation.section == .today)
        #expect(navigation.selectedDay == nil)
    }

    @Test func splitShortcutSelectsTodayAndClearsTheHistoricalDay() {
        let navigation = ShellNavigationState()
        navigation.section = .days
        navigation.selectedDay = "2026-10-01"

        navigation.goToToday(shell: .split)

        #expect(navigation.section == .today)
        #expect(navigation.selectedTab == .today)
        #expect(navigation.selectedDay == nil)
    }

    /// Today may already be selected while its historical-day selection is still retained.
    @Test(arguments: [ShellKind.tabs, .split])
    func todayShortcutClearsTheDayEvenWhenTodayIsSelected(_ shell: ShellKind) {
        let navigation = ShellNavigationState()
        navigation.selectedDay = "2026-10-01"

        navigation.goToToday(shell: shell)
        navigation.goToToday(shell: shell)

        #expect(navigation.section == .today)
        #expect(navigation.selectedTab == .today)
        #expect(navigation.selectedDay == nil)
    }
}
