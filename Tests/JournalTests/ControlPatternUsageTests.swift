import Foundation
import Testing

/// Source guard for the control patterns (`docs/design.md`, "Denetim kalıpları"): screens build
/// their controls from the shared components instead of restyling system ones by hand.
///
/// Scope: `App/Screens`, `App/Navigation`, `App/Mac`. Today's offenders sit in a per-rule,
/// per-file allowlist that **only shrinks**: a new offender fails, and so does a listed file
/// that no longer offends (remove it from the list in the same change).
struct ControlPatternUsageTests {
    enum Rule: String, CaseIterable, Sendable {
        /// `.pickerStyle(.segmented)` → ``InkTabs``.
        case segmentedPicker
        /// `.pickerStyle(.menu)` → ``InkLabeledMenu`` (or ``InkHeaderMenu`` for sort / filter).
        case menuPicker
        /// `Picker(` with no `.pickerStyle(` in the same expression → ``InkTabs`` / ``InkLabeledMenu``.
        case unstyledPicker
        /// `.textFieldStyle(.roundedBorder)` → ``InkFilterField``.
        case roundedBorderField
        /// `SearchButton()` inside `.toolbar` → the manşet row's `actions` slot.
        case toolbarSearch
        /// `Button("Bitti"` → the sheet words are "Vazgeç", "Kaydet", "Oluştur", "Kapat".
        case doneButton
        /// Hand-built sheet toolbar (`ToolbarItem(placement: .cancellationAction` /
        /// `.confirmationAction`, or a sheet word button inside `.toolbar`) → `.inkSheet`.
        case sheetToolbar
    }

    /// Files that still break each rule. Screen work removes entries; nothing is added.
    static let allowlist: [Rule: Set<String>] = [
        .segmentedPicker: [],
        .menuPicker: [],
        .unstyledPicker: [],
        .roundedBorderField: [],
        .toolbarSearch: [
            "App/Navigation/MacNavigation.swift"
        ],
        .doneButton: [],
        .sheetToolbar: [],
    ]

