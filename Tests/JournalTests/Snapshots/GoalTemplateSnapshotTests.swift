#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

    @MainActor @Suite("Goal template snapshots", .serialized)
    struct GoalTemplateSnapshotTests {
        @Test func sheetLight() async throws { try await run("sheetLight") }
        @Test func sheetDark() async throws { try await run("sheetDark", scheme: .dark) }
        @Test func sheetAX3() async throws { try await run("sheetAX3", type: .accessibility3) }
        @Test func filteredWater() async throws { try await run("filteredWater", query: "su") }
        @Test func noMatches() async throws { try await run("noMatches", query: "xyz") }
        @Test func selectedWater() async throws { try await run("selectedWater", selected: true) }
        @Test func regularSheet() async throws { try await run("regularSheet", regular: true) }

        @Test(arguments: GoalTemplate.all)
        func templateSymbolsExist(_ template: GoalTemplate) {
            #expect(UIImage(systemName: template.symbol) != nil, "\(template.id): \(template.symbol)")
        }

        private func run(
            _ name: String, scheme: SnapshotColorScheme = .light,
            type: SnapshotDynamicType = .medium, query: String = "", selected: Bool = false,
            regular: Bool = false
        ) async throws {
            let context = try TaskTestContext()
            defer { context.clean() }
            await context.start()
            let model = GoalCreationModel(store: context.store)
            model.name = query
            if selected {
                let water = try #require(GoalTemplate.all.first { $0.id == "water" })
                model.apply(water, locale: snapshotLocale)
            }
            await SnapshotHost.assertView(
                colorScheme: scheme, dynamicType: type, increaseContrast: false,
                named: name, store: context.store,
                shell: regular ? .pad11Portrait : .phone,
                size: regular ? CGSize(width: 480, height: 520) : nil,
                testName: "goalTemplate", file: #filePath, line: #line
            ) {
                NavigationStack { GoalCreationView(model: model) }
                    .environment(\.locale, snapshotLocale)
                    .environment(\.timeZone, snapshotTimeZone)
                    .environment(\.openSearch, {})
            }
        }
    }
#endif
