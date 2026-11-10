import Summaries
import SwiftUI

#if os(macOS)
    /// Mac Today desk shell values handed to ``DayView``. DayView draws the hour grid and the panel
    /// from its own loaded day, goals and tasks; the shell only adds what DayView does not load.
    /// Present means desk mode: DayView leaves its "Günü kapat" to the panel and its quick-entry
    /// bar to the shell.
    struct TodayDeskChrome {
        /// The detail column fits the 300 pt right panel; otherwise its sections fold under the grid.
        var showsPanel: Bool
        /// "Bu gün geçmişte" entry, loaded by the shell.
        var onThisDay: OnThisDay?
    }

    private struct TodayDeskChromeKey: EnvironmentKey {
        static let defaultValue: TodayDeskChrome? = nil
    }

    extension EnvironmentValues {
        var todayDeskChrome: TodayDeskChrome? {
            get { self[TodayDeskChromeKey.self] }
            set { self[TodayDeskChromeKey.self] = newValue }
        }
    }
#endif
