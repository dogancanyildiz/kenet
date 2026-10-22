import Foundation
import Observation

/// The form's state in the extension: the text, a write in flight, a failed write.
@MainActor @Observable final class ShareFormModel {
    var text = ""
    private(set) var isSaving = false
    private(set) var failed = false
    @ObservationIgnored private let writer: ShareEntryWriter
    @ObservationIgnored private let finish: () -> Void
    @ObservationIgnored let cancel: () -> Void

    init(writer: ShareEntryWriter, finish: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.writer = writer
        self.finish = finish
        self.cancel = cancel
    }

    func load(_ items: [Any]) async {
        let shared = await ShareInput.text(from: items)
        if text.isEmpty { text = shared }
    }

    /// Writes into the iCloud vault or queues for the app (`ShareEntryWriter`); the sheet closes
    /// once either is saved, and stays open with an error when neither could be.
    func confirm() {
        guard !isSaving else { return }
        let entry = ShareEntry(text: EntryWriting.singleLine(text), at: Date())
        guard entry.isWritable else { return }
        isSaving = true
        failed = false
        Task {
            do {
                _ = try await writer.add(entry)
                finish()
            } catch {
                failed = true
                isSaving = false
            }
        }
    }
}
