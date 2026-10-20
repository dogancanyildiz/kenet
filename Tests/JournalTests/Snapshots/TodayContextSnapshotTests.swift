#if os(iOS)
    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// Bugün bağlam bölümleri: bu gün geçmişte (açık, koyu, AX3),
    /// önemli tarihler (açık, koyu, AX3), bağlananlar (açık, koyu, AX3).
    enum TodayContextSnapshotCase: String, CaseIterable, Sendable {
        case todayOnThisDayLight
        case todayOnThisDayDark
        case todayOnThisDayAX3
        case todayImportantDatesLight
        case todayImportantDatesDark
        case todayImportantDatesAX3
        case todayBacklinksLight
        case todayBacklinksDark
        case todayBacklinksAX3

        var colorScheme: SnapshotColorScheme {
            switch self {
            case .todayOnThisDayDark, .todayImportantDatesDark, .todayBacklinksDark: .dark
            default: .light
            }
        }

        var dynamicType: SnapshotDynamicType {
            switch self {
            case .todayOnThisDayAX3, .todayImportantDatesAX3, .todayBacklinksAX3: .accessibility3
            default: .medium
            }
        }

        var usesOnThisDay: Bool {
            self == .todayOnThisDayLight || self == .todayOnThisDayDark || self == .todayOnThisDayAX3
        }

        var usesImportantDates: Bool {
            self == .todayImportantDatesLight || self == .todayImportantDatesDark
                || self == .todayImportantDatesAX3
        }

        var usesBacklinks: Bool {
            self == .todayBacklinksLight || self == .todayBacklinksDark || self == .todayBacklinksAX3
        }
    }

    @MainActor @Suite("Today context snapshots")
    struct TodayContextSnapshotTests {
        /// Tab bar + home indicator so the quick-entry shelf matches a real phone bottom inset.
        private static let tabBarHeight: CGFloat = 84

        @Test(arguments: TodayContextSnapshotCase.allCases)
        func today(_ snapshotCase: TodayContextSnapshotCase) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            if snapshotCase.usesOnThisDay {
                try Self.writeEarlierYears(in: context.root)
            }
            if snapshotCase.usesImportantDates {
                try Self.writeImportantDates(in: context.root)
            }
            if snapshotCase.usesBacklinks {
                try Self.writeBacklinks(in: context.root)
            }
            if snapshotCase == .todayOnThisDayAX3 || snapshotCase == .todayImportantDatesAX3
                || snapshotCase == .todayBacklinksAX3
            {
                // At AX3 the full sample day pushes the line off even the tall canvas.
                try Self.stripOpenTasksDueBeforeSnapshotDay(in: context.root)
                try FileManager.default.removeItem(at: context.root.appendingPathComponent("goals"))
            }
            await context.start()
            #expect(context.store.lastUpdated != nil)

            let defaults = context.defaults.defaults
            let notifications = NotificationService(
                center: FakeNotificationCenter(), defaults: defaults,
                now: { snapshotNow },
                timeZone: { snapshotTimeZone })
            let calendar = CalendarService(source: SnapshotCalendarSource())
            let location = LocationService(source: FakeLocationSource(), defaults: defaults)

            // The goal strip loads in a `.task`; without this the reference can catch its spinner.
            let goalsReady = ContextReadyBox()
            let contextReady = ContextReadyBox()
            let backlinksReady = ContextReadyBox()
            let store = context.store
            // The line sits below the events; the tall canvas keeps it in view at every type size.
            // AX3 plus the overflow line needs more than the on-this-day canvas.
            let size: CGSize =
                if snapshotCase == .todayImportantDatesAX3 {
                    CGSize(width: 390, height: 2200)
                } else {
                    CGSize(width: 390, height: 1600)
                }
            let root = NavigationStack {
                DayView(store: store, date: snapshotDay, isToday: true)
            }
            .environment(notifications)
            .environment(calendar)
            .environment(location)
            .environment(\.locale, snapshotLocale)
            .environment(\.calendar, makeSnapshotCalendar())
            .environment(\.timeZone, snapshotTimeZone)
            .environment(\.clockNow, { snapshotNow })
            .environment(\.openSearch, {})
            // Without an action the masthead hides its Settings button.
            .environment(\.openSettings, {})
            .onPreferenceChange(GoalsStripReadyKey.self) { goalsReady.isReady = $0 }
            .onPreferenceChange(DayContextReadyKey.self) { contextReady.isReady = $0 }
            .onPreferenceChange(DayBacklinksReadyKey.self) { backlinksReady.isReady = $0 }
            let needsContext = snapshotCase.usesOnThisDay || snapshotCase.usesImportantDates
            let needsBacklinks = snapshotCase.usesBacklinks
            await SnapshotHost.assertView(
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: false,
                named: snapshotCase.rawValue,
                store: store,
                size: size,
                bottomSafeArea: Self.tabBarHeight,
                isReady: {
                    goalsReady.isReady
                        && (!needsContext || contextReady.isReady)
                        && (!needsBacklinks || backlinksReady.isReady)
                },
                testName: "today",
                file: #filePath,
                line: #line,
                content: { root }
            )
        }

        /// Four birthdays inside 20–27 September so Today shows three lines and one "more" line.
        private static func writeImportantDates(in root: URL) throws {
            let replacements = [
                "people/Deniz Arıkan.md": ("doğum günü: 1990-05-14", "doğum günü: 1990-09-20"),
                "people/Selin Korkmaz.md": ("doğum günü: 1992-11-23", "doğum günü: 1992-09-21"),
                "people/Ece Yalın.md": ("doğum günü: 1994-03-30", "doğum günü: 1994-09-23"),
                "people/Baran Tunç.md": ("doğum günü: 1988-08-04", "doğum günü: 1988-09-27"),
            ]
            for (path, pair) in replacements {
                let file = root.appendingPathComponent(path)
                var text = try String(contentsOf: file, encoding: .utf8)
                guard let range = text.range(of: pair.0) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                text.replaceSubrange(range, with: pair.1)
                try text.write(to: file, atomically: true, encoding: .utf8)
            }
        }

        /// Two linked earlier years (three people, two places in the nearest) and an unlinked one.
        private static func writeEarlierYears(in root: URL) throws {
            let days = [
                "2025-09-20": [
                    "- 10:00 [[Deniz Arıkan]] ile [[Çınaraltı Kafe]]'de kahve",
                    "- 13:00 [[Selin Korkmaz]] ile öğle yemeği",
                    "- 16:00 [[Baran Tunç]] ile [[Liman Ofis]]'te toplantı",
                ],
                "2024-09-20": ["- 20:00 [[Ece Yalın]] ile [[Ev]]'de akşam yemeği"],
                "2023-09-20": ["- 09:00 [[Okuma Listesi]] gözden geçirildi"],
            ]
            for (date, events) in days {
                let body =
                    "---\ntype: journal\ndate: \(date)\n---\n\n## Tasks\n\n## Events\n"
                    + events.joined(separator: "\n") + "\n\n## Journal\n"
                try body.write(
                    to: root.appendingPathComponent("journal/\(date).md"), atomically: true,
                    encoding: .utf8)
            }
        }

        /// Adds backlinks to snapshotDay from a note, person, and another day.
        private static func writeBacklinks(in root: URL) throws {
            let note = root.appendingPathComponent("notes/Proje Fikirleri.md")
            var noteText = try String(contentsOf: note, encoding: .utf8)
            noteText += "\n[[2026-09-20]] için sunum taslağı hazırlandı.\n"
            try noteText.write(to: note, atomically: true, encoding: .utf8)

            let person = root.appendingPathComponent("people/Deniz Arıkan.md")
            var personText = try String(contentsOf: person, encoding: .utf8)
            personText += "\n[[2026-09-20]] görüşmesi yapıldı.\n"
            try personText.write(to: person, atomically: true, encoding: .utf8)

            let otherDay = root.appendingPathComponent("journal/2026-09-19.md")
            var otherDayText = try String(contentsOf: otherDay, encoding: .utf8)
            let event = "- 18:00 Yarın için [[2026-09-20]] notu bırakıldı\n"
            if let range = otherDayText.range(of: "## Events\n") {
                otherDayText.insert(contentsOf: event, at: range.upperBound)
            } else {
                otherDayText += "\n" + event
            }
            try otherDayText.write(to: otherDay, atomically: true, encoding: .utf8)
        }

        private static func stripOpenTasksDueBeforeSnapshotDay(in root: URL) throws {
            let journal = root.appendingPathComponent("journal")
            let files = try FileManager.default.contentsOfDirectory(
                at: journal, includingPropertiesForKeys: nil)
            let openTask = try NSRegularExpression(
                pattern: #"^- \[[ /]\] .*(?:📅|🛫) 2026-09-(0[1-9]|1[0-9])\b.*$"#,
                options: .anchorsMatchLines)
            for file in files where file.pathExtension == "md" {
                var text = try String(contentsOf: file, encoding: .utf8)
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                text = openTask.stringByReplacingMatches(
                    in: text, options: [], range: range, withTemplate: "")
                try text.write(to: file, atomically: true, encoding: .utf8)
            }
        }
    }

    @MainActor private final class ContextReadyBox {
        var isReady = false
    }
#endif
