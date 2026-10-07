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
    private var isValid: Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .name:
            return !clean.isEmpty && !clean.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        case .period:
            return GoalPeriod(rawValue: clean) != nil
        case .kind:
            return GoalKind(rawValue: clean) != nil
        case .target:
            guard let number = GoalValueModel.number(clean), number > 0 else { return false }
            return !clean.lowercased().contains("e")
        case .unit:
            return !clean.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        }
    }

    var body: some View {
        List {
            InkPageTitleRow(verbatim: field.title)
            if field == .period {
                // Three choices right under the manşet: tabs, not a menu.
                InkTabs(
                    selection: $text,
                    items: [GoalPeriod.day, .week, .year].map {
                        InkTabItem(verbatim: $0.title, value: $0.rawValue)
                    },
                    accessibilityLabelPrefix: field.title
                )
                .inkListRow()
            } else if field == .kind {
                InkTabs(
                    selection: $text,
                    items: [GoalKind.boolean, .number].map {
                        InkTabItem(verbatim: $0.title, value: $0.rawValue)
                    },
                    accessibilityLabelPrefix: field.title
                )
                .inkListRow()
                Text("Tür değişikliği geçmiş kayıtları dönüştürmez.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
            } else if field == .unit {
                TextField("Birim (isteğe bağlı)", text: $text)
                    .font(.ink.content)
                    .inkListRow()
            } else {
                TextField(field.title, text: $text)
                    .font(field == .name ? .ink.content : .ink.value)
                    .inkListRow()
            }
            if let error = model.errorText {
                InfoBand(kind: .error, verbatim: error)
                    .inkListRow()
            }
        }
        .listStyle(.plain)
        .disabled(model.isWriting || isSaved)
        .inkSheet(
            verbatim: field.title, isConfirmEnabled: model.canEdit && !isSaved && isValid,
            isBusy: model.isWriting,
            onConfirm: {
                Task {
                    isSaved = await model.set(field.rawValue, text: text)
                    if isSaved && model.errorText == nil { dismiss() }
                }
            }
        )
        .frame(minWidth: 300, minHeight: 200)
    }
}
