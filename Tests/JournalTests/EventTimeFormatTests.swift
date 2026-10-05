import Foundation
import Testing
import VaultFormat

@testable import Journal

struct EventTimeFormatTests {
    private var sampleTime: EventTime {
        RawDocument(bytes: Array("## Events\n- 08:15 sample".utf8)).bodyLines.events.first!.time!
    }

    private func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test(arguments: [
        "UTC", "Europe/Istanbul", "America/Los_Angeles", "Asia/Kolkata",
    ])
    func vaultClockUnaffectedByDisplayTimeZone(_ identifier: String) throws {
        let time = sampleTime
        let zone = try #require(TimeZone(identifier: identifier))
        let locale = Locale(identifier: "tr_TR")
        #expect(EventTimeFormat.string(for: time, locale: locale) == "08:15")
        #expect(DayEventView.formattedEventTime(time, locale: locale) == "08:15")
        let day = try #require(CalendarDate("2026-09-20"))
        let instant = LocalDay.instant(for: day, time: time, timeZone: .gmt)
        let style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: zone)
        let viaInstant = instant.formatted(style)
        if zone.secondsFromGMT() != 0 {
            #expect(viaInstant != EventTimeFormat.string(for: time, locale: locale))
        } else {
            #expect(normalized(viaInstant).hasPrefix("8:15") || normalized(viaInstant).hasPrefix("08:15"))
        }
    }

    @Test func respectsLocaleHourCycle() throws {
        let time = sampleTime
        let turkish = Locale(identifier: "tr_TR")
        let english = Locale(identifier: "en_US")
        #expect(
            normalized(EventTimeFormat.string(for: time, locale: turkish)).hasPrefix("08:15")
                || normalized(EventTimeFormat.string(for: time, locale: turkish)).hasPrefix("8:15"))
        #expect(normalized(EventTimeFormat.string(for: time, locale: english)) == "8:15 AM")
    }

    @Test func formattingAbsoluteInstantInDeviceTimeZoneShiftsDisplay() throws {
        let time = sampleTime
        let day = try #require(CalendarDate("2026-09-20"))
        let istanbul = try #require(TimeZone(identifier: "Europe/Istanbul"))
        let instant = LocalDay.instant(for: day, time: time, timeZone: .gmt)
        let style = Date.FormatStyle(
            date: .omitted, time: .shortened, locale: Locale(identifier: "en_US"), timeZone: istanbul)
        let shifted = normalized(instant.formatted(style))
        #expect(shifted == "11:15 AM")
        let vaultClock = normalized(EventTimeFormat.string(for: time, locale: Locale(identifier: "en_US")))
        #expect(vaultClock == "8:15 AM")
        #expect(shifted != vaultClock)
    }
}
