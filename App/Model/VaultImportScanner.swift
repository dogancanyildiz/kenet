import CoreFoundation
import Foundation
import VaultFormat

enum VaultImportScanner {
    static func markdownFiles(in root: URL) throws -> [String] {
        try listing(in: root).files
    }
    private static func listing(in root: URL) throws -> (files: [String], skipped: [String]) {
        var files: [String] = []
        var skipped: [String] = []
        func visit(_ url: URL, prefix: String) throws {
            let children: [URL]
            do {
                children = try FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            } catch {
                if prefix.isEmpty { throw error }
                skipped.append(prefix)
                return
            }
            for file in children.sorted(by: { $0.path < $1.path }) {
                let name = file.lastPathComponent
                guard !name.hasPrefix("."), !(prefix.isEmpty && ["templates", "conflicts"].contains(name))
                else { continue }
                let path = prefix + name
                guard let values = try? file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                else {
                    skipped.append(path)
                    continue
                }
                if values.isSymbolicLink == true {
                    skipped.append(path)
                    continue
                }
                if values.isDirectory == true {
                    try visit(file, prefix: path + "/")
                } else if name.hasSuffix(".md") {
                    files.append(path)
                }
            }
        }
        try visit(root, prefix: "")
        return (files, skipped)
    }
    static func supportsSettings(at root: URL) -> Bool {
        let url: URL
        do { url = try VaultImportBootstrap.checked(".app/vault.json", root: root) } catch { return false }
        if !FileManager.default.fileExists(atPath: url.path) { return true }
        guard let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let value = json["formatVersion"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
            value.doubleValue == 1
        else { return false }
        return true
    }
    static func inspect(_ root: URL) throws -> VaultImportReport {
        var report = VaultImportReport(root: root)
        let children = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        report.foundFolders = try children.filter {
            let values = try $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return values.isDirectory == true && values.isSymbolicLink != true
        }.map(\.lastPathComponent).sorted()
        report.missingFolders = VaultImportReport.folders.filter { !report.foundFolders.contains($0) }
        for path in ["templates/person.md", "templates/place.md"] {
            if !FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) {
                report.missingTemplates.append(path)
            }
        }
        let settings = root.appendingPathComponent(".app/vault.json")
        report.needsSettings = !FileManager.default.fileExists(atPath: settings.path)
        report.canPrepare = supportsSettings(at: root)
        if !report.canPrepare { report.skipped.append(".app/vault.json") }
        let listing = try listing(in: root)
        report.skipped += listing.skipped
        for path in listing.files {
            report.markdownCount += 1
            let parts = path.split(separator: "/")
            if let file = parts.last, CalendarDate(String(file.dropLast(3))) != nil {
                if parts.count == 2 && parts[0] == "journal" {
                    report.journalDays.append(path)
                } else if parts.count == 1 || (parts.count == 2 && parts[0] == "daily") {
                    report.externalDays.append(path)
                }
            }
            guard let data = try? Data(contentsOf: root.appendingPathComponent(path)) else {
                report.skipped.append(path)
                continue
            }
            let document = RawDocument(bytes: data)
            guard String(data: data, encoding: .utf8) != nil, !document.isReadOnly, document.frontmatter != .unreadable
            else {
                report.skipped.append(path)
                continue
            }
            let type: String?
            let hasType: Bool
            if case .parsed(let fields) = document.frontmatter {
                hasType = fields.field(named: "type") != nil
                if case .scalar(let value) = fields.field(named: "type")?.value {
                    type = value.text
                } else {
                    type = nil
                }
            } else {
                type = nil
                hasType = false
            }
            if let type, ["person", "place", "goal"].contains(type) { report.typed[type, default: 0] += 1 }
            if !hasType, let folder = parts.first, ["people", "places"].contains(folder), parts.count > 1 {
                report.candidates.append(.init(path: path, kind: folder == "people" ? "person" : "place"))
            }
        }
        return report
    }
}
