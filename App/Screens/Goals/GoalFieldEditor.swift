import GoalTracking
import SwiftUI

enum GoalEditableField: String, Identifiable {
    case name, period, kind, target, unit
    var id: Self { self }
    var title: String {
        switch self {
        case .name: String(localized: "Ad")
        case .period: String(localized: "Dönem")
        case .kind: String(localized: "Tür")
        case .target: String(localized: "Hedef miktar")
        case .unit: String(localized: "Birim")
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
                    Text(verbatim: GoalPeriod.day.title).tag("day")
                    Text(verbatim: GoalPeriod.week.title).tag("week")
                    Text(verbatim: GoalPeriod.year.title).tag("year")
                }
            } else if field == .kind {
                Picker(field.title, selection: $text) {
                    Text(verbatim: GoalKind.boolean.title).tag("boolean")
                    Text(verbatim: GoalKind.number.title).tag("number")
                }
                Text("Tür değişikliği geçmiş kayıtları dönüştürmez.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
            } else if field == .unit {
                TextField("Birim (isteğe bağlı)", text: $text)
                    .font(.ink.content)
            } else {
                TextField(field.title, text: $text)
                    .font(field == .name ? .ink.content : .ink.value)
            }
            if let error = model.errorText {
                InfoBand(kind: .error, verbatim: error)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.ink.surface)
        .disabled(model.isWriting || isSaved)
        .navigationTitle(field.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Kapat") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Kaydet") {
                    Task {
                        isSaved = await model.set(field.rawValue, text: text)
                        if isSaved && model.errorText == nil { dismiss() }
                    }
                }
                .disabled(!model.canEdit || isSaved)
            }
        }
        .frame(minWidth: 300, minHeight: 200)
    }
}
