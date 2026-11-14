#if os(iOS)
    import SwiftUI
    import Testing
    @testable import Kenet

    /// Quick alias sheet (filled, error band, large text) and the person page's alias row at an
    /// accessibility text size, where the names move under the row's title.
    @MainActor @Suite("Entity alias snapshots")
    struct EntityAliasSnapshotTests {
        private static let person = "people/Deniz Arıkan.md"

        @Test(arguments: ["sheetLight", "sheetDark", "sheetErrorLight", "sheetAX3", "pageRowAX3"])
        func alias(_ name: String) async throws {
            let context = try await EntityRelationsModelTests.context()
            defer { context.clean() }
            let store = context.store
            let detail = EntityDetailModel(store: store, path: Self.person)
            await detail.load()
            let isPage = name == "pageRowAX3"
            for alias in ["Deniz", "Denizciğim"] + (isPage ? ["D. Arıkan", "Arıkan Bey"] : []) {
                #expect(await detail.addAlias(alias, name: "Deniz Arıkan"))
            }
            var draft = ""
            if name == "sheetErrorLight" {
                draft = "deniz arıkan"
                #expect(await detail.addAlias(draft, name: "Deniz Arıkan") == false)
                #expect(detail.aliasErrorText != nil)
            }
            let entity = try #require(store.content.entities.first { $0.id == Self.person })
            let isAX3 = name.hasSuffix("AX3")
            let ready = AliasPageReadyBox()
            await SnapshotHost.assertView(
                colorScheme: name == "sheetDark" ? .dark : .light,
                dynamicType: isAX3 ? .accessibility3 : .medium,
                increaseContrast: false, named: name, store: store,
                size: CGSize(width: 390, height: isPage ? 1200 : (isAX3 ? 900 : 560)),
                isReady: { !isPage || ready.isReady },
                testName: "alias",
                content: {
                    Group {
                        if isPage {
                            NavigationStack { EntityView(store: store, entity: entity) }
                        } else {
                            // The sheet owns its `NavigationStack`.
                            EntityAliasSheet(model: detail, name: entity.name, draft: draft)
                        }
                    }
                    .environment(IntentNavigation())
                    .environment(\.locale, snapshotLocale)
                    .environment(\.timeZone, snapshotTimeZone)
                    .environment(\.openSearch, .nothing)
                    .onPreferenceChange(ImportantDatesReadyKey.self) { ready.isReady = $0 }
                })
        }
    }

    @MainActor private final class AliasPageReadyBox {
        var isReady = false
    }
#endif
