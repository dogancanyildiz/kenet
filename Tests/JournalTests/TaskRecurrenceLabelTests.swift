import Foundation
import Testing
import VaultFormat

@testable import Journal

struct TaskRecurrenceLabelTests {
    private let turkish = Locale(identifier: "tr_TR")
    private let english = Locale(identifier: "en_US")

    @Test func singularIntervalMatchesBareEveryLabel() {
        #expect(
            TaskRecurrence.intervalLabel(count: 1, unit: .week, locale: turkish)
                == String(localized: "Her hafta", locale: turkish))
        #expect(
            TaskRecurrence.intervalLabel(count: 1, unit: .day, locale: turkish)
                == String(localized: "Her gün", locale: turkish))
        #expect(
            TaskRecurrence.intervalLabel(count: 1, unit: .month, locale: turkish)
                == String(localized: "Her ay", locale: turkish))
        #expect(
            TaskRecurrence.intervalLabel(count: 1, unit: .year, locale: turkish)
                == String(localized: "Her yıl", locale: turkish))
    }

    @Test func pluralIntervalKeepsCount() {
        let week = TaskRecurrence.intervalLabel(count: 2, unit: .week, locale: turkish)
        #expect(week == String(localized: "Her \(2) hafta", locale: turkish))
        #expect(week != String(localized: "Her hafta", locale: turkish))
        #expect(week.contains("2"))
    }

    @Test func englishSingularOmitsNumber() {
        #expect(
            TaskRecurrence.intervalLabel(count: 1, unit: .week, locale: english)
                == String(localized: "Her hafta", locale: english))
        #expect(
            TaskRecurrence.intervalLabel(count: 2, unit: .week, locale: english)
                == String(localized: "Her \(2) hafta", locale: english))
        #expect(
            TaskRecurrence.intervalLabel(count: 1, unit: .week, locale: english)
                != TaskRecurrence.intervalLabel(count: 2, unit: .week, locale: english))
    }
}
