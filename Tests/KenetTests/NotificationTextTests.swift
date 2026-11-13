import Foundation
import Testing
import UserNotifications
import VaultFormat
import VaultIndex

@testable import Kenet

/// Notification text is resolved when the system delivers, so a planned request must carry a
/// catalog key and arguments, never the text of the language at planning.
@MainActor
struct NotificationTextTests {
    private static let english = PresentationLocalization.bundle(Locale(identifier: "en"))
    private static let turkish = PresentationLocalization.bundle(Locale(identifier: "tr"))

    /// Every text the planner and the people reminder send, with both languages' wording. The
    /// delivery-time formatter fills only `%@`, so no format here may take `%lld` or a plural.
    private static let texts: [(text: NotificationText, tr: String, en: String)] = [
        (.localized("Bugünkü görevler"), "Bugünkü görevler", "Today's tasks"),
        (.localized("1 görev bugün"), "1 görev bugün", "1 task today"),
        (.localized("%@ görev bugün", "3"), "3 görev bugün", "3 tasks today"),
        (
            .localized("Önceki günlerden %@ açık görev.", "10"), "Önceki günlerden 10 açık görev.",
            "10 open tasks from previous days."
        ),
        (.localized("Günlük hedefler"), "Günlük hedefler", "Daily goals"),
        (.localized("Bugün bekleyen hedefler var"), "Bugün bekleyen hedefler var", "There are goals remaining today"),
        (
            .localized("Bugün bekleyen hedefler: %@", "Kitap, Su"), "Bugün bekleyen hedefler: Kitap, Su",
            "Goals remaining today: Kitap, Su"
        ),
        (.localized("Gününden bir an"), "Gününden bir an", "A moment from your day"),
        (
            .localized("Bugünden bir an yazmak ister misin?"), "Bugünden bir an yazmak ister misin?",
            "Would you like to write a moment from today?"
        ),
        (.localized("Görüşme zamanı"), "Görüşme zamanı", "Time for a conversation"),
        (
            .localized("Görüşme zamanı gelen 1 kişi var"), "Görüşme zamanı gelen 1 kişi var",
            "1 person is due for a conversation"
        ),
        (
            .localized("Görüşme zamanı gelen %@ kişi var", "3"), "Görüşme zamanı gelen 3 kişi var",
            "3 people are due for a conversation"
        ),
        (.localized("%@ ve %@", "Ada", "Bora"), "Ada ve Bora", "Ada and Bora"),
        (.localized("%@, %@ ve %@", "Ada", "Bora", "Cem"), "Ada, Bora ve Cem", "Ada, Bora and Cem"),
        (
            .localized("%@, %@, %@ ve 1 kişi daha", "Ada", "Bora", "Cem"), "Ada, Bora, Cem ve 1 kişi daha",
            "Ada, Bora, Cem and 1 more person"
        ),
        (
            .localized("%@, %@, %@ ve %@ kişi daha", "Ada", "Bora", "Cem", "4"), "Ada, Bora, Cem ve 4 kişi daha",
            "Ada, Bora, Cem and 4 more people"
        ),
    ]

    @Test func everyKeyResolvesInBothLanguagesWithObjectArgumentsOnly() throws {
        #expect(Self.english.bundlePath != Self.turkish.bundlePath)
        for item in Self.texts {
            let key = try #require(item.text.key)
            #expect(item.text.resolved(in: Self.turkish) == item.tr, "\(key)")
            #expect(item.text.resolved(in: Self.english) == item.en, "\(key)")
            for bundle in [Self.turkish, Self.english] {
                let format = bundle.localizedString(forKey: key, value: "", table: nil)
                #expect(!format.isEmpty, "\(key)")
                // Only `%@` and `%n$@` remain once those are taken out.
                let rest = format.replacing(/%(\d+\$)?@/, with: "")
                #expect(!rest.contains("%"), "\(key): \(format)")
            }
        }
    }

