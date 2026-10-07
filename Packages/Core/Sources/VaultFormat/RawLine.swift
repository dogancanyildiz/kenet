/// One line of a document, stored as the exact bytes found in the file.
///
/// The content and the line ending are kept apart so that either can be inspected without
/// disturbing the other. Text is derived from the bytes on demand and is never used to
/// rebuild them.
public struct RawLine: Hashable, Sendable {
    /// The bytes of the line without its line ending. Never contains LF or CR.
    public let content: [UInt8]

    /// The terminator that follows the content, or `nil` when the file ends without one.
    public let ending: LineEnding?

    init(content: [UInt8], ending: LineEnding?) {
        self.content = content
        self.ending = ending
    }

    /// The bytes of the line as they appear in the file: content followed by the line ending.
    public var bytes: [UInt8] {
        guard let ending else { return content }
        return content + ending.bytes
    }

    /// The content decoded as UTF-8, or `nil` when the content is not well-formed UTF-8.
    ///
    /// Nothing is repaired or normalized: when a value is returned, its UTF-8 bytes equal `content`.
    public var text: String? {
        StrictUTF8.decode(content)
    }

    /// The content as text for showing to the user, with every ill-formed byte sequence
    /// replaced by U+FFFD.
    ///
    /// Equal to `text` when the content is well-formed UTF-8. For display only: the replacement
    /// loses bytes, so this value must never be used on a path that writes to the file.
    public var displayText: String {
        String(decoding: content, as: UTF8.self)
    }
}
