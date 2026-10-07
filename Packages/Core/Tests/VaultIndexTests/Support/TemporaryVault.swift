import Foundation

func withVault(
    in directory: URL = FileManager.default.temporaryDirectory, _ action: (URL) throws -> Void
) throws {
    let root = directory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try action(root)
}

func write(_ root: URL, _ path: String, _ text: String) throws {
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

/// True when the volume under `directory` distinguishes letter case in paths.
func isCaseSensitiveFileSystem(at directory: URL) throws -> Bool {
    let probe = directory.appendingPathComponent("CaseProbe_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: probe, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: probe) }
    let lower = probe.appendingPathComponent("case_probe_a")
    let upper = probe.appendingPathComponent("case_probe_A")
    try FileManager.default.createDirectory(at: lower, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: lower) }
    return !FileManager.default.fileExists(atPath: upper.path)
}
