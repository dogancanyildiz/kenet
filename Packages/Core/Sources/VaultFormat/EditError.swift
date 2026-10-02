/// Why an edit was refused.
///
/// Editing returns a new document and never changes the one it was called on, so a refused
/// edit leaves nothing half done: there is no document to write to the file.
public enum EditError: Error, Hashable, Sendable {
    /// The file is not valid UTF-8, which makes it read-only.
    case readOnlyDocument
    /// A line range lies outside the document or overlaps another edit of the same batch.
    case invalidLineRange
    /// New line content contains LF or CR.
    case lineBreakInContent
    /// The frontmatter cannot be parsed as a whole; the app does not write to it.
    case unreadableFrontmatter
    /// The field uses YAML outside the supported subset; it is kept as raw text and never changed.
    case rawField(key: String)
    /// The field holds a value, so entries cannot be written under it.
    case notAMapping(key: String)
    /// The key is empty or is the YAML merge key `<<`.
    case invalidKey
    /// The value has no spelling in the vault format (a number that is not written as digits).
    case invalidValue
}
