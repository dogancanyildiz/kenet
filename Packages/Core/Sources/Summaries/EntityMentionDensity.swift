import Foundation
import VaultFormat

/// Monthly mention density for the 12-month calendar bar chart.
public struct EntityMonthlyDensity: Sendable, Equatable, Codable {
    public let month: CalendarDate
    public let count: Int
    public let isCurrentMonth: Bool

    public init(month: CalendarDate, count: Int, isCurrentMonth: Bool) {
        self.month = month
        self.count = count
        self.isCurrentMonth = isCurrentMonth
    }

    enum CodingKeys: String, CodingKey {
        case month, count, isCurrentMonth
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let monthString = try container.decode(String.self, forKey: .month)
        guard let month = CalendarDate(monthString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .month, in: container, debugDescription: "Invalid CalendarDate: \(monthString)")
        }
        self.month = month
        self.count = try container.decode(Int.self, forKey: .count)
        self.isCurrentMonth = try container.decode(Bool.self, forKey: .isCurrentMonth)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(month.description, forKey: .month)
        try container.encode(count, forKey: .count)
        try container.encode(isCurrentMonth, forKey: .isCurrentMonth)
    }
}

/// A single day entry in the 90-day activity strip.
public struct EntityRecentDayDensity: Sendable, Equatable, Codable {
    public let date: CalendarDate
    public let isMentioned: Bool
    public let isToday: Bool

    public init(date: CalendarDate, isMentioned: Bool, isToday: Bool) {
        self.date = date
        self.isMentioned = isMentioned
        self.isToday = isToday
    }

    enum CodingKeys: String, CodingKey {
        case date, isMentioned, isToday
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dateString = try container.decode(String.self, forKey: .date)
        guard let date = CalendarDate(dateString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .date, in: container, debugDescription: "Invalid CalendarDate: \(dateString)")
        }
        self.date = date
        self.isMentioned = try container.decode(Bool.self, forKey: .isMentioned)
        self.isToday = try container.decode(Bool.self, forKey: .isToday)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date.description, forKey: .date)
        try container.encode(isMentioned, forKey: .isMentioned)
        try container.encode(isToday, forKey: .isToday)
    }
}

/// Density calculation for entity mentions over the last 12 calendar months and recent 90 days.
public struct EntityMentionDensity: Sendable, Equatable, Codable {
    public let months: [EntityMonthlyDensity]
    public let totalYearDays: Int
    public let busiestMonth: CalendarDate?
    public let busiestMonthCount: Int
    public let recentDays: [EntityRecentDayDensity]
    public let recentDayCount: Int
    public let averageInterval: Double?
    public let hasHistory: Bool

    public init(
        months: [EntityMonthlyDensity],
        totalYearDays: Int,
        busiestMonth: CalendarDate?,
        busiestMonthCount: Int,
        recentDays: [EntityRecentDayDensity],
        recentDayCount: Int,
        averageInterval: Double?,
        hasHistory: Bool
    ) {
        self.months = months
        self.totalYearDays = totalYearDays
        self.busiestMonth = busiestMonth
        self.busiestMonthCount = busiestMonthCount
        self.recentDays = recentDays
        self.recentDayCount = recentDayCount
        self.averageInterval = averageInterval
        self.hasHistory = hasHistory
    }

    enum CodingKeys: String, CodingKey {
        case months, totalYearDays, busiestMonth, busiestMonthCount, recentDays, recentDayCount, averageInterval,
            hasHistory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.months = try container.decode([EntityMonthlyDensity].self, forKey: .months)
        self.totalYearDays = try container.decode(Int.self, forKey: .totalYearDays)
        if let busiest = try container.decodeIfPresent(String.self, forKey: .busiestMonth) {
            guard let month = CalendarDate(busiest) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .busiestMonth, in: container, debugDescription: "Invalid CalendarDate: \(busiest)")
            }
            self.busiestMonth = month
        } else {
            self.busiestMonth = nil
        }
        self.busiestMonthCount = try container.decode(Int.self, forKey: .busiestMonthCount)
        self.recentDays = try container.decode([EntityRecentDayDensity].self, forKey: .recentDays)
        self.recentDayCount = try container.decode(Int.self, forKey: .recentDayCount)
        self.averageInterval = try container.decodeIfPresent(Double.self, forKey: .averageInterval)
        self.hasHistory = try container.decode(Bool.self, forKey: .hasHistory)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(months, forKey: .months)
        try container.encode(totalYearDays, forKey: .totalYearDays)
        try container.encode(busiestMonth?.description, forKey: .busiestMonth)
        try container.encode(busiestMonthCount, forKey: .busiestMonthCount)
        try container.encode(recentDays, forKey: .recentDays)
        try container.encode(recentDayCount, forKey: .recentDayCount)
        try container.encode(averageInterval, forKey: .averageInterval)
        try container.encode(hasHistory, forKey: .hasHistory)
    }

    /// Computes density for the entity's recorded timeline days as of `today`.
    /// Duplicate mentions on the same day count as a single day.
    /// Days in the future (`> today`) are excluded.
    public static func compute(days: [CalendarDate], today: CalendarDate) -> EntityMentionDensity {
        let historyDates = Set(days.filter { $0 <= today })
        let hasHistory = !historyDates.isEmpty

        let todayMonthStart = today.startOfMonth
        var months: [EntityMonthlyDensity] = []
        months.reserveCapacity(12)
        var totalYearDays = 0
        var busiestMonth: CalendarDate?
        var busiestMonthCount = 0

        for offset in (0..<12).reversed() {
            guard let monthStart = todayMonthStart.addingMonths(-offset) else { continue }
            let monthEnd = monthStart.endOfMonth
            let count = historyDates.filter { $0 >= monthStart && $0 <= min(monthEnd, today) }.count
            totalYearDays += count
            let isCurrent = (offset == 0)

            months.append(
                EntityMonthlyDensity(
                    month: monthStart,
                    count: count,
                    isCurrentMonth: isCurrent
                )
            )

            if count > busiestMonthCount {
                busiestMonthCount = count
                busiestMonth = monthStart
            }
        }

        var recentDays: [EntityRecentDayDensity] = []
        recentDays.reserveCapacity(90)
        for offset in (0..<90).reversed() {
            guard let day = today.addingDays(-offset) else { continue }
            recentDays.append(
                EntityRecentDayDensity(
                    date: day,
                    isMentioned: historyDates.contains(day),
                    isToday: day == today
                )
            )
        }

        let recentMentionDates = historyDates.filter { today.ordinal - $0.ordinal < 90 }.sorted()
        let recentDayCount = recentMentionDates.count
        let averageInterval: Double? =
            recentMentionDates.count > 1
            ? Double(recentMentionDates.last!.ordinal - recentMentionDates.first!.ordinal)
                / Double(recentMentionDates.count - 1)
            : nil

        return EntityMentionDensity(
            months: months,
            totalYearDays: totalYearDays,
            busiestMonth: busiestMonth,
            busiestMonthCount: busiestMonthCount,
            recentDays: recentDays,
            recentDayCount: recentDayCount,
            averageInterval: averageInterval,
            hasHistory: hasHistory
        )
    }
}