    /// The system's own resolution of the delivery string agrees with the catalog in the process language.
    @Test func deliveryStringIsALocalizedProxyCarryingKeyAndArguments() throws {
        for item in Self.texts {
            let request = NotificationRequest(
                id: "task-2026-09-27", date: notificationDate(), title: item.text, body: .verbatim("Ada'yı ara"),
                destination: .tasks)
            let content = SystemNotificationScheduler.content(for: request)
            let title = try #require(content.value(forKey: "title") as? NSString)
            #expect(NSStringFromClass(type(of: title)).contains("LocalizedString"), "\(item.tr)")
            #expect(content.title == item.text.resolved, "\(item.tr)")
            #expect(content.body == "Ada'yı ara")
            // The archive the system receives names the key and each argument, not only a resolved
            // text. The content here holds the title alone: `userInfo` would name them by itself.
            let bare = UNMutableNotificationContent()
            bare.title = item.text.deliveryString
            let data = try NSKeyedArchiver.archivedData(withRootObject: bare, requiringSecureCoding: true)
            let archive = try #require(
                try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            let strings = Set((archive["$objects"] as? [Any] ?? []).compactMap { $0 as? String })
            #expect(strings.contains(try #require(item.text.key)), "\(item.tr)")
            #expect(strings.isSuperset(of: item.text.arguments), "\(item.tr)")
        }
    }

    @Test func plannedRequestsCarryKeysNotTheLanguageAtPlanning() throws {
        var preferences = NotificationPreferences()
        preferences.hideContent = true
        preferences.peopleEnabled = true
        let day = CalendarDate("2026-09-27")!
        var week = NotificationVaultDays()
        week.dueTasks = try notificationTasks("- [ ] 📅 2026-09-27 bir\n- [ ] 📅 2026-09-27 iki\n")
        week.openTaskCounts = [day: 2, CalendarDate("2026-09-20")!: 4]
        let people = [
            cadencePerson("a", name: "Ada", last: "2026-08-01", days: 7),
            cadencePerson("b", name: "Bora", last: "2026-08-01", days: 7),
        ]
        let requests = NotificationPlanner.requests(
            goals: NotificationGoals(), days: week, preferences: preferences, now: notificationDate(hour: 0),
            timeZone: notificationUTC, people: people)
        let task = try #require(requests.first { $0.id == "task-\(day)" })
        #expect(task.titleText == .localized("%@ görev bugün", "2"))
        #expect(task.bodyText == .localized("Önceki günlerden %@ açık görev.", "4"))
        let diary = try #require(requests.first { $0.id == "diary-\(day)" })
        #expect(diary.titleText == .localized("Gününden bir an"))
        #expect(diary.bodyText == .localized("Bugünden bir an yazmak ister misin?"))
        let reminder = try #require(requests.first { $0.destination == .people })
        #expect(reminder.titleText == .localized("Görüşme zamanı"))
        #expect(reminder.bodyText == .localized("Görüşme zamanı gelen %@ kişi var", "2"))
        // One plan reads in either language: nothing of the planning language is in it.
        #expect(task.titleText.resolved(in: Self.turkish) == "2 görev bugün")
        #expect(task.titleText.resolved(in: Self.english) == "2 tasks today")
        for request in requests {
            #expect(request.titleText.key != nil, "\(request.id)")
            #expect(request.bodyText.key != nil || request.bodyText == .verbatim(""), "\(request.id)")
        }
    }

