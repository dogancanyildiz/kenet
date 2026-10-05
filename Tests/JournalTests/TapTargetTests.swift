import Foundation
import Testing

/// Touch targets on iPhone must be at least 44×44 pt (HIG). These tests lock the shared
/// modifier and the views that were found below that size in the Stage 8 audit.
///
/// Hit-frame measurement via `UIHostingController` belongs with the upcoming XCUITest /
/// accessibility audit job. Until then these checks require the modifier to sit on the
/// **button label** (the placement that actually expands the control's hit area on iOS).
struct TapTargetTests {
    @Test func tapTargetModifierEnforcesFixedFortyFourPointMinimum() throws {
        let source = try Self.read("App/Support/TapTarget.swift")
        #expect(source.contains("static let minimumLength: CGFloat = 44"))
        #expect(source.contains("frame(minWidth:"))
        #expect(source.contains("minHeight:"))
        #expect(source.contains("contentShape(Rectangle())"))
        #expect(source.contains("os(iOS)"), "Mac pointer targets must stay a no-op")
        #expect(
            !source.contains("@ScaledMetric"),
            "44 pt floor must stay fixed; ScaledMetric grows past 100 pt at AX5")
        #expect(
            source.contains("Button label") || source.contains("button label"),
            "docs must say the modifier belongs on the label, not outside the Button")
    }

    @Test(arguments: [
        "App/Screens/Today/QuickEntryPlaceholder.swift",
        "App/Screens/Today/QuickEntryTaskControls.swift",
        "App/Screens/Today/DayTaskView.swift",
        "App/Screens/Days/DaysCalendarView.swift",
        "App/Screens/Summaries/SummariesView.swift",
        "App/Screens/Tasks/Timeline/TaskTimelineView.swift",
        "App/Screens/Graph/GraphCanvas.swift",
    ])
    func listedControlsApplyTapTargetInsideButton(_ path: String) throws {
        let source = try Self.read(path)
        #expect(source.contains(".tapTarget()"), "\(path) must expand iOS touch targets to 44 pt")
        // frame + contentShape outside a Button only pads layout; the button hit area stays
        // the label's bounds. `.buttonStyle` is always applied to the Button, so tapTarget
        // after it is outside.
        #expect(
            !Self.matches(source, #"\.buttonStyle\([^\n]+\)\s*\n\s*\.tapTarget\(\)"#),
            "\(path): .tapTarget() after .buttonStyle is outside the button")
        #expect(
            !Self.matches(
                source,
                #"Button\("[^"]+"(?:,\s*systemImage:\s*"[^"]+")?\)\s*\{[^}]*\}\s*\n(?:\s*\.[^\n]+\n)*\s*\.tapTarget\(\)"#),
            "\(path): .tapTarget() must sit on the label, not after Button(\"…\") { }")
        #expect(
            Self.tapTargetIsInsideLabel(source),
            "\(path): every .tapTarget() must appear inside a label: { … } (or Label / Image label content)")
    }

    @Test func heatmapKeepsDenseGridWithoutTapFloor() throws {
        let source = try Self.read("App/Screens/Goals/GoalHeatmap.swift")
        #expect(
            !source.contains(".tapTarget()"),
            "18 pt heatmap cells must stay a dense grid; Stage 9 redesign owns the hit area")
        #expect(source.contains("frame(height: 18)"))
    }

    @Test func quickEntryReflowsForLargeDynamicType() throws {
        let source = try Self.read("App/Screens/Today/QuickEntryPlaceholder.swift")
        #expect(source.contains("ViewThatFits"), "large Dynamic Type must stack the entry row")
    }

    @Test func onboardingScrollsForLargeDynamicType() throws {
        let source = try Self.read("App/Screens/Onboarding/OnboardingView.swift")
        #expect(source.contains("ScrollView"), "onboarding must remain reachable at large text sizes")
    }

    @Test func graphNodeHitRadiusMeetsTapTargetDiameter() throws {
        let source = try Self.read("App/Screens/Graph/GraphCanvas.swift")
        #expect(
            source.contains("TapTarget.minimumLength / 2"),
            "node hit radius must be at least half of the 44 pt minimum")
    }

    @Test func dayTaskRowGestureComesAfterHitShape() throws {
        let source = try Self.read("App/Screens/Today/DayTaskView.swift")
        let shape = try #require(source.range(of: "contentShape(Rectangle())"))
        let gesture = try #require(source.range(of: ".onTapGesture"))
        #expect(
            shape.lowerBound < gesture.lowerBound,
            "contentShape / tapTarget must precede onTapGesture or the row won't receive taps")
    }

    /// Each `.tapTarget()` must fall between a `label:` / `Button(action:` label closure and
    /// its matching close, or ride on inline label content (`Label` / `Image` / `Text` /
    /// `Group` / `HStack` / `VStack`) that itself sits in that closure.
    private static func tapTargetIsInsideLabel(_ source: String) -> Bool {
        let needle = ".tapTarget()"
        var searchStart = source.startIndex
        while let range = source.range(of: needle, range: searchStart..<source.endIndex) {
            let before = source[source.startIndex..<range.lowerBound]
            // Nearest enclosing `label:` or `Button(action:` … `{` wins over a bare outer Button.
            let labelIdx = before.range(of: "label:", options: .backwards)?.lowerBound
            let actionIdx = before.range(of: "Button(action:", options: .backwards)?.lowerBound
            let opener: String.Index?
            if let labelIdx, let actionIdx {
                opener = max(labelIdx, actionIdx)
            } else {
                opener = labelIdx ?? actionIdx
            }
            guard let opener else { return false }
            let between = source[opener..<range.lowerBound]
            // The tapTarget must still be inside that label closure: more `{` than `}` since opener.
            let opens = between.filter { $0 == "{" }.count
            let closes = between.filter { $0 == "}" }.count
            if opens <= closes { return false }
            searchStart = range.upperBound
        }
        return source.contains(needle)
    }

    private static func matches(_ source: String, _ pattern: String) -> Bool {
        source.range(of: pattern, options: .regularExpression) != nil
    }

    private static func read(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
