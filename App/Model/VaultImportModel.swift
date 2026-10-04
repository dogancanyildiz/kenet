import Foundation
import Observation

@MainActor @Observable
final class VaultImportModel: Identifiable {
    let id = UUID()
    let report: VaultImportReport
    var options = VaultImportOptions()
    private(set) var result: VaultImportResult?
    private(set) var isApplying = false
    private let accessed: Bool
    init(root: URL) async throws {
        accessed = root.startAccessingSecurityScopedResource()
        do { report = try await Task.detached { try VaultImportScanner.inspect(root) }.value } catch {
            if accessed { root.stopAccessingSecurityScopedResource() }
            throw error
        }
    }
    deinit { if accessed { report.root.stopAccessingSecurityScopedResource() } }
    func apply() async {
        guard !isApplying, result == nil else { return }
        isApplying = true
        let report = report
        let options = options
        result = await Task.detached { await VaultImportWriter.apply(report: report, options: options) }.value
        isApplying = false
    }
}
