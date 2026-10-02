/// A lossless, line-based view of a file's bytes.
///
/// Every byte of the file belongs to exactly one place: the optional byte order mark, a line's
/// content, or a line's ending. Serializing an unmodified document therefore reproduces the
/// file byte for byte, including files that are not valid UTF-8.
///
/// A document read from bytes always satisfies:
/// - No line content contains LF or CR.
/// - Every line except the last has a line ending.
/// - A line without a line ending has content, so a file that ends with a line ending has no
///   empty line after it, and an empty file has no lines.
/// - A line ending in CR is never directly followed by an empty line ending in LF: those two
///   bytes are read as a single CRLF ending.
public struct RawDocument: Hashable, Sendable {
    /// The UTF-8 byte order mark (`EF BB BF`).
    public static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// Whether the file starts with a UTF-8 byte order mark.
    ///
    /// The mark is not part of the first line's content; serialization writes it back.
    public let hasByteOrderMark: Bool

    /// The lines of the file in order.
    public let lines: [RawLine]

    init(hasByteOrderMark: Bool, lines: [RawLine]) {
        self.hasByteOrderMark = hasByteOrderMark
        self.lines = lines
    }

    /// Whether every line decodes as UTF-8, which is the same as the whole file being valid UTF-8.
    public var isValidUTF8: Bool {
        lines.allSatisfy { $0.text != nil }
    }

    /// Whether the app must not write to this file.
    ///
    /// The vault format makes a file that cannot be decoded as UTF-8 read-only.
    public var isReadOnly: Bool {
        !isValidUTF8
    }

    /// The line ending to use for lines added to this document.
    ///
    /// This is the first line ending in the file, whichever of the three it is, or LF when the
    /// file has none.
    public var lineEndingForNewLines: LineEnding {
        lines.lazy.compactMap(\.ending).first ?? .lf
    }
}