    @Test func userTextStaysVerbatimAndIsNeverAFormat() throws {
        var preferences = NotificationPreferences()
        preferences.hideContent = false
        var week = NotificationVaultDays()
        week.dueTasks = try notificationTasks("- [ ] 📅 2026-09-27 %@ %lld 100% bitir\n")
        week.openTaskCounts = [CalendarDate("2026-09-27")!: 1]
        let requests = NotificationPlanner.requests(
            goals: NotificationGoals(), days: week, preferences: preferences, now: notificationDate(hour: 0),
            timeZone: notificationUTC)
        let task = try #require(requests.first { $0.id == "task-2026-09-27" })
        #expect(task.titleText == .verbatim("%@ %lld 100% bitir"))
        #expect(task.title == "%@ %lld 100% bitir")
        let content = SystemNotificationScheduler.content(for: task)
        #expect(content.title == "%@ %lld 100% bitir")
        #expect(
            NotificationText.localized("Bugün bekleyen hedefler: %@", "%@ 100%").resolved(in: Self.english)
                == "Goals remaining today: %@ 100%")
    }

    @Test func pendingRequestReadsBackItsKeysAndAnOlderOneIsReplaced() throws {
        let planned = NotificationRequest(
            id: "task-2026-09-27", date: notificationDate(), title: .localized("%@ görev bugün", "3"),
            body: .verbatim(""), destination: .tasks)
        let content = SystemNotificationScheduler.content(for: planned)
        let pending = UNNotificationRequest(identifier: planned.id, content: content, trigger: nil)
        let read = try #require(SystemNotificationScheduler.planned(pending))
        #expect(read == planned)
        #expect(read.isSameSchedule(as: planned))

        // A build before 2026-11-13 left the resolved text and no keys.
        let old = UNMutableNotificationContent()
        old.title = "3 görev bugün"
        old.userInfo = ["fireDate": planned.date.timeIntervalSince1970]
        let older = try #require(
            SystemNotificationScheduler.planned(
                UNNotificationRequest(identifier: planned.id, content: old, trigger: nil)))
        #expect(older.titleText == .verbatim("3 görev bugün"))
        #expect(!older.isSameSchedule(as: planned))
    }

    @Test func sameKeyWithOtherArgumentsIsAnotherSchedule() {
        func request(_ title: NotificationText, _ body: NotificationText) -> NotificationRequest {
            NotificationRequest(
                id: "task-2026-09-27", date: notificationDate(), title: title, body: body, destination: .tasks)
        }
        let planned = request(
            .localized("%@ görev bugün", "3"), .localized("Önceki günlerden %@ açık görev.", "4"))
        #expect(planned.isSameSchedule(as: planned))
        #expect(!planned.isSameSchedule(as: request(.localized("%@ görev bugün", "2"), planned.bodyText)))
        #expect(
            !planned.isSameSchedule(
                as: request(planned.titleText, .localized("Önceki günlerden %@ açık görev.", "5"))))
        let named = request(.verbatim("Ada'yı ara"), .verbatim(""))
        #expect(named.isSameSchedule(as: named))
        #expect(!named.isSameSchedule(as: request(.verbatim("Bora'yı ara"), .verbatim(""))))
        #expect(!named.isSameSchedule(as: request(.verbatim("Ada'yı ara"), .verbatim("not"))))
    }

    /// A stored form can hold fewer arguments than its format reads; formatting it would read
    /// past them, so the format comes back as written.
    @Test func aFormatWithoutItsArgumentsIsNotFormatted() throws {
        let short = try #require(NotificationText(stored: ["%@ görev bugün"]))
        #expect(short.resolved(in: Self.turkish) == "%@ görev bugün")
        #expect(short.resolved(in: Self.english) == "%@ tasks today")
        let positional = NotificationText.localized("%@, %@, %@ ve %@ kişi daha", "Ada", "Bora", "Cem")
        #expect(positional.resolved(in: Self.english) == "%1$@, %2$@, %3$@ and %4$@ more people")
        // More arguments than the format reads are harmless.
        #expect(NotificationText.localized("Günlük hedefler", "fazla").resolved(in: Self.english) == "Daily goals")
        // A key outside the catalog is its own format.
        #expect(NotificationText.localized("yok %lld", "3").resolved(in: Self.english) == "yok %lld")
        #expect(NotificationText.localized("yok %@ %", "3").resolved(in: Self.english) == "yok %@ %")

        #expect(NotificationText.argumentCount(of: "düz") == 0)
        #expect(NotificationText.argumentCount(of: "%@ ve %@") == 2)
        #expect(NotificationText.argumentCount(of: "%2$@ ve %1$@") == 2)
        #expect(NotificationText.argumentCount(of: "%4$@") == 4)
        #expect(NotificationText.argumentCount(of: "100%% %@") == 1)
        #expect(NotificationText.argumentCount(of: "%%@") == 0)
        #expect(NotificationText.argumentCount(of: "%lld") == nil)
        #expect(NotificationText.argumentCount(of: "%0$@") == nil)
        #expect(NotificationText.argumentCount(of: "yarım %") == nil)
    }

    @Test func storedFormRoundTrips() {
        for text in Self.texts.map(\.text) + [.verbatim(""), .verbatim("Ada"), .verbatim("%@")] {
            #expect(NotificationText(stored: text.stored) == text)
        }
        #expect(NotificationText(stored: []) == nil)
        #expect(NotificationText(stored: ["", "a", "b"]) == nil)
    }
}
