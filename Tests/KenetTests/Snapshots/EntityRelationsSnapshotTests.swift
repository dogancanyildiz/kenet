#if os(iOS)
    import SwiftUI
    import Testing
    @testable import Kenet

    @MainActor @Suite("Entity relations snapshots")
    struct EntityRelationsSnapshotTests {
        @Test(arguments: ["sectionLight", "sectionDark", "sectionAX3", "sheetLight"])
        func relations(_ name: String) async throws {
            let context = try await EntityRelationsModelTests.context()
            defer { context.clean() }
            let model = EntityRelationsModel(store: context.store, path: EntityRelationsModelTests.person)
            await model.load()
            #expect(model.rows.count == 3)
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
                .environment(\.openSearch, .nothing)
            }
        }

        /// A page other pages link to and that links to nobody: its rows are the other names alone,
        /// with the source's label after the name.
        @Test func incomingOnly() async throws {
            let context = try await EntityRelationsModelTests.context()
            defer { context.clean() }
            let place = "places/Liman Ofis.md"
            try await context.store.addRelation(
                from: EntityRelationsModelTests.person, to: "/places/Liman Ofis", label: "iş yeri")
            try await context.store.addRelation(from: "people/Selin Korkmaz.md", to: "/places/Liman Ofis", label: nil)
            let model = EntityRelationsModel(store: context.store, path: place)
            await model.load()
            #expect(model.rows.map(\.isOutgoing) == [false, false])
            #expect(Set(model.rows.map(\.name)) == ["Deniz Arıkan", "Selin Korkmaz"])
            await SnapshotHost.assertView(
                colorScheme: .light, dynamicType: .medium, increaseContrast: false, named: "incomingLight",
                store: context.store, testName: "relations"
            ) {
                NavigationStack {
                    List { EntityRelationsSection(model: model) }
                        .listStyle(.plain).inkPage().inkPageScrollColumn()
                }
                .environment(\.locale, snapshotLocale)
                .environment(\.openSearch, .nothing)
            }
        }
    }
#endif
