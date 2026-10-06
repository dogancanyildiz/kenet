import SwiftUI
import VaultFormat

struct QuickEntryTaskControls: View {
    @Bindable var model: QuickEntryModel
    @Binding var showsPicker: Bool

    var body: some View {
        if model.mode == .task {
            if let recurrence = model.recurrenceExpression?.recurrence ?? model.taskRecurrence {
                TaskRecurrenceLabel(recurrence: recurrence)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
            }
            Button {
                showsPicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    if let date = model.dueDate {
                        Text(
                            LocalDay.instant(for: date),
                            format: .dateTime.day().month(.abbreviated).weekday(.abbreviated))
                    } else {
                        Text("Tarih ver")
                    }
                    if model.dateIsAssumed { Image(systemName: "questionmark.circle") }
                }
                .font(.ink.meta)
                .foregroundStyle(model.dateIsAssumed ? Color.ink.warning : Color.ink.accent)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.ink.well, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(
                        model.dateIsAssumed ? Color.ink.warning : Color.ink.control,
                        lineWidth: InkStroke.control)
                }
                .tapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                model.dateIsAssumed ? Text("Varsayılan tarih, değiştirmek için dokun") : Text("Görev tarihini değiştir")
            )
            .popover(isPresented: $showsPicker) {
                TaskDatePicker(current: model.dueDate) { date in
                    model.selectDate(date)
                    showsPicker = false
                }
                .presentationCompactAdaptation(.popover)
            }
        }
    }
}
