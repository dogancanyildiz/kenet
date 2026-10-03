import Foundation
import Observation
import VaultStore

@MainActor @Observable
final class EntityRenameModel {
    let detail: EntityDetailModel
    var name: String
    var qualifier: String
    private(set) var needsQualifier = false
    private(set) var isRenaming = false
    private(set) var result: RenameResult?
    private(set) var errorText: String?

    init(detail: EntityDetailModel, name: String, qualifier: String?) {
        self.detail = detail
        self.name = name
        self.qualifier = qualifier ?? ""
    }

    func save() async {
        guard !isRenaming, result == nil else { return }
        isRenaming = true
        errorText = nil
        defer { isRenaming = false }
        do {
            let qualifier = qualifier.trimmingCharacters(in: .whitespacesAndNewlines)
            result = try await detail.rename(to: name, qualifier: qualifier.isEmpty ? nil : qualifier)
        } catch VaultStoreError.nameTaken {
            needsQualifier = true
        } catch { errorText = DayEditError.message(for: error) }
    }
}
