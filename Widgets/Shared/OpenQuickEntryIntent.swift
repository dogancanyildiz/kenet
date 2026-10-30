import AppIntents

/// Opens the existing Today composer; never writes from the extension.
struct OpenQuickEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "widget.write.open"
    static let openAppWhenRun = true
}
