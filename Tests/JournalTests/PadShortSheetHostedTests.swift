#if os(iOS)
    import Observation
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(2)), .enabled("iPad simulator only", PadSnapshotHost.isPadSimulator))
    struct PadShortSheetHostedTests {
        @Test(arguments: PadShortSheetCase.allCases)
        func shortEditorFitsItsContent(_ editor: PadShortSheetCase) async throws {
            try await PadSnapshotHost.assertWindow(
                named: editor.rawValue, testName: "hosted", canvas: .pad13Portrait,
                presentsSheet: true, shellKind: .split,
                inspect: { host in
                    guard let sheet = host.presentedViewController else {
                        Issue.record("Short editor was never presented")
                        return
                    }
                    let size = sheet.view.bounds.size
                    #expect(size.width >= 480, "Form width: \(size)")
                    #expect(size.height > 100 && size.height < 480, "Short editor height: \(size)")
                    if editor == .taskDateLight {
                        #expect(size.height < 360, "The date editor must drop the old minimum: \(size)")
                        Self.expectDateContentFits(sheet)
                    }
                }, draws: false,
                content: { scene in
                    AnyView(PadShortSheetContent(editor: try await editor.editor(store: scene.store)))
                })
        }

        @Test func taskDetailKeepsCommonIdealHeight() async throws {
            try await PadSnapshotHost.assertWindow(
                named: "taskDetail", testName: "hosted", canvas: .pad13Portrait,
                presentsSheet: true, shellKind: .split,
                inspect: { host in
                    let sheet = host.presentedViewController
                    #expect((sheet?.view.bounds.height ?? 0) >= 480)
                    #expect(sheet.map { ChromeSheetsDuoHost.hasVisibleRowOrField(in: $0.view) } ?? false)
                }, draws: false,
                content: { scene in
                    let tasks = TasksModel(store: scene.store, today: { snapshotDay })
                    tasks.section = .kanban
                    let row = try #require(try await scene.store.allTasks().first { !$0.isClosed })
                    return AnyView(
                        NavigationStack { KanbanView(tasks: tasks, showsFilters: true, selection: row) }
                            .frame(width: 600)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .inkPage())
                })
        }

        private static func expectDateContentFits(_ sheet: UIViewController) {
            // ScrollView's content size measures the manşet, picker and action row independently
            // of the sheet's viewport. Navigation chrome is accounted for by its adjusted inset.
            guard
                let scroll = ChromeSheetsDuoHost.views(UIScrollView.self, under: sheet.view).first(where: {
                    $0.contentSize.height > 0 && $0.bounds.width >= 400
                })
            else {
                Issue.record("Date editor has no measurable scroll content")
                return
            }
            let contentHeight =
                scroll.contentSize.height + scroll.adjustedContentInset.top + scroll.adjustedContentInset.bottom
            #expect(scroll.bounds.height >= contentHeight - 4, "Date content must fit without scrolling")
            #expect(scroll.bounds.height <= contentHeight + 40, "Date editor has excess blank space")
        }
    }

    @MainActor @Observable private final class DatePickerState {
        var graphical = false
    }

    private struct ResizableDateEditor: View {
        let model: TaskEditorModel
        let state: DatePickerState

        var body: some View {
            // Keep one editor identity; only the inherited DatePickerStyle changes.
            TaskDateEditor(model: model)
                .datePickerStyle(ResizingDatePickerStyle(graphical: state.graphical))
        }
    }

    private struct ResizingDatePickerStyle: DatePickerStyle {
        let graphical: Bool

        @ViewBuilder func makeBody(configuration: Configuration) -> some View {
            if graphical {
                GraphicalDatePickerStyle().makeBody(configuration: configuration)
            } else {
                CompactDatePickerStyle().makeBody(configuration: configuration)
            }
        }
    }

    /// Async inspection for a content change while presented. Uses the same canvas and scene
    /// gate as PadSnapshotHost; no capture and no new UIKit view type.
    @MainActor private enum DateSheetWindow {
        private static var retired: UIWindow?

        static func withWindow<V: View>(
            _ root: V, inspect: @MainActor (UIHostingController<AnyView>) async throws -> Void
        ) async throws {
            var failure: (any Error)?
            await SnapshotHostGate.exclusive {
                guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
                    Issue.record("Date sheet needs the test host's window scene")
                    return
                }
                let animated = UIView.areAnimationsEnabled
                UIView.setAnimationsEnabled(false)
                defer { UIView.setAnimationsEnabled(animated) }
                let host = UIHostingController(rootView: AnyView(root))
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(origin: .zero, size: ShellCanvas.pad13Portrait.size)
                window.traitOverrides.horizontalSizeClass = .regular
                window.traitOverrides.verticalSizeClass = .regular
                window.traitOverrides.preferredContentSizeCategory = .medium
                window.overrideUserInterfaceStyle = .light
                ShellCanvas.pad13Portrait.applySizeClasses(to: host)
                window.rootViewController = host
                window.makeKeyAndVisible()
                await settle(host)
                do { try await inspect(host) } catch { failure = error }
                host.presentedViewController?.dismiss(animated: false)
                await settle(host)
                window.isHidden = true
                window.rootViewController = nil
                window.windowScene = nil
                retired = window
            }
            if let failure { throw failure }
        }

        static func settle(_ host: UIViewController) async {
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(50))
                host.view.layoutIfNeeded()
                host.presentedViewController?.view.layoutIfNeeded()
            }
        }
    }
#endif
