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
    case vaultUnavailable, emptyText, writeFailed, goalMissing, invalidAmount
    var errorDescription: String? {
        switch self {
        case .vaultUnavailable: String(localized: "Kasaya erişilemiyor. Journal'da kasanı açıp yeniden dene.")
        case .emptyText: String(localized: "Eklenecek metin boş olamaz.")
        case .writeFailed: String(localized: "Kayıt yazılamadı. Kasa erişimini ve metni kontrol et.")
        case .goalMissing: String(localized: "Hedef bulunamadı. Kısayolda hedefi yeniden seç.")
        case .invalidAmount: String(localized: "Sayısal hedef için sıfır veya daha büyük, sonlu bir miktar gir.")
        }
    }
}

/// Shared by foreground UI and App Intents; no real vault is opened by construction.
@MainActor
final class IntentActions {
    static let shared = IntentActions()
    let store: IndexStore
    private let now: () -> Date
    private let permitsStart: () -> Bool
    private var isPerforming = false
    var languages: [DateParsing.Language] = [.turkish, .english]

    init(
        store: IndexStore = IndexStore(), now: @escaping () -> Date = { Date() },
        permitsStart: @escaping () -> Bool = { AppLaunchPolicy.allowsAutomaticStart() }
    ) {
        self.store = store
        self.now = now
        self.permitsStart = permitsStart
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
        try await begin()
        defer { isPerforming = false }
        guard let root = store.vaultURL else { throw IntentActionError.vaultUnavailable }
        return store.content.goals.map { IntentGoal(definition: $0, root: root) }
    }
    func addEvent(text: String, time: LineClock? = nil) async throws -> IntentActionResult {
        guard !text.allSatisfy(\.isWhitespace) else { throw IntentActionError.emptyText }
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
    func addTask(text: String, due: CalendarDate? = nil) async throws -> IntentActionResult {
        let day = LocalDay.today(at: now())
        let recurrence = RecurrenceExpressionParser.parse(text, language: languages)
        let priority = PriorityExpressionParser.parse(recurrence?.remainder ?? text)
        let input = priority?.remainder ?? recurrence?.remainder ?? text
        let explicit = RawDocument(bytes: ("- [ ] " + text).utf8).bodyLines.tasks.first?.priority
        let expression = DateExpressionParser.parse(input, today: day, language: languages)
        let remainder = expression?.remainder ?? input
        guard !remainder.allSatisfy(\.isWhitespace) else { throw IntentActionError.emptyText }
        try await begin()
        defer { isPerforming = false }
        let linked: String
        do { linked = try IntentText.linking(remainder, entities: store.knownEntities) } catch {
            throw IntentActionError.writeFailed
        }
        guard
            await store.addTask(
                on: day, text: linked, due: due ?? expression?.date, priority: explicit ?? priority?.priority,
                recurrence: recurrence?.recurrence)
        else {
            throw IntentActionError.writeFailed
        }
        return IntentActionResult(dialog: "Görev eklendi: \(IntentText.display(linked))")
    }
    func markGoal(id: String, amount: Double? = nil) async throws -> IntentActionResult {
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
