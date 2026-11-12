#if DEBUG
    import Foundation

    /// A calendar in memory: UI tests (`JOURNAL_UITEST_CALENDAR=memory`) and unit tests use it in
    /// place of EventKit. It models what the writes depend on: repeating series with their
    /// occurrences, "this event" and "this and following" spans, read-only events, and it finds the
    /// picked occurrence with the same `CalendarWritePlan` rules as the EventKit source.
    @MainActor final class InMemoryCalendarSource: CalendarEventSource {
        var authorization: CalendarAuthorization
        var onChange: (@MainActor @Sendable () -> Void)?
        let calendars: [CalendarTarget]
        /// Writes and deletes, in order: what reached the calendar.
        private(set) var writeCount = 0
        private var series: [Series] = []
        private var nextID = 1

        /// One stored event: a single event or a repeating series.
        private struct Series {
            var event: CalendarEvent
            /// Original starts of deleted occurrences.
            var removed: Set<Date> = []
            /// Occurrences changed on their own ("Yalnız bu etkinlik"), by original start.
            var detached: [Date: CalendarEvent] = [:]
        }

        init(
            authorization: CalendarAuthorization = .fullAccess, events: [CalendarEvent] = [],
            calendars: [CalendarTarget] = InMemoryCalendarSource.sampleCalendars
        ) {
            self.authorization = authorization
            self.calendars = calendars
            series = events.map { Series(event: $0) }
        }

        /// Today's fictional events for the screen tour: a morning meeting, a lunch, an evening run.
        static func sampleEvents(on day: Date, calendar: Calendar = .current) -> [CalendarEvent] {
            let items: [(String, Int, Int, Int, Int, CalendarTarget)] = [
                ("Ürün toplantısı", 10, 0, 11, 0, sampleCalendars[1]),
                ("Öğle yemeği", 12, 30, 13, 30, sampleCalendars[0]),
                ("Akşam koşusu", 19, 0, 20, 0, sampleCalendars[0]),
            ]
            return items.enumerated().compactMap { index, item in
                guard
                    let start = calendar.date(bySettingHour: item.1, minute: item.2, second: 0, of: day),
                    let end = calendar.date(bySettingHour: item.3, minute: item.4, second: 0, of: day)
                else { return nil }
                return CalendarEvent(
                    id: "sample-\(index)", title: item.0, start: start, end: end, isAllDay: false,
                    color: item.5.color, eventIdentifier: "sample-\(index)", calendarID: item.5.id,
                    calendarTitle: item.5.title, isEditable: true)
            }
        }

        static let sampleCalendars = [
            CalendarTarget(
                id: "home", title: "Ev", color: CalendarEventColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)),
            CalendarTarget(
                id: "work", title: "İş", color: CalendarEventColor(red: 0.9, green: 0.4, blue: 0.2, alpha: 1)),
        ]

        /// Every stored series' first event, for assertions.
        var stored: [CalendarEvent] { series.map(\.event) }

        func requestFullAccess() async throws -> Bool {
            authorization = .fullAccess
            return true
        }

        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] {
            expand(from: start, to: end).map(\.event)
        }

        func writableCalendars() async throws -> [CalendarTarget] { calendars }
        func systemDefaultCalendarID() async -> String? { calendars.first?.id }

        func save(_ draft: CalendarEventDraft, editing: CalendarEvent?, span: CalendarEditSpan) async throws {
            let changes = CalendarWritePlan.changes(draft: draft, original: editing)
            guard let editing else {
                let identifier = newIdentifier()
                let target = try calendar(for: changes.calendarID, current: nil)
                var event = CalendarEvent(
                    id: identifier, title: draft.title, start: draft.start, end: draft.end,
                    isAllDay: draft.isAllDay, color: target.color, eventIdentifier: identifier,
                    calendarID: target.id, calendarTitle: target.title, isEditable: true)
                event = Self.apply(rule: changes.rule, to: event)
                series.append(Series(event: event))
                return finish()
            }
            let (index, occurrence) = try find(editing)
            if changes.isEmpty { return }
            var item = series[index]
            let isRecurring = item.event.recurrence != .none
            let original = occurrence.occurrenceDate ?? occurrence.start
            if !isRecurring {
                item.event = try apply(changes, to: item.event)
            } else if span == .thisEvent {
                guard changes.calendarID == nil, changes.rule == nil else { throw CalendarWriteError.unsupported }
                item.detached[original] = try apply(changes, to: occurrence)
            } else if original == item.event.start {
                item.event = try apply(changes, to: item.event)
                item.detached = [:]
            } else {
                // "Bu ve sonrakiler" from the middle: the old series stops before this occurrence and
                // a new one carries the change on, as EventKit splits it.
                var rest = try apply(changes, to: occurrence)
                let identifier = newIdentifier()
                rest = Self.with(rest, identifier: identifier, occurrenceDate: nil)
                item.event = Self.ending(item.event, before: original)
                series.append(Series(event: rest))
            }
            series[index] = item
            finish()
        }

        func delete(_ event: CalendarEvent, span: CalendarEditSpan) async throws {
            let (index, occurrence) = try find(event)
            let original = occurrence.occurrenceDate ?? occurrence.start
            if series[index].event.recurrence == .none
                || (span == .futureEvents && original == series[index].event.start)
            {
                series.remove(at: index)
            } else if span == .thisEvent {
                series[index].removed.insert(original)
                series[index].detached[original] = nil
            } else {
                series[index].event = Self.ending(series[index].event, before: original)
            }
            finish()
        }

        // MARK: - Finding

        private func find(_ target: CalendarEvent) throws -> (Int, CalendarEvent) {
            let around = expand(from: target.start.addingTimeInterval(-86400), to: target.end.addingTimeInterval(86400))
            let fallbackIndex = series.firstIndex { $0.event.eventIdentifier == target.eventIdentifier }
            let fallback = fallbackIndex.map { Self.candidate(of: series[$0].event) }
            let pick = CalendarWritePlan.pickOccurrence(
                target, in: around.map { Self.candidate(of: $0.event) }, fallback: fallback)
            let found: (Int, CalendarEvent)
            switch pick {
            case .candidate(let at): found = (around[at].series, around[at].event)
            case .fallback:
                guard let fallbackIndex else { throw CalendarWriteError.notFound }
                found = (fallbackIndex, series[fallbackIndex].event)
            case .notFound: throw CalendarWriteError.notFound
            }
            guard found.1.isEditable else { throw CalendarWriteError.readOnly }
            return found
        }

        private static func candidate(of event: CalendarEvent) -> OccurrenceCandidate {
            OccurrenceCandidate(
                identifier: event.eventIdentifier, start: event.start, occurrenceDate: event.occurrenceDate,
                isRecurring: event.recurrence != .none)
        }

        /// Occurrences overlapping the range, with the index of their series.
        private func expand(from start: Date, to end: Date) -> [(series: Int, event: CalendarEvent)] {
            var result: [(Int, CalendarEvent)] = []
            for (index, item) in series.enumerated() {
                for occurrence in Self.occurrences(of: item, before: end) {
                    let event = item.detached[occurrence.start] ?? occurrence
                    if event.start < end, event.end > start || event.start >= start {
                        result.append((index, event))
                    }
                }
            }
            return result
        }

        private static func occurrences(of item: Series, before end: Date) -> [CalendarEvent] {
            let base = item.event
            let component: Calendar.Component
            switch base.recurrence {
            case .none, .custom:
                return [with(base, identifier: base.eventIdentifier ?? base.id, occurrenceDate: base.start)]
            case .daily: component = .day
            case .weekly: component = .weekOfYear
            case .monthly: component = .month
            case .yearly, .lastDayOfFebruary: component = .year
            }
            let calendar = Calendar(identifier: .gregorian)
            let length = base.end.timeIntervalSince(base.start)
            var result: [CalendarEvent] = []
            var step = 0
            while step < 2000, let begin = occurrenceStart(base, step: step, component: component, calendar: calendar),
                begin < end
            {
                step += 1
                if let last = base.recurrenceEnd, begin > last { break }
                if item.removed.contains(begin) { continue }
                result.append(
                    CalendarEvent(
                        id: (base.eventIdentifier ?? base.id) + ":" + String(begin.timeIntervalSince1970),
                        title: base.title, start: begin, end: begin.addingTimeInterval(length), isAllDay: base.isAllDay,
                        color: base.color, attendees: base.attendees, eventIdentifier: base.eventIdentifier,
                        calendarID: base.calendarID, calendarTitle: base.calendarTitle, recurrence: base.recurrence,
                        recurrenceEnd: base.recurrenceEnd, occurrenceDate: begin, isEditable: base.isEditable,
                        isFromBirthdayCalendar: base.isFromBirthdayCalendar))
            }
            return result
        }

        /// The `step`th occurrence. February's last day is 1 March minus a day, at the series' time.
        private static func occurrenceStart(
            _ base: CalendarEvent, step: Int, component: Calendar.Component, calendar: Calendar
        ) -> Date? {
            guard base.recurrence == .lastDayOfFebruary else {
                return calendar.date(byAdding: component, value: step, to: base.start)
            }
            let time = base.start.timeIntervalSince(calendar.startOfDay(for: base.start))
            let year = calendar.component(.year, from: base.start) + step
            guard let march = calendar.date(from: DateComponents(year: year, month: 3, day: 1)),
                let last = calendar.date(byAdding: .day, value: -1, to: march)
            else { return nil }
            return last.addingTimeInterval(time)
        }

        // MARK: - Changing

        private func calendar(for requested: String?, current: String?) throws -> CalendarTarget {
            let id = CalendarWritePlan.calendarID(
                requested: requested, current: current, writable: Set(calendars.map(\.id)),
                systemDefault: calendars.first?.id)
            guard let target = calendars.first(where: { $0.id == id }) else { throw CalendarWriteError.noCalendar }
            return target
        }

        private func apply(_ changes: CalendarWritePlan.Changes, to event: CalendarEvent) throws -> CalendarEvent {
            let target =
                changes.calendarID == nil
                ? nil : try calendar(for: changes.calendarID, current: event.calendarID)
            let applied = CalendarEvent(
                id: event.id, title: changes.title ?? event.title, start: changes.start ?? event.start,
                end: changes.end ?? event.end, isAllDay: changes.isAllDay ?? event.isAllDay,
                color: target?.color ?? event.color, attendees: event.attendees, eventIdentifier: event.eventIdentifier,
                calendarID: target?.id ?? event.calendarID, calendarTitle: target?.title ?? event.calendarTitle,
                recurrence: event.recurrence, recurrenceEnd: event.recurrenceEnd, occurrenceDate: event.occurrenceDate,
                isEditable: event.isEditable, isFromBirthdayCalendar: event.isFromBirthdayCalendar)
            return Self.apply(rule: changes.rule, to: applied)
        }

        private static func apply(rule: CalendarWritePlan.RuleChange?, to event: CalendarEvent) -> CalendarEvent {
            guard let rule else { return event }
            var copy = event
            switch rule {
            case .remove:
                copy.recurrence = .none
                copy.recurrenceEnd = nil
            case .set(let recurrence, let end):
                copy.recurrence = recurrence
                copy.recurrenceEnd = end
            }
            return copy
        }

        private static func ending(_ event: CalendarEvent, before occurrence: Date) -> CalendarEvent {
            var copy = event
            copy.recurrenceEnd = occurrence.addingTimeInterval(-1)
            return copy
        }

        private static func with(_ event: CalendarEvent, identifier: String, occurrenceDate: Date?) -> CalendarEvent {
            var copy = CalendarEvent(
                id: identifier, title: event.title, start: event.start, end: event.end, isAllDay: event.isAllDay,
                color: event.color, attendees: event.attendees, eventIdentifier: identifier,
                calendarID: event.calendarID, calendarTitle: event.calendarTitle, recurrence: event.recurrence,
                recurrenceEnd: event.recurrenceEnd, occurrenceDate: occurrenceDate, isEditable: event.isEditable,
                isFromBirthdayCalendar: event.isFromBirthdayCalendar)
            copy.occurrenceDate = occurrenceDate
            return copy
        }

        private func newIdentifier() -> String {
            defer { nextID += 1 }
            return "memory-\(nextID)"
        }

        private func finish() {
            writeCount += 1
            onChange?()
        }
    }
#endif
