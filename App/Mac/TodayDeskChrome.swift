import SwiftUI

#if os(macOS)
    /// Mac Today desk chrome injected into ``DayView``: hour grid, folded panel sections, and
    /// which DayView chrome the shell already draws (close day, quick entry).
    struct TodayDeskChrome {
        /// Hour-column timeline inserted into Today's scroll content.
        var hourGrid: AnyView
        /// Panel sections drawn under the grid when the right panel is folded away.
        var foldedPanel: AnyView?
        /// DayView omits its own "Günü kapat" (the panel or folded block owns it).
        var suppressCloseDay: Bool
        /// DayView omits its bottom quick-entry bar (the desk column owns it).
        var suppressQuickEntry: Bool
    }

    private struct TodayDeskChromeKey: EnvironmentKey {
        // AnyView slots are MainActor UI values; EnvironmentKey requires a static default.
        nonisolated(unsafe) static let defaultValue: TodayDeskChrome? = nil
    }

    extension EnvironmentValues {
        var todayDeskChrome: TodayDeskChrome? {
            get { self[TodayDeskChromeKey.self] }
            set { self[TodayDeskChromeKey.self] = newValue }
        }
    }
#endif
