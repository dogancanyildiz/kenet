import Foundation

/// The filesystem observation the incremental index compares before it reads a file again.
///
/// Modification time and size alone miss a same-size external edit on volumes with coarse
/// timestamps (FAT and exFAT 2 s, SMB and NFS 1 s). The status change time (`ctime`) moves on
/// every in-place write and the inode moves when an editor replaces the file by renaming.
struct FileStamp: Equatable, Sendable {
    let modified: Double
    let changed: Double
    let inode: Int64
    let size: Int

    /// A stamp verified less than this many seconds after its modification time is racy: a later
    /// edit within the same timestamp tick would leave every field unchanged.
    static let racyWindow: Double = 2

    /// Test seam: replaces the filesystem observation, for example to simulate a coarse volume.
    @TaskLocal static var reader: @Sendable (URL) throws -> FileStamp = { try FileStamp(url: $0) }
    /// Test seam: the wall-clock time recorded as the moment a stamp was verified.
    @TaskLocal static var clock: @Sendable () -> Double = { Date().timeIntervalSince1970 }

    init(modified: Double, changed: Double, inode: Int64, size: Int) {
        self.modified = modified
        self.changed = changed
        self.inode = inode
        self.size = size
    }

    init(url: URL) throws {
        var status = stat()
        guard stat(url.path, &status) == 0 else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        #if canImport(Darwin)
            let modified = status.st_mtimespec
            let changed = status.st_ctimespec
        #else
            let modified = status.st_mtim
            let changed = status.st_ctim
        #endif
        self.modified = Double(modified.tv_sec) + Double(modified.tv_nsec) / 1_000_000_000
        self.changed = Double(changed.tv_sec) + Double(changed.tv_nsec) / 1_000_000_000
        inode = Int64(bitPattern: UInt64(status.st_ino))
        size = Int(status.st_size)
    }

    /// Whether an unchanged stamp proves unchanged bytes: it was verified well after its last edit.
    func isSettled(verifiedAt verified: Double) -> Bool {
        verified - modified >= Self.racyWindow
    }
}
