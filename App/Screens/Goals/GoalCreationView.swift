import GoalTracking
import SwiftUI

struct GoalCreationView: View {
    @State private var model: GoalCreationModel
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    init(store: IndexStore) { _model = State(initialValue: GoalCreationModel(store: store)) }

    init(model: GoalCreationModel) { _model = State(initialValue: model) }

    @State private var showsAllTemplates = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name, target, unit }

    /// The templates the name matches; the drawing lists the first five ("15 hedeften 5'i").
    private var matchingTemplates: [GoalTemplate] {
        GoalTemplate.all.filter { GoalCreationModel.matches($0, query: model.name, locale: locale) }
    }

    private var templates: [GoalTemplate] {
        let matching = matchingTemplates
        return showsAllTemplates ? matching : Array(matching.prefix(GoalCreationLayout.shownTemplates))
    }

    var body: some View {
        @Bindable var model = model
        List {
            InkPageTitleRow("Yeni hedef")
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Ad")
                    TextField("Ad", text: $model.name)
                        .font(.ink.content)
                        .focused($focusedField, equals: .name)
                        .accessibilityIdentifier("goal.create.name")
                        .modifier(GoalCreationFieldBox(isFocused: focusedField == .name))
                }
                .inkListRow()
            }
            if !templates.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        templatesHeader
                        InkCard(padded: false) {
                            // One stack without the card's row gap: rows sit flush between hairlines.
                            VStack(spacing: 0) {
                                ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                                    if index > 0 { InkCardDivider() }
                                    templateRow(template)
                                        .padding(.horizontal, 12)
                                }
                                if matchingTemplates.count > templates.count {
                                    InkCardDivider()
                                    Button {
                                        showsAllTemplates = true
                                    } label: {
                                        Text("Tümünü göster")
                                            .font(.ink.meta)
                                            .foregroundStyle(Color.ink.accent)
                                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 12)
                                }
                            }
                        }
                    }
                    .inkListRow()
                }
            }
            Section {
                if model.kind != .milestone {
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Dönem")
                        InkTabs(
                            selection: $model.period,
                            items: [GoalPeriod.day, .week, .year].map {
                                InkTabItem(
                                    verbatim: GoalListPresentation.periodChip($0, locale: locale),
                                    value: $0)
                            },
                            identifier: "goal.create.period",
                            accessibilityLabelPrefix: PresentationLocalization.string(
                                localized: "Dönem", locale: locale)
                        )
                    }
                    .inkListRow()
                }
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Tür")
                    InkTabs(
                        selection: $model.kind,
                        items: [GoalKind.boolean, .number, .milestone].map {
                            InkTabItem(
                                verbatim: GoalListPresentation.kindTab($0, locale: locale),
                                value: $0)
                        },
                        identifier: "goal.create.kind",
                        accessibilityLabelPrefix: PresentationLocalization.string(localized: "Tür", locale: locale)
                    )
                }
                .inkListRow()
                if model.kind != .milestone {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("Hedef miktar")
                            TextField("Hedef miktar", text: $model.target)
                                .font(.ink.value)
                                .focused($focusedField, equals: .target)
                                #if os(iOS)
                                    .keyboardType(.decimalPad)
                                #endif
                                .modifier(GoalCreationFieldBox(isFocused: focusedField == .target))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if model.kind == .number {
                            VStack(alignment: .leading, spacing: 6) {
                                fieldLabel("Birim")
                                TextField("Birim (isteğe bağlı)", text: $model.unit)
                                    .font(.ink.content)
                                    .focused($focusedField, equals: .unit)
                                    .modifier(GoalCreationFieldBox(isFocused: focusedField == .unit))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .inkListRow()
                }
            }
            // The key is derived from the name; it trails the form so the choices stay on the first screen.
            Section {
                LabeledContent("Anahtar") {
                    Text(verbatim: model.key)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                }
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .inkListRow()
            }
            if let error = model.errorText {
                Section {
                    InfoBand(kind: .error, verbatim: error)
                        .inkListRow()
                }
            }
        }
        .listStyle(.plain)
        .inkPageScrollColumn()
        .disabled(model.isWriting || model.isSaved)
        .inkSheet(
            "Yeni hedef", confirm: .create, isConfirmEnabled: model.canSave, isBusy: model.isWriting,
            onConfirm: { Task { if await model.save(), model.errorText == nil { dismiss() } } }
        )
        .frame(minWidth: 320, minHeight: 350)
        .task(id: model.store.lastUpdated) { await model.load() }
        // The target is read the way the app's language writes numbers ("7.500" in Turkish).
        .onChange(of: locale, initial: true) { _, locale in model.locale = locale }
    }

    private func fieldLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.ink.meta)
            .foregroundStyle(Color.ink.secondaryText)
            .accessibilityHidden(true)
    }

    private var templatesHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            fieldLabel("Hazır hedefler")
            Spacer(minLength: 8)
            Text("\(GoalTemplate.all.count) hedeften \(Self.shownCount(templates.count, locale: locale))")
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    /// "5'i" in Turkish ("15 hedeften 5'i": third-person possessive with vowel harmony), "5" elsewhere.
    static func shownCount(_ count: Int, locale: Locale) -> String {
        guard TurkishSuffix.isTurkish(locale) else { return count.formatted(.number.locale(locale)) }
        let word = TurkishSuffix.lastSpokenWord(of: count)
        let vowels: [Character: Character] = [
            "a": "ı", "ı": "ı", "e": "i", "i": "i", "o": "u", "u": "u", "ö": "ü", "ü": "ü",
        ]
        let last = word.last { vowels[$0] != nil }
        let vowel = last.flatMap { vowels[$0] } ?? "i"
        let buffer = word.last.map { vowels[$0] != nil } == true ? "s" : ""
        return "\(count)'\(buffer)\(vowel)"
    }

    /// The template name with the typed letters in bold ("**K**itap oku").
    private func highlightedName(_ name: String) -> AttributedString {
        var text = AttributedString(name)
        let query = model.name.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty,
            let range = name.range(
                of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: locale),
            let attributed = Range(NSRange(range, in: name), in: text)
        else { return text }
        text[attributed].inlinePresentationIntent = .stronglyEmphasized
        return text
    }

    private func templateRow(_ template: GoalTemplate) -> some View {
        let selected = model.templateID == template.id
        return Button {
            model.apply(template, locale: locale)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: template.symbol)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.accent)
                    .frame(width: GoalCreationLayout.iconBox, height: GoalCreationLayout.iconBox)
                    .background(
                        RoundedRectangle(cornerRadius: InkCorner.xs, style: .continuous)
                            .fill(Color.ink.accentSoft)
                    )
                    .accessibilityHidden(true)
                Text(highlightedName(template.localizedName(locale: locale)))
                    .font(.ink.content)
                    .foregroundStyle(Color.ink.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(verbatim: template.summary(locale: locale))
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .multilineTextAlignment(.trailing)
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.ink.accent)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("button.goal.template.\(template.id)")
    }
}

private enum GoalCreationLayout {
    /// Templates listed before "Tümünü göster" (drawing: "15 hedeften 5'i").
    static let shownTemplates = 5
    static let iconBox: CGFloat = 32
}

/// The visible text field of the drawing: a filled box, an accent outline while editing.
private struct GoalCreationFieldBox: ViewModifier {
    let isFocused: Bool
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 44
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .frame(minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: InkCorner.sm, style: .continuous)
                    .fill(isFocused ? Color.ink.surface : Color.ink.well)
            )
            .overlay(
                RoundedRectangle(cornerRadius: InkCorner.sm, style: .continuous)
                    .stroke(
                        isFocused ? Color.ink.accent : Color.ink.rule,
                        lineWidth: isFocused ? 1.5 : InkStroke.hairline(scale: displayScale))
            )
    }
}
