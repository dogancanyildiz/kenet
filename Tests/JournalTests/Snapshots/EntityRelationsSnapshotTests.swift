#if os(iOS)
    import SwiftUI
    import Testing
    @testable import Journal

    @MainActor @Suite("Entity relations snapshots")
    struct EntityRelationsSnapshotTests {
        @Test(arguments: ["sectionLight", "sectionDark", "sectionAX3", "sheetLight"])
        func relations(_ name: String) async throws {
            let context = try await EntityRelationsModelTests.context()
            defer { context.clean() }
            let model = EntityRelationsModel(store: context.store, path: EntityRelationsModelTests.person)
            await model.load()
            #expect(model.rows.count == 4)
            await SnapshotHost.assertView(
                colorScheme: name == "sectionDark" ? .dark : .light,
                dynamicType: name == "sectionAX3" ? .accessibility3 : .medium,
                increaseContrast: false, named: name, store: context.store,
                size: name == "sectionAX3" ? CGSize(width: 390, height: 1200) : snapshotCanvasSize,
                testName: "relations"
            ) {
                Group {
                    if name == "sheetLight" {
                        EntityRelationSheet(model: model)
                    } else {
                        NavigationStack {
                            List { EntityRelationsSection(model: model) }
                                .listStyle(.plain).inkPage().inkPageScrollColumn()
                        }
                    }
                }
                .environment(\.locale, snapshotLocale)
                .environment(\.openSearch, {})
            }
        }
    }
#endif
