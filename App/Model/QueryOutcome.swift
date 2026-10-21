import Foundation
import VaultStore

/// How an on-demand read ended for the screen that asked it (architecture.md "Sorgu kalıbı").
/// A screen keeps what it shows unless the read answered; only a failed read shows an error.
enum QueryOutcome<Value> {
    case answer(Value)
    /// A newer request replaced this one (`.task(id:)`): the screen shows no error.
    case cancelled
    /// Another vault opened meanwhile, or none is open: the answer is not this screen's.
    case stale
    /// The read failed: the screen keeps its last answer and shows ``errorText``.
    case failed(any Error)

    /// Runs `read` and sorts how it ended. A caller cancelled meanwhile is `cancelled`, whatever
    /// `read` answered or threw.
    @MainActor static func of(_ read: () async throws -> Value) async -> QueryOutcome {
        do {
            let value = try await read()
            return Task.isCancelled ? .cancelled : .answer(value)
        } catch {
            if error is CancellationError || Task.isCancelled { return .cancelled }
            if case VaultStoreError.staleTarget = error { return .stale }
            return .failed(error)
        }
    }

    /// The line a screen shows for a failed read; nil for every other end.
    var errorText: String? {
        guard case .failed = self else { return nil }
        return String(localized: "Kasa okunamadı. Kasayı kontrol edip yeniden dene.")
    }
}

extension QueryOutcome: Sendable where Value: Sendable {}

/// A screen's last answer to one query and the error of its latest failed read.
struct QueryState<Value> {
    /// Nil until the first answer. A cancelled, stale or failed read keeps the previous one.
    private(set) var value: Value?
    /// Set by a failed read, cleared by the next answer.
    private(set) var errorText: String?

    init() {}

    mutating func apply(_ outcome: QueryOutcome<Value>) {
        switch outcome {
        case .answer(let answer):
            value = answer
            errorText = nil
        case .cancelled, .stale:
            break
        case .failed:
            errorText = outcome.errorText
        }
    }
}
