import Foundation
import VaultFormat
import VaultIndex

@testable import Journal

let notificationUTC = TimeZone(secondsFromGMT: 0)!
func notificationDate(_ day: String = "2026-09-27", hour: Int = 8, minute: Int = 0, zone: TimeZone = notificationUTC)
    -> Date
{
    let value = CalendarDate(day)!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar.date(
        from: DateComponents(year: value.year, month: value.month, day: value.day, hour: hour, minute: minute))!
}
func notificationSample() throws -> VaultReadModel {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/vaults/sample")
    let index = try VaultIndex()
    try index.rebuild(vaultRoot: root)
    return VaultReadModel(snapshot: try index.snapshot(), today: CalendarDate("2026-09-27")!)
}

func notificationTasks(_ text: String) throws -> [TaskRow] {
    let root = try testDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("journal")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(("---\ntype: journal\ndate: 2026-09-27\n---\n\n## Tasks\n" + text).utf8).write(
        to: directory.appendingPathComponent("2026-09-27.md"))
    let index = try VaultIndex()
    try index.rebuild(vaultRoot: root)
    return VaultReadModel(snapshot: try index.snapshot()).tasks
}

@MainActor
final class FakeNotificationCenter: NotificationScheduling {
    enum Failure: Error { case unavailable }
    var status = NotificationAuthorization.authorized
    var permissionResult = NotificationAuthorization.authorized
    var permissionRequests = 0
    var activationCount = 0
    var authorizationReads = 0
    var values: [String: NotificationRequest] = [:]
    var additions: [NotificationRequest] = []
    var removals: [[String]] = []
    var operations: [String] = []
    var failPermission = false
    var failIDs: Set<String> = []
    var pauseNextAdd = false
    var pausedAdd: CheckedContinuation<Void, Never>?
    var concurrentAdds = 0
    var maxConcurrentAdds = 0
    var response: (@MainActor @Sendable (NotificationDestination) -> Void)?

    func authorization() async -> NotificationAuthorization {
        authorizationReads += 1
        return status
    }
    func requestAuthorization() async throws -> Bool {
        permissionRequests += 1
        if failPermission { throw Failure.unavailable }
        status = permissionResult
        return status.canSchedule
    }
    func pendingRequests() async -> [NotificationRequest] { Array(values.values) }
    func add(_ request: NotificationRequest) async throws {
        concurrentAdds += 1
        maxConcurrentAdds = max(maxConcurrentAdds, concurrentAdds)
        defer { concurrentAdds -= 1 }
        if pauseNextAdd {
            pauseNextAdd = false
            await withCheckedContinuation { pausedAdd = $0 }
        }
        if failIDs.contains(request.id) { throw Failure.unavailable }
        operations.append("add:" + request.id)
        additions.append(request)
        values[request.id] = request
    }
    func remove(identifiers: [String]) async {
        operations.append("remove")
        removals.append(identifiers)
        for identifier in identifiers { values.removeValue(forKey: identifier) }
    }
    var deliveredRemovals = 0
    func removeAllDeliveredNotifications() async {
        operations.append("removeDelivered")
        deliveredRemovals += 1
    }
    func activate(response: @escaping @MainActor @Sendable (NotificationDestination) -> Void) {
        activationCount += 1
        self.response = response
    }
}
