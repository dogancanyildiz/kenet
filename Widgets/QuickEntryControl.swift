import AppIntents
import SwiftUI
import WidgetKit

struct QuickEntryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "QuickEntryControl") {
            ControlWidgetButton(action: OpenQuickEntryIntent()) {
                Label("widget.write.open", systemImage: "square.and.pencil")
            }
        }
        .displayName("widget.write.open")
        .description("widget.write.description")
    }
}

/// Extension process: the foreground app performs the navigation.
extension OpenQuickEntryIntent {
    func perform() async throws -> some IntentResult { .result() }
}
