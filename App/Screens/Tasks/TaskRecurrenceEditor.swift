import SwiftUI
import VaultFormat

struct TaskRecurrenceEditor: View {
    enum Choice: String, CaseIterable { case none, day, week, month, year, days, weekday }
    @Bindable var model: TaskEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var choice = Choice.none
    @State private var count = 1
    @State private var weekday = 0
    @State private var whenDone = false
    /// Editing sheet: nothing is written until "Kaydet".
    var body: some View {
        List {
            InkPageTitleRow("Tekrar")
            if model.canEditRecurrence {
                InkLabeledMenu(
                    "Tekrar", selection: $choice,
                    options: [
                        InkMenuOption("Yok", value: Choice.none),
                        InkMenuOption("Her gün", value: Choice.day),
                        InkMenuOption("Her hafta", value: Choice.week),
                        InkMenuOption("Her ay", value: Choice.month),
                        InkMenuOption("Her yıl", value: Choice.year),
                        InkMenuOption("Her N gün", value: Choice.days),
                        InkMenuOption("Haftanın günü", value: Choice.weekday),
                    ], identifier: "tasks.recurrence.choice"
                )
                .inkListRow()
                if choice == .weekday {
                    InkLabeledMenu(
                        "Gün", selection: $weekday,
                        options: (0..<7).map { InkMenuOption(TaskRecurrence.weekdayTitle($0), value: $0) },
                        identifier: "tasks.recurrence.weekday"
                    )
                    .inkListRow()
                } else if choice != .none {
                    Stepper("Aralık: \(count)", value: $count, in: 1...9999)
                        .font(.ink.content)
                        .foregroundStyle(.ink.text)
                        .inkListRow()
                }
                if choice != .none {
                    Toggle("Tamamlanınca hesapla", isOn: $whenDone)
                        .font(.ink.content)
                        .foregroundStyle(.ink.text)
                        .inkListRow()
                }
            } else {
                Text("Tanınmayan tekrar")
                    .font(.ink.content)
                    .foregroundStyle(.ink.text)
                    .inkListRow()
                Text("Bu tekrar kuralı uygulamada tanınmıyor. Değiştirmek için dosyada düzenle.")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                    .inkListRow()
            }
            if let error = model.errorText {
                InfoBand(kind: .error, verbatim: error)
                    .inkListRow()
            }
        }
        .listStyle(.plain)
        .inkSheet(
            "Tekrar", isConfirmEnabled: model.canSave && model.canEditRecurrence, isBusy: model.isSaving,
            onConfirm: {
                Task { if await model.setRecurrence(recurrence), model.errorText == nil { dismiss() } }
            }
        )
        .task {
            await model.load()
            if let recurrence = model.target?.recurrence {
                whenDone = recurrence.whenDone
                switch recurrence.frequency {
                case .weekday(let day):
                    choice = .weekday
                    weekday = day
                case .interval(let amount, let unit):
                    count = amount
                    switch unit {
                    case .day: choice = amount == 1 ? .day : .days
                    case .week: choice = .week
                    case .month: choice = .month
                    case .year: choice = .year
                    }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 280)
    }
    private var recurrence: TaskRecurrence? {
        let frequency: TaskRecurrence.Frequency
        switch choice {
        case .none: return nil
        case .weekday: frequency = .weekday(weekday)
        case .day, .days: frequency = .interval(count, .day)
        case .week: frequency = .interval(count, .week)
        case .month: frequency = .interval(count, .month)
        case .year: frequency = .interval(count, .year)
        }
        return TaskRecurrence(frequency: frequency, whenDone: whenDone)
    }
}
