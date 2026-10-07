import Foundation

/// Mutable write-gate state owned by one `VaultStore` and touched only on that store's write queue.
final class WriteGate: @unchecked Sendable {
    var checked = false
    var missing = false
    var mtime: Date?
    var allowsWrite = true
}
