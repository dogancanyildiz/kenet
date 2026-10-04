import Foundation

enum PeopleInsightsPreference {
    static let key = "peopleInsights.thresholdDays"
    static let defaultDays = 30
    static func normalized(_ days: Int) -> Int { min(365, max(1, days)) }
    static func threshold(in defaults: UserDefaults) -> Int {
        guard defaults.object(forKey: key) != nil else { return defaultDays }
        return normalized(defaults.integer(forKey: key))
    }
}
