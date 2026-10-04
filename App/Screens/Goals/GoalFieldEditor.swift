import GoalTracking
import SwiftUI

enum GoalEditableField: String, Identifiable {
    case name, period, kind, target, unit
    var id: Self { self }
    var title: LocalizedStringKey {
        switch self {
        case .name: "Ad"
        case .period: "Dönem"
        case .kind: "Tür"
        case .target: "Hedef miktar"
        case .unit: "Birim (isteğe bağlı)"
        }
    }
}
struct GoalFieldEditor: View {
    let field: GoalEditableField
    @State private var model: GoalDefinitionModel
    @State private var text: String
    @State private var isSaved = false
    @Environment(\.dismiss) private var dismiss
    init(store: IndexStore, goal: GoalDefinition, field: GoalEditableField) {
        self.field = field
        _model = State(initialValue: GoalDefinitionModel(store: store, goal: goal))
        let value: String
        switch field {
        case .name: value = goal.name
        case .period: value = goal.period.rawValue
        case .kind: value = goal.kind.rawValue
        case .target: value = String(goal.target)
        case .unit: value = goal.unit ?? ""
        }
        _text = State(initialValue: value)
    }
    var body: some View {
        Form {
            if field == .period {
                Picker(field.title, selection: $text) {
                    Text(GoalPeriod.day.title).tag("day")
                    Text(GoalPeriod.week.title).tag("week")
                    Text(GoalPeriod.year.title).tag("year")
                }
            } else if field == .kind {
                Picker(field.title, selection: $text) {
                    Text(GoalKind.boolean.title).tag("boolean")
                    Text(GoalKind.number.title).tag("number")
                }
                Text("Tür değişikliği geçmiş kayıtları dönüştürmez.").font(.caption).foregroundStyle(.secondary)
            } else {
                TextField(field.title, text: $text)
            }
            if let error = model.errorText { Text(verbatim: error).foregroundStyle(.secondary) }
        }.formStyle(.grouped).disabled(model.isWriting || isSaved)
            .navigationTitle(field.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        Task {
                            isSaved = await model.set(field.rawValue, text: text)
                            if isSaved && model.errorText == nil { dismiss() }
                        }
                    }.disabled(!model.canEdit || isSaved)
                }
            }.frame(minWidth: 300, minHeight: 200)
    }
}
