import CryptoKit
import DateParsing
import Foundation
import GoalTracking
import VaultFormat
import VaultStore

struct IntentGoal: Sendable, Identifiable {
    let id: String
    let definition: GoalDefinition
    init(definition: GoalDefinition, root: URL) {
        self.definition = definition
        let path = root.resolvingSymlinksInPath().standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        id = digest + ":" + definition.key
    }
}
struct IntentActionResult: Sendable {
    let dialog: LocalizedStringResource
    var text: String { String(localized: dialog) }
}

enum IntentActionError: LocalizedError {
    case vaultUnavailable, emptyText, writeFailed, goalMissing, invalidAmount, appLocked
    var errorDescription: String? {
        switch self {
        case .vaultUnavailable: String(localized: "Kasaya erişilemiyor. Journal'da kasanı açıp yeniden dene.")
        case .emptyText: String(localized: "Eklenecek metin boş olamaz.")
        case .writeFailed: String(localized: "Kayıt yazılamadı. Kasa erişimini ve metni kontrol et.")
        case .goalMissing: String(localized: "Hedef bulunamadı. Kısayolda hedefi yeniden seç.")
        case .invalidAmount: String(localized: "Sayısal hedef için sıfır veya daha büyük, sonlu bir miktar gir.")
        case .appLocked: String(localized: "Günlük kilitli. Uygulamayı açıp kilidi aç.")
        }
    }
}

/// Shared by foreground UI and App Intents; no real vault is opened by construction.
@MainActor
final class IntentActions {
    static let shared: IntentActions = {
        IntentActions(isLocked: {
            // Cold intent launch before JournalApp attaches the live service: enabled ⇒ unauthenticated.
            UserDefaults.standard.bool(forKey: AppLockService.enabledKey)
        })
    }()
    let store: IndexStore
    private let now: () -> Date
    private let permitsStart: () -> Bool
    /// Locked means app lock is enabled and not yet authenticated (`isEnabled && isLocked`).
    var isLocked: () -> Bool
    private var isPerforming = false
    var languages: [DateParsing.Language] = [.turkish, .english]

    init(
        store: IndexStore = IndexStore(), now: @escaping () -> Date = { Date() },
        permitsStart: @escaping () -> Bool = { AppLaunchPolicy.allowsAutomaticStart() },
        isLocked: @escaping () -> Bool = { false }
    ) {
        self.store = store
        self.now = now
        self.permitsStart = permitsStart
        self.isLocked = isLocked
    }

    /// Bind the live lock service so foreground unlock state is visible to intents.
    func attach(lock: AppLockService) {
        isLocked = { [weak lock] in
            guard let lock else {
                return UserDefaults.standard.bool(forKey: AppLockService.enabledKey)
            }
            return lock.isEnabled && lock.isLocked
        }
    }

    private func requireUnlocked() throws {
        if isLocked() { throw IntentActionError.appLocked }
    }

    private func prepare() async throws {
        guard permitsStart() else { throw IntentActionError.vaultUnavailable }
        do { try await store.prepareForIntent() } catch { throw IntentActionError.vaultUnavailable }
    }
    private func begin() async throws {
        for _ in 0..<400 {
            if !isPerforming { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard !isPerforming else { throw IntentActionError.writeFailed }
        isPerforming = true
        do { try await prepare() } catch {
            isPerforming = false
            throw error
        }
    }
    func goals() async throws -> [IntentGoal] {
        if isLocked() { return [] }
        try await begin()
        defer { isPerforming = false }
        guard let root = store.vaultURL else { throw IntentActionError.vaultUnavailable }
        return store.content.goals.map { IntentGoal(definition: $0, root: root) }
    }
    func addEvent(text: String, time: LineClock? = nil) async throws -> IntentActionResult {
        guard !text.allSatisfy(\.isWhitespace) else { throw IntentActionError.emptyText }
        try requireUnlocked()
        try await begin()
        defer { isPerforming = false }
        let instant = now()
        let linked: String
        do { linked = try IntentText.linking(text, entities: store.knownEntities) } catch {
            throw IntentActionError.writeFailed
        }
        guard
            await store.addEvent(
                on: LocalDay.today(at: instant), text: linked, time: time ?? LocalDay.clock(at: instant))
        else { throw IntentActionError.writeFailed }
        return IntentActionResult(dialog: "Olay eklendi: \(IntentText.display(linked))")
    }
    /// Confirms an assumed natural-language date before it is applied. Default (nil) declines.
    func addTask(
        text: String, due: CalendarDate? = nil,
        confirmAssumedDate: ((CalendarDate) async -> Bool)? = nil
    ) async throws -> IntentActionResult {
        try requireUnlocked()
        let day = LocalDay.today(at: now())
        let recurrence = RecurrenceExpressionParser.parse(text, language: languages)
        let priority = PriorityExpressionParser.parse(recurrence?.remainder ?? text)
        let input = priority?.remainder ?? recurrence?.remainder ?? text
        let explicit = RawDocument(bytes: ("- [ ] " + text).utf8).bodyLines.tasks.first?.priority
        let expression = DateExpressionParser.parse(input, today: day, language: languages)
        let resolved = await Self.resolveTaskDate(
            due: due, expression: expression, input: input, confirmAssumedDate: confirmAssumedDate)
        guard !resolved.text.allSatisfy(\.isWhitespace) else { throw IntentActionError.emptyText }
        try await begin()
        defer { isPerforming = false }
        let linked: String
        do { linked = try IntentText.linking(resolved.text, entities: store.knownEntities) } catch {
            throw IntentActionError.writeFailed
        }
        guard
            await store.addTask(
                on: day, text: linked, due: resolved.due, priority: explicit ?? priority?.priority,
                recurrence: recurrence?.recurrence)
        else {
            throw IntentActionError.writeFailed
        }
        return IntentActionResult(dialog: "Görev eklendi: \(IntentText.display(linked))")
    }

    /// Chooses due date and body text for an intent task from an explicit due and/or parse result.
    static func resolveTaskDate(
        due: CalendarDate?, expression: DateParse?, input: String,
        confirmAssumedDate: ((CalendarDate) async -> Bool)?
    ) async -> (text: String, due: CalendarDate?) {
        if let due {
            return (expression?.remainder ?? input, due)
        }
        guard let expression else { return (input, nil) }
        switch expression.confidence {
        case .exact:
            return (expression.remainder, expression.date)
        case .assumed:
            let confirmed = await confirmAssumedDate?(expression.date) ?? false
            if confirmed { return (expression.remainder, expression.date) }
            return (input, nil)
        }
    }
    func markGoal(id: String, amount: Double? = nil) async throws -> IntentActionResult {
        try requireUnlocked()
        try await begin()
        defer { isPerforming = false }
        guard let root = store.vaultURL,
            let goal = store.content.goals.first(where: { IntentGoal(definition: $0, root: root).id == id })
        else { throw IntentActionError.goalMissing }
        let value: GoalValue
        if goal.kind != .number {
            value = .boolean(true)
        } else {
            guard let amount, amount.isFinite, amount >= 0 else { throw IntentActionError.invalidAmount }
            value = .number(amount)
        }
        do { try await store.setGoal(on: LocalDay.today(at: now()), key: goal.key, value: value) } catch VaultStoreError
            .indexUpdateFailed
        {
            // Saved bytes are already the result.
        } catch { throw IntentActionError.writeFailed }
        return IntentActionResult(dialog: "Hedef kaydedildi: \(goal.name)")
    }
}
