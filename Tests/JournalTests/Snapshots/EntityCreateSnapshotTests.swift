#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Journal

    @MainActor @Suite("Entity create snapshots", .serialized)
    struct EntityCreateSnapshotTests {
        @Test func light() async throws { try await run("light") }

        private func run(
            _ name: String, scheme: SnapshotColorScheme = .light, type: SnapshotDynamicType = .medium
        ) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            await SnapshotHost.assertView(
                colorScheme: scheme, dynamicType: type, increaseContrast: false, named: name,
                store: context.store, size: CGSize(width: snapshotCanvasSize.width, height: 520),
                testName: "entityCreate", file: #filePath, line: #line
            ) {
                NavigationStack {
                    EntityCreateSheet(store: context.store, kind: .person) { _ in }
                }
                .environment(\.locale, snapshotLocale)
                .environment(\.timeZone, snapshotTimeZone)
            }
        }
    }
#endif
