import CoreGraphics
import EventKit
import Foundation

@MainActor final class EventKitCalendarSource: CalendarEventSource {
    var onChange: (@MainActor @Sendable () -> Void)?
    private let reader = CalendarEventReader()
    private var observation: CalendarChangeObservation?

    init() {
        observation = CalendarChangeObservation { [weak self] in self?.onChange?() }
    }

    var authorization: CalendarAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .fullAccess: .fullAccess
        case .denied: .denied
        case .restricted: .restricted
        case .writeOnly: .writeOnly
        @unknown default: .restricted
        }
    }

    func requestFullAccess() async throws -> Bool { try await reader.requestFullAccess() }
    func events(from start: Date, to end: Date) async throws -> [CalendarEvent] {
        await reader.events(from: start, to: end)
    }
}

/// EventKit objects stay on one actor; potentially blocking queries never run on the UI thread.
private actor CalendarEventReader {
    private lazy var store = EKEventStore()

    func requestFullAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestFullAccessToEvents { granted, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: granted) }
            }
        }
    }

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { event in
            let color = event.calendar.cgColor?.converted(
                to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)
            let components = color?.components ?? [0.2, 0.5, 0.9, 1]
            return CalendarEvent(
                id: (event.eventIdentifier ?? event.calendarItemIdentifier) + ":"
                    + String(event.startDate.timeIntervalSince1970),
                title: event.title ?? "", start: event.startDate, end: event.endDate,
                isAllDay: event.isAllDay,
                color: CalendarEventColor(
                    red: components[0], green: components[1], blue: components[2], alpha: components[3]))
        }
    }
}

/// NotificationCenter permits removal from any thread. The callback always hops to MainActor.
private final class CalendarChangeObservation: @unchecked Sendable {
    private let token: any NSObjectProtocol
    init(action: @escaping @MainActor @Sendable () -> Void) {
        token = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: nil) { _ in
            Task { @MainActor in action() }
        }
    }
    deinit { NotificationCenter.default.removeObserver(token) }
}
