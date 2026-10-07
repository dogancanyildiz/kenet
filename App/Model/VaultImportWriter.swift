import Foundation
import VaultFormat
import VaultIndex
import VaultStore

enum VaultImportWriter {
    static func apply(report: VaultImportReport, options: VaultImportOptions) async -> VaultImportResult {
        var result = VaultImportResult(skipped: report.skipped)
        guard report.canPrepare, VaultImportScanner.supportsSettings(at: report.root) else {
            result.failures.append(".app/vault.json")
            return result
        }
        let root = report.root
        if options.folders {
            for folder in report.missingFolders {
                do {
                    if try VaultImportBootstrap.directory(folder, root: root) { result.created.append(folder + "/") }
                } catch { result.failures.append(folder) }
            }
            for path in report.missingTemplates {
                do {
                    let kind = path.contains("person") ? "person" : "place"
                    if try VaultImportBootstrap.file(path, bytes: VaultImportBootstrap.template(kind), root: root) {
                        result.created.append(path)
                    }
                } catch { result.failures.append(path) }
            }
        }
        if options.settings && report.needsSettings {
            do {
                if try VaultImportBootstrap.file(
                    ".app/vault.json", bytes: Data("{ \"formatVersion\": 1 }\n".utf8), root: root)
                {
                    result.created.append(".app/vault.json")
                }
            } catch { result.failures.append(".app/vault.json") }
        }
        if options.types {
            do {
                let index = try VaultIndex()
                let writer = VaultStore(vaultRoot: root, index: index)
                for candidate in report.candidates {
                    do {
                        let document = try await writer.document(at: candidate.path)
                        guard !document.isReadOnly, document.frontmatter != .unreadable,
                            String(bytes: document.serialized(), encoding: .utf8) != nil
                        else {
                            result.skipped.append(candidate.path)
                            continue
                        }
                        if case .parsed(let fields) = document.frontmatter, fields.field(named: "type") != nil {
                            result.skipped.append(candidate.path)
                            continue
                        }
                        _ = try await writer.settingFrontmatterValue(
                            at: candidate.path, key: "type", value: .text(candidate.kind))
                        result.typed.append(candidate.path)
                    } catch {
                        if case VaultStoreError.indexUpdateFailed = error { result.typed.append(candidate.path) }
                        result.failures.append(candidate.path)
                    }
                }
            } catch { result.failures += report.candidates.map(\.path) }
        }
        return result
    }
}
