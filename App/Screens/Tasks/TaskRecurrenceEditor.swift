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
    var body: some View {
        Form {
            if model.canEditRecurrence {
                Picker("Tekrar", selection: $choice) {
                    Text("Yok").tag(Choice.none)
                    Text("Her gün").tag(Choice.day)
                    Text("Her hafta").tag(Choice.week)
                    Text("Her ay").tag(Choice.month)
                    Text("Her yıl").tag(Choice.year)
                    Text("Her N gün").tag(Choice.days)
                    Text("Haftanın günü").tag(Choice.weekday)
                }
                if choice == .weekday {
                    Picker("Gün", selection: $weekday) {
                        ForEach(0..<7, id: \.self) { day in Text(TaskRecurrence.weekdayTitle(day)).tag(day) }
                    }
                } else if choice != .none {
                    Stepper("Aralık: \(count)", value: $count, in: 1...9999)
                }
                if choice != .none { Toggle("Tamamlanınca hesapla", isOn: $whenDone) }
            } else {
                Text("Tanınmayan tekrar")
                    .font(.ink.content)
                    .foregroundStyle(.ink.text)
                Text("Bu tekrar kuralı uygulamada tanınmıyor. Değiştirmek için dosyada düzenle.")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
            }
            if let error = model.errorText {
                InfoBand(kind: .error, verbatim: error)
            }
        }
        .navigationTitle("Tekrar").formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .inkSurface(bordered: false, cornerRadius: 0)
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Kapat") { dismiss() }
                    .buttonStyle(InkTextButtonStyle())
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Kaydet") {
                    Task { if await model.setRecurrence(recurrence), model.errorText == nil { dismiss() } }
                }
                .buttonStyle(InkPrimaryButtonStyle())
                .disabled(!model.canSave || !model.canEditRecurrence)
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
