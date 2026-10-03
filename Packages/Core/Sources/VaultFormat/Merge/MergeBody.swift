/// A region of the body: the lines from a first or second level heading up to the next one,
/// or the lines before the first heading.
struct MergeRegion: Sendable {
    /// The heading line without trailing blanks; `nil` for the region before the first heading.
    let key: [UInt8]?
    /// The lines of the region in its document, heading included.
    let range: Range<Int>
    /// The recognized section this heading opens, when it is the first `## Tasks`, `## Events`
    /// or `## Journal` of the document.
    let kind: DaySectionKind?
    /// The indices (into `MergeBody.blocks`) of the blocks that start in this region, in order.
    var blocks: [Int] = []
}

/// An event or task line without indentation, together with the more indented lines below it.
struct MergeBlock: Sendable {
    /// The index of the region the block starts in.
    let region: Int
    /// The lines of the block in its document.
    let range: Range<Int>
    /// The content of every line of the block.
    let contents: [[UInt8]]
    /// The block identifier of the first line, when it has one.
    let id: String?
    let kind: BodyLineKind
    /// Whether the task is done or cancelled; `nil` for an event.
    let isClosed: Bool?
    /// The character inside the task's checkbox; `nil` for an event.
    let status: String?
    /// The clock time of the event; `nil` for a task or a timeless event.
    let time: EventTime?
    /// The contents with the checkbox character and the completion date at the end of the first
    /// line removed, which is the part of a task that may differ without being a conflict.
    let normalized: [[UInt8]]

    var isTask: Bool { kind == .task }
}

/// The body of one version read into regions and blocks, without changing any bytes.
struct MergeBody: Sendable {
    let document: RawDocument
    /// The first line of the body: the line after the frontmatter, or the first line.
    let start: Int
    let regions: [MergeRegion]
    let blocks: [MergeBlock]

    init(_ document: RawDocument) {
        self.document = document
        start = document.frontmatterLineRange?.upperBound ?? 0
        var regions = Self.regions(of: document, from: start)
        var blocks: [MergeBlock] = []
        var regionIndex = 0
        for block in Self.lineBlocks(of: document) {
            while regionIndex + 1 < regions.count, regions[regionIndex + 1].range.lowerBound <= block.line {
                regionIndex += 1
            }
            let region = regions[regionIndex]
            guard region.range.contains(block.line) else { continue }
            // A block never reaches into the next region, even when a more indented heading follows.
            let range = block.lineRange.clamped(to: region.range)
            regions[regionIndex].blocks.append(blocks.count)
            blocks.append(MergeBlock(document: document, block: block, region: regionIndex, range: range))
        }
        self.regions = regions
        self.blocks = blocks
    }

    /// Whether the line holds only blanks or nothing.
    static func isBlank(_ content: [UInt8]) -> Bool {
        content.allSatisfy(Syntax.isBlank)
    }

    private static func regions(of document: RawDocument, from start: Int) -> [MergeRegion] {
        let lines = document.lines
        var headings: [(line: Int, key: [UInt8], kind: DaySectionKind?)] = []
        var seen: Set<DaySectionKind> = []
        var fence = FenceScanner()
        for index in start..<lines.count {
            let bytes = lines[index].content
            if fence.consumes(bytes) { continue }
            guard let level = SectionParser.headingLevel(bytes), level <= 2 else { continue }
            let key = SectionParser.trimmedHeading(bytes)
            let candidate = DaySectionKind.allCases.first { key.elementsEqual(("## " + $0.rawValue).utf8) }
            let kind = candidate.flatMap { seen.insert($0).inserted ? $0 : nil }
            headings.append((index, key, kind))
        }
        var regions = [MergeRegion(key: nil, range: start..<(headings.first?.line ?? lines.count), kind: nil)]
        for (offset, heading) in headings.enumerated() {
            let end = offset + 1 < headings.count ? headings[offset + 1].line : lines.count
            regions.append(MergeRegion(key: heading.key, range: heading.line..<end, kind: heading.kind))
        }
        return regions
    }

    /// The events and the tasks without indentation or quote marker, in line order.
    private static func lineBlocks(of document: RawDocument) -> [(
        line: Int, lineRange: Range<Int>, block: LineBlock, task: TaskLine?, event: EventLine?
    )] {
        let body = document.bodyLines
        var found: [(line: Int, lineRange: Range<Int>, block: LineBlock, task: TaskLine?, event: EventLine?)] = []
        for task in body.tasks {
            let first = task.block.firstLineContent
            guard LineSyntax.indentation(first).columns == 0, first.first != UInt8(ascii: ">") else { continue }
            found.append((task.block.line, task.block.lineRange, task.block, task, nil))
        }
        for event in body.events {
            found.append((event.block.line, event.block.lineRange, event.block, nil, event))
        }
        return found.sorted { $0.line < $1.line }
    }
}

extension MergeBlock {
    fileprivate init(
        document: RawDocument,
        block: (line: Int, lineRange: Range<Int>, block: LineBlock, task: TaskLine?, event: EventLine?),
        region: Int, range: Range<Int>
    ) {
        self.region = region
        self.range = range
        contents = range.map { document.lines[$0].content }
        id = block.block.id
        kind = block.block.kind
        isClosed = block.task.map(\.status.isClosed)
        status = block.task?.rawStatus
        time = block.event?.time
        if block.task != nil {
            var lines = contents
            lines[0] = TaskNormalization.normalizedFirstLine(lines[0])
            normalized = lines
        } else {
            normalized = contents
        }
    }
}

/// Removes from a task's first line what may differ between two versions of the same task
/// without being a conflict: the checkbox character and the completion date that stands at the
/// end of the line, before the identifier. A date anywhere else is text.
enum TaskNormalization {
    private static let completionMark: [UInt8] = Array(" ✅ ".utf8)

    static func normalizedFirstLine(_ content: [UInt8]) -> [UInt8] {
        var bytes = content
        if let checkbox = BodyLineParser.task(bytes) {
            bytes.removeSubrange(checkbox.statusRange)
        }
        let split = BodyLineParser.splitID(Syntax.string(bytes))
        var text = Array(split.text.utf8)
        let trailingBlanks = text.reversed().prefix(while: Syntax.isBlank).count
        let end = text.count - trailingBlanks
        let dateStart = end - 10
        let markStart = dateStart - completionMark.count
        if markStart >= 0, text[markStart..<dateStart].elementsEqual(completionMark), isDate(text[dateStart..<end]) {
            text.removeSubrange(markStart..<end)
        }
        return text + (split.id.map { Array(" ^\($0)".utf8) } ?? [])
    }

    /// Whether the bytes are `YYYY-MM-DD`.
    private static func isDate(_ bytes: ArraySlice<UInt8>) -> Bool {
        guard bytes.count == 10 else { return false }
        for (offset, byte) in bytes.enumerated() {
            if offset == 4 || offset == 7 {
                guard byte == Syntax.dash else { return false }
            } else {
                guard Syntax.isDigit(byte) else { return false }
            }
        }
        return true
    }
}
