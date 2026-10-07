import SwiftUI

struct TimelineDateSelection: Identifiable {
    let row: TaskRow
    let edge: TimelineDates.Edge
    let root: URL?
    var id: String { row.id + (edge == .start ? ":start" : ":due") }
}

struct TimelineDateEditor: View {
    let model: TimelineModel
    let selection: TimelineDateSelection
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    private var title: LocalizedStringKey { selection.edge == .start ? "Başlangıç tarihi" : "Bitiş tarihi" }

    /// Closing sheet: the picker's own buttons write the date and dismiss, so the toolbar
    /// only offers "Kapat".
    var body: some View {
        InkSheetScaffold(
            title, onClose: { if !isSaving { dismiss() } },
            content: {
                TaskDatePicker(
                    current: selection.edge == .start ? selection.row.start : selection.row.due, isOnPage: true
                ) { date in
                    guard let dates = TimelineDates(selection.row).setting(selection.edge, to: date) else {
                        model.rejectRange()
                        return
                    }
                    let root = selection.root
                    isSaving = true
                    Task {
                        let saved = await model.save(selection.row, dates: dates, root: root)
                        isSaving = false
                        if saved { dismiss() }
                    }
                }.disabled(isSaving || !model.store.canAddEvent)
                if let error = model.errorText {
                    InfoBand(kind: .error, verbatim: error)
                }
            })
    }
}

struct TimelineTaskMenu: View {
    let edit: (TimelineDates.Edge) -> Void
    var body: some View {
        Button("Başlangıç tarihini değiştir", systemImage: "calendar.badge.clock") { edit(.start) }
        Button("Bitiş tarihini değiştir", systemImage: "calendar") { edit(.due) }
    }
}