    @Test(arguments: Rule.allCases)
    func allowlistOnlyShrinks(_ rule: Rule) throws {
        let offenders = Set(
            try Self.screenSwiftFiles().filter { path in
                ControlPatternScanner.violates(rule, source: try Self.read(path))
            })
        let allowed = Self.allowlist[rule] ?? []
        let unexpected = offenders.subtracting(allowed)
        #expect(
            unexpected.isEmpty,
            "\(rule.rawValue): new offenders (use the shared component): \(unexpected.sorted())")
        let cleared = allowed.subtracting(offenders)
        #expect(
            cleared.isEmpty,
            "\(rule.rawValue): no longer offending — remove from the allowlist: \(cleared.sorted())")
    }

    @Test func everyRuleHasAnAllowlistEntry() {
        for rule in Rule.allCases {
            #expect(Self.allowlist[rule] != nil, "\(rule.rawValue) missing from the allowlist")
        }
    }

    @Test func scannedFoldersExistAndHoldSources() throws {
        let files = try Self.screenSwiftFiles()
        for folder in Self.scannedFolders {
            #expect(files.contains { $0.hasPrefix(folder + "/") }, "\(folder) has no Swift files")
        }
    }

    // MARK: - Scanner self-tests (the guard must really detect each pattern)

    @Test func detectsSegmentedMenuAndRoundedBorder() {
        #expect(
            ControlPatternScanner.violates(
                .segmentedPicker, source: "Picker(\"A\", selection: $a) {}\n.pickerStyle(.segmented)"))
        #expect(
            ControlPatternScanner.violates(
                .menuPicker, source: "Picker(\"A\", selection: $a) {}\n    .pickerStyle( .menu )"))
        #expect(
            ControlPatternScanner.violates(
                .roundedBorderField, source: "TextField(\"A\", text: $a).textFieldStyle(.roundedBorder)"))
        #expect(
            !ControlPatternScanner.violates(
                .segmentedPicker, source: "// .pickerStyle(.segmented) is banned\nText(\"a\")"))
        #expect(
            !ControlPatternScanner.violates(
                .roundedBorderField, source: "TextField(\"A\", text: $a).textFieldStyle(.plain)"))
    }

    @Test func detectsUnstyledPickerOnly() {
        let unstyled = """
            Picker("Sıralama", selection: $sort) {
                ForEach(items) { Text($0.name).tag($0) }
            }
            .labelsHidden()
            .padding()
            Text("x").pickerStyle(.inline)
            """
        #expect(ControlPatternScanner.violates(.unstyledPicker, source: unstyled))
        let styled = """
            Picker(selection: $sort) {
                ForEach(items) { Text($0.name).tag($0) }
            } label: {
                Text("Sıralama")
            }
            .labelsHidden()
            #if os(iOS)
                .pickerStyle(.inline)
            #endif
            """
        #expect(!ControlPatternScanner.violates(.unstyledPicker, source: styled))
        let lookalikes = """
            DatePicker("Tarih", selection: $date)
            ColorPicker("Renk", selection: $color)
            PhotosPicker(selection: $photo) { Text("Foto") }
            EntityTypePicker(selection: $type)
            // Picker("yorum", selection: $x) {}
            """
        #expect(!ControlPatternScanner.violates(.unstyledPicker, source: lookalikes))
        // The second picker is unstyled even though the first one is styled.
        let mixed = "Picker(\"A\", selection: $a) {}.pickerStyle(.inline)\nPicker(\"B\", selection: $b) {}"
        #expect(ControlPatternScanner.violates(.unstyledPicker, source: mixed))
    }

    @Test func detectsToolbarSearchButNotHeaderSearch() {
        let toolbar = """
            List {}
                .toolbar {
                    if !isToday { SearchButton() }
                }
            """
        #expect(ControlPatternScanner.violates(.toolbarSearch, source: toolbar))
        let item = "ToolbarItem(placement: .primaryAction) { SearchButton() }"
        #expect(ControlPatternScanner.violates(.toolbarSearch, source: item))
        let header = """
            InkPageTitleRow("Görevler") {
                SearchButton()
            }
            .toolbar { EditButton() }
            """
        #expect(!ControlPatternScanner.violates(.toolbarSearch, source: header))
    }

    @Test func detectsDoneButtonAndHandBuiltSheetToolbar() {
        #expect(ControlPatternScanner.violates(.doneButton, source: "Button(\"Bitti\") { dismiss() }"))
        #expect(!ControlPatternScanner.violates(.doneButton, source: "Text(\"Bitti\")"))
        #expect(
            ControlPatternScanner.violates(
                .sheetToolbar,
                source: ".toolbar {\n ToolbarItem(placement: .cancellationAction) { Button(\"X\") {} }\n}"))
        #expect(
            ControlPatternScanner.violates(
                .sheetToolbar, source: "ToolbarItem(placement:.confirmationAction) { save }"))
        #expect(
            ControlPatternScanner.violates(
                .sheetToolbar, source: "List {}.toolbar { Button(\"Kapat\") { dismiss() } }"))
        #expect(
            ControlPatternScanner.violates(
                .sheetToolbar,
                source: ".toolbar {\n Button(\"Kapat\") { dismiss() }.buttonStyle(InkTextButtonStyle())\n}"))
        // The same word outside a toolbar (an in-page button) is not a sheet toolbar.
        #expect(!ControlPatternScanner.violates(.sheetToolbar, source: "Button(\"Kaydet\") { save() }"))
        #expect(
            !ControlPatternScanner.violates(
                .sheetToolbar,
                source: "List {}.inkSheet(\"Yeni hedef\", confirm: .create, onConfirm: save)"))
    }

    @Test func commentsAndStringsDoNotConfuseBlockMatching() {
        let source = """
            .toolbar {
                Text("}")  // } closes nothing
                SearchButton()
            }
            """
        #expect(ControlPatternScanner.violates(.toolbarSearch, source: source))
        #expect(ControlPatternScanner.strippingComments("a // b\n/* c */d") == "a \nd")
        #expect(ControlPatternScanner.strippingComments("\"http://x\" // y") == "\"http://x\" ")
    }

    // MARK: - Files

    static let scannedFolders = ["App/Screens", "App/Navigation", "App/Mac"]

    private static func screenSwiftFiles() throws -> [String] {
        let root = repositoryRoot()
        var files: [String] = []
        for folder in scannedFolders {
            let enumerator = FileManager.default.enumerator(
                at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles])
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                files.append(url.path.replacingOccurrences(of: root.path + "/", with: ""))
            }
        }
        return files.sorted()
    }

    private static func read(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
    }

    private static func repositoryRoot(filePath: String = #filePath) -> URL {
        URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

/// Small source scanner: comment stripping, balanced blocks, modifier chains.
enum ControlPatternScanner {
    typealias Rule = ControlPatternUsageTests.Rule

    static let sheetWords = ["Kapat", "Vazgeç", "Kaydet", "Oluştur", "Bitti"]

    static func violates(_ rule: Rule, source raw: String) -> Bool {
        let source = strippingComments(raw)
        switch rule {
        case .segmentedPicker:
            return matches(source, #"\.pickerStyle\(\s*\.segmented\s*\)"#)
        case .menuPicker:
            return matches(source, #"\.pickerStyle\(\s*\.menu\s*\)"#)
        case .roundedBorderField:
            return matches(source, #"\.textFieldStyle\(\s*\.roundedBorder\s*\)"#)
        case .doneButton:
            return matches(source, #"\bButton\(\s*"Bitti""#)
        case .unstyledPicker:
            return pickerExpressions(in: source).contains { !$0.contains(".pickerStyle(") }
        case .toolbarSearch:
            return toolbarBlocks(in: source).contains { $0.contains("SearchButton(") }
        case .sheetToolbar:
            if matches(source, #"ToolbarItem\(\s*placement:\s*\.(cancellationAction|confirmationAction)\b"#) {
                return true
            }
            let words = sheetWords.joined(separator: "|")
            return toolbarBlocks(in: source).contains {
                matches($0, #"\bButton\(\s*"(?:"# + words + #")""#)
            }
        }
    }

    /// Removes `//` and `/* */` comments, keeping string literals intact.
    static func strippingComments(_ source: String) -> String {
        var out = ""
        var index = source.startIndex
        var inString = false
        while index < source.endIndex {
            let char = source[index]
            let next = source.index(after: index)
            if inString {
                out.append(char)
                if char == "\\", next < source.endIndex {
                    out.append(source[next])
                    index = source.index(after: next)
                    continue
                }
                if char == "\"" { inString = false }
                index = next
                continue
            }
            if char == "\"" {
                inString = true
                out.append(char)
                index = next
                continue
            }
            if char == "/", next < source.endIndex, source[next] == "/" {
                while index < source.endIndex, source[index] != "\n" { index = source.index(after: index) }
                continue
            }
            if char == "/", next < source.endIndex, source[next] == "*" {
                if let end = source.range(of: "*/", range: next..<source.endIndex) {
                    index = end.upperBound
                } else {
                    index = source.endIndex
                }
                continue
            }
            out.append(char)
            index = next
        }
        return out
    }

    /// Every `Picker(…)` call with its trailing closures and its modifier chain.
    /// `DatePicker(`, `ColorPicker(`, `PhotosPicker(`, `EntityTypePicker(` do not match.
    static func pickerExpressions(in source: String) -> [String] {
        var result: [String] = []
        var searchStart = source.startIndex
        while let match = source.range(
            of: #"(?<![A-Za-z0-9_])Picker\("#, options: .regularExpression,
            range: searchStart..<source.endIndex)
        {
            let open = source.index(before: match.upperBound)
            guard let afterCall = endOfBalanced(source, from: open, open: "(", close: ")") else { break }
            let end = endOfChain(source, from: afterCall)
            result.append(String(source[match.lowerBound..<end]))
            searchStart = afterCall
        }
        return result
    }

    /// Bodies of `.toolbar { … }`, `.toolbar(…) { … }` and `ToolbarItem…(…) { … }`.
    static func toolbarBlocks(in source: String) -> [String] {
        var result: [String] = []
        var searchStart = source.startIndex
        while let match = source.range(
            of: #"(?:\.toolbar\b(?!\()|\.toolbar\((?!\.|removing)|\bToolbarItem(?:Group)?\()"#,
            options: .regularExpression, range: searchStart..<source.endIndex)
        {
            var cursor = match.upperBound
            if source[source.index(before: cursor)] == "(" {
                guard
                    let afterArgs = endOfBalanced(
                        source, from: source.index(before: cursor), open: "(", close: ")")
                else { break }
                cursor = afterArgs
            }
            cursor = skippingWhitespace(source, from: cursor)
            if cursor < source.endIndex, source[cursor] == "{",
                let end = endOfBalanced(source, from: cursor, open: "{", close: "}")
            {
                result.append(String(source[cursor..<end]))
            }
            searchStart = match.upperBound
        }
        return result
    }

    /// Index just past the delimiter that closes the one at `start` (string-literal aware).
    static func endOfBalanced(
        _ source: String, from start: String.Index, open: Character, close: Character
    ) -> String.Index? {
        var depth = 0
        var index = start
        var inString = false
        while index < source.endIndex {
            let char = source[index]
            if inString {
                if char == "\\" {
                    index = source.index(after: index)
                    if index < source.endIndex { index = source.index(after: index) }
                    continue
                }
                if char == "\"" { inString = false }
            } else if char == "\"" {
                inString = true
            } else if char == open {
                depth += 1
            } else if char == close {
                depth -= 1
                if depth == 0 { return source.index(after: index) }
            }
            index = source.index(after: index)
        }
        return nil
    }

    /// Consumes trailing closures (`{ … }`, `label: { … }`), `.modifier(…) { … }` links and
    /// `#if` lines after a call, returning where the expression ends.
    static func endOfChain(_ source: String, from start: String.Index) -> String.Index {
        var end = start
        var cursor = start
        while true {
            cursor = skippingWhitespace(source, from: cursor)
            guard cursor < source.endIndex else { return end }
            let rest = source[cursor...]
            if rest.hasPrefix("#if") || rest.hasPrefix("#else") || rest.hasPrefix("#endif") {
                cursor = source[cursor...].firstIndex(of: "\n") ?? source.endIndex
                continue
            }
            if source[cursor] == "{" {
                guard let next = endOfBalanced(source, from: cursor, open: "{", close: "}") else { return end }
                cursor = next
                end = next
                continue
            }
            if let label = rest.range(of: #"^[a-zA-Z_]+:\s*\{"#, options: .regularExpression) {
                let brace = source.index(before: label.upperBound)
                guard let next = endOfBalanced(source, from: brace, open: "{", close: "}") else { return end }
                cursor = next
                end = next
                continue
            }
            if let name = rest.range(of: #"^\.[a-zA-Z_][a-zA-Z0-9_]*"#, options: .regularExpression) {
                cursor = name.upperBound
                if cursor < source.endIndex, source[cursor] == "(" {
                    guard let next = endOfBalanced(source, from: cursor, open: "(", close: ")") else { return end }
                    cursor = next
                }
                end = cursor
                continue
            }
            return end
        }
    }

    private static func skippingWhitespace(_ source: String, from start: String.Index) -> String.Index {
        var index = start
        while index < source.endIndex, source[index].isWhitespace { index = source.index(after: index) }
        return index
    }

    private static func matches(_ source: String, _ pattern: String) -> Bool {
        source.range(of: pattern, options: .regularExpression) != nil
    }
}
