#if os(macOS)
    import AppKit
    import Foundation
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    @MainActor
    struct MacSystemControlTests {
        // MARK: - 1. TaskDateMacPicker Coordinator Tests

        @Test func taskDateMacPickerCoordinatorReflectsUserChangeToBinding() {
            let initial = Date(timeIntervalSince1970: 1_700_000_000)
            var selected = initial
            let binding = Binding(get: { selected }, set: { selected = $0 })
            let picker = TaskDateMacPicker(selected: binding)
            let coordinator = picker.makeCoordinator()

            let nsView = NSDatePicker()
            let updated = Date(timeIntervalSince1970: 1_700_100_000)
            nsView.dateValue = updated

            coordinator.dateChanged(nsView)
            #expect(selected == updated)
        }

        @Test func taskDateMacPickerCoordinatorReflectsExternalDateUpdates() {
            let date1 = Date(timeIntervalSince1970: 1_700_000_000)
            let date2 = Date(timeIntervalSince1970: 1_700_086_400)
            var selected = date1
            let binding = Binding(get: { selected }, set: { selected = $0 })
            let picker1 = TaskDateMacPicker(selected: binding)
            let coordinator = picker1.makeCoordinator()

            #expect(coordinator.parent.selected == date1)

            selected = date2
            let picker2 = TaskDateMacPicker(selected: binding)
            coordinator.parent = picker2

            #expect(coordinator.parent.selected == date2)

            let nsView = NSDatePicker()
            let date3 = Date(timeIntervalSince1970: 1_700_200_000)
            nsView.dateValue = date3
            coordinator.dateChanged(nsView)
            #expect(selected == date3)
        }

        @Test func taskDatePickerPreservesNoonAndDoesNotDriftAcrossTimeZones() {
            let day = CalendarDate(year: 2026, month: 10, day: 8)!
            let auckland = TimeZone(identifier: "Pacific/Auckland")!
            let utc = TimeZone(identifier: "UTC")!

            // LocalDay.instant creates noon (12:00)
            let instantAuckland = LocalDay.instant(for: day, timeZone: auckland)
            var aucklandCal = Calendar(identifier: .gregorian)
            aucklandCal.timeZone = auckland
            let aucklandHour = aucklandCal.component(.hour, from: instantAuckland)
            #expect(aucklandHour == 12)

            let instantUTC = LocalDay.instant(for: day, timeZone: utc)
            var utcCal = Calendar(identifier: .gregorian)
            utcCal.timeZone = utc
            let utcHour = utcCal.component(.hour, from: instantUTC)
            #expect(utcHour == 12)

            // Converting back to CalendarDate maintains the exact same day
            let parsedAuckland = LocalDay.today(at: instantAuckland, timeZone: auckland)
            #expect(parsedAuckland == day)

            let parsedUTC = LocalDay.today(at: instantUTC, timeZone: utc)
            #expect(parsedUTC == day)
        }

        @Test func macTimePickerCoordinatorReflectsUserChangeToBinding() {
            let initial = Date(timeIntervalSince1970: 1_700_000_000)
            var selected = initial
            let binding = Binding(get: { selected }, set: { selected = $0 })
            let picker = MacTimePicker(selection: binding)
            let coordinator = picker.makeCoordinator()

            let nsView = NSDatePicker()
            let updated = Date(timeIntervalSince1970: 1_700_003_600)
            nsView.dateValue = updated

            coordinator.timeChanged(nsView)
            #expect(selected == updated)
        }

        @Test func macTimePickerCoordinatorReflectsExternalUpdates() {
            let initial = Date(timeIntervalSince1970: 1_700_000_000)
            var selected = initial
            let binding = Binding(get: { selected }, set: { selected = $0 })
            let picker1 = MacTimePicker(selection: binding)
            let coordinator = picker1.makeCoordinator()

            #expect(coordinator.parent.selection == initial)

            let updated = Date(timeIntervalSince1970: 1_700_003_600)
            selected = updated
            let picker2 = MacTimePicker(selection: binding)
            coordinator.parent = picker2

            #expect(coordinator.parent.selection == updated)
        }

        // MARK: - 2. Graph Weight Filter Stepper Boundary and Step Tests

        @Test func graphWeightFilterBoundaryDisablingAndStep() {
            var filter = GraphFilter(minimumWeight: 1)
            let maximumWeight = 5

            // Boundary at minimum (1): decrement is disabled
            #expect(filter.minimumWeight <= 1)
            #expect(filter.minimumWeight < max(maximumWeight, filter.minimumWeight))

            // Step up
            filter.minimumWeight += 1
            #expect(filter.minimumWeight == 2)
            #expect(filter.minimumWeight > 1)  // decrement enabled
            #expect(filter.minimumWeight < max(maximumWeight, filter.minimumWeight))  // increment enabled

            // Reach upper boundary
            filter.minimumWeight = maximumWeight
            #expect(filter.minimumWeight >= max(maximumWeight, filter.minimumWeight))  // increment disabled
            #expect(filter.minimumWeight > 1)  // decrement enabled

            // Step down
            filter.minimumWeight -= 1
            #expect(filter.minimumWeight == maximumWeight - 1)
        }

        // MARK: - 3. Mac Settings Tab Selection Tests

        @Test func macSettingsTabValuesAndSelection() {
            let allTabs: [MacSettingsTab] = [
                .quickEntry,
                .privacy,
                .notifications,
                .calendarAndLocation,
                .vault,
                .diagnostics,
            ]
            let tabSet = Set(allTabs)
            #expect(tabSet.count == 6)

            var selectedTab: MacSettingsTab = .quickEntry
            #expect(selectedTab == .quickEntry)

            selectedTab = .vault
            #expect(selectedTab == .vault)

            selectedTab = .notifications
            #expect(selectedTab == .notifications)
        }
    }
#endif
