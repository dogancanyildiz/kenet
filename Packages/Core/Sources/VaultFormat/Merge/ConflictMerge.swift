/// One version of a file that a sync conflict produced.
public struct MergeVersion: Hashable, Sendable {
    /// The exact bytes of the file.
    public let bytes: [UInt8]

    /// When the file was last changed. The unit is the caller's; only the order matters.
    public let modificationTime: Int

    public init(bytes: [UInt8], modificationTime: Int) {
        self.bytes = bytes
        self.modificationTime = modificationTime
    }
}

/// What merging two versions produced.
public struct MergeResult: Hashable, Sendable {
    /// The bytes of the merged file.
    public let bytes: [UInt8]

    /// The versions that hold content the merged file does not and that must be kept as
    /// conflict copies: none, one or both, the older version first.
    public let preserved: [MergeVersion]

    /// Whether the merge gave up and returned the newer version with the older one preserved,
    /// because reading the merged file back did not confirm what the merge had built. The app can
    /// tell the user that the versions were not merged.
    public let fellBack: Bool

    public init(bytes: [UInt8], preserved: [MergeVersion], fellBack: Bool = false) {
        self.bytes = bytes
        self.preserved = preserved
        self.fellBack = fellBack
    }
}

/// Merges the two versions of a file that a sync conflict produced, as `vault-format.md`
/// describes under "Senkronizasyon çakışması".
///
/// The function is pure: it depends on the two versions alone, gives the same result in
/// either argument order, and never fails. Whatever it cannot fit into the merged file is
/// reported through `preserved`, so that no content is lost silently.
public enum ConflictMerge {
    public static func merge(_ first: MergeVersion, _ second: MergeVersion) -> MergeResult {
        if first.bytes == second.bytes { return MergeResult(bytes: first.bytes, preserved: []) }
        let order = MergeOrder(first, second)
        let newer = RawDocument(bytes: order.newer.bytes)
        let older = RawDocument(bytes: order.older.bytes)

        if newer.isReadOnly || older.isReadOnly {
            return MergeResult(bytes: order.newer.bytes, preserved: [order.older])
        }
        if newer.lines.map(\.content) == older.lines.map(\.content) {
            return MergeResult(bytes: order.newer.bytes, preserved: [])
        }

        var preserved = Preservation()
        let frontmatter = FrontmatterMerge.merge(newer: newer, older: older, preserved: &preserved)
        let body = BodyMerge.merge(
            newer: MergeBody(newer), older: MergeBody(older), hasFrontmatter: !frontmatter.isEmpty,
            preserved: &preserved)
        let assembled = MergeAssembly.document(
            frontmatter: frontmatter, body: body.lines, hasByteOrderMark: newer.hasByteOrderMark,
            newLineEnding: newer.lineEndingForNewLines)
        let result = RawDocument(bytes: assembled.serialized())
        guard
            LossCheck.passes(
                result: result, frontmatterLineCount: frontmatter.count, built: body, newer: newer, older: older,
                preserved: preserved)
        else {
            // The merge went wrong somewhere; the newer version with the older kept loses nothing.
            return MergeResult(bytes: order.newer.bytes, preserved: [order.older], fellBack: true)
        }

        var copies: [MergeVersion] = []
        if preserved.older { copies.append(order.older) }
        if preserved.newer { copies.append(order.newer) }
        return MergeResult(bytes: result.serialized(), preserved: copies)
    }
}

/// The two sides of a merge.
enum MergeSide: Hashable, Sendable {
    case newer
    case older

    var other: MergeSide { self == .newer ? .older : .newer }
}

/// Which versions must be kept as conflict copies.
struct Preservation: Hashable, Sendable {
    var newer = false
    var older = false

    mutating func keep(_ side: MergeSide) {
        switch side {
        case .newer: newer = true
        case .older: older = true
        }
    }
}

/// The versions told apart: the newer one has the larger modification time, or, when the
/// times are equal, the bytes that sort later.
struct MergeOrder: Sendable {
    let newer: MergeVersion
    let older: MergeVersion

    init(_ first: MergeVersion, _ second: MergeVersion) {
        let firstIsNewer: Bool
        if first.modificationTime != second.modificationTime {
            firstIsNewer = first.modificationTime > second.modificationTime
        } else {
            firstIsNewer = second.bytes.lexicographicallyPrecedes(first.bytes)
        }
        newer = firstIsNewer ? first : second
        older = firstIsNewer ? second : first
    }
}
