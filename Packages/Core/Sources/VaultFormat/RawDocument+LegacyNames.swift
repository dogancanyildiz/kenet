extension RawDocument {
    /// The day file with the names an older vault wrote turned into today's names, as the vault
    /// migration writes it (`vault-format.md`, "Eski adlar ve geçiş"). Exactly two places change:
    ///
    /// - The recognized diary heading, when it has the legacy name: only the name becomes
    ///   `Diary`; the trailing blanks and the line ending stay.
    /// - A readable frontmatter `type` field whose value is the legacy day type: it becomes
    ///   `VaultLayout.dayType` by the single-field rule.
    ///
    /// Every other byte, the byte order mark included, stays. A read-only document (not UTF-8),
    /// a heading inside a code fence, a second diary heading and a frontmatter that cannot be read
    /// are left as they are. Returns the document unchanged when nothing applies.
    public func migratingLegacyDayNames() -> RawDocument {
        guard !isReadOnly else { return self }
        var result = self
        if case .parsed(let fields) = frontmatter, let field = fields.field(named: "type"),
            case .scalar(let value) = field.value, value.text == LegacyVaultNames.dayType,
            let changed = try? settingFrontmatterValue(.text(VaultLayout.dayType), forKey: "type"),
            changed.lines.count == lines.count
        {
            result = changed
        }
        guard let section = result.daySections.section(.diary) else { return result }
        let heading = result.lines[section.headingLine]
        let legacy = Array(("## " + LegacyVaultNames.diaryHeading).utf8)
        guard SectionParser.trimmedHeading(heading.content).elementsEqual(legacy) else { return result }
        let content = Array(("## " + DaySectionKind.diary.rawValue).utf8) + heading.content.dropFirst(legacy.count)
        var lines = result.lines
        lines[section.headingLine] = RawLine(content: content, ending: heading.ending)
        return RawDocument(hasByteOrderMark: result.hasByteOrderMark, lines: lines)
    }
}
