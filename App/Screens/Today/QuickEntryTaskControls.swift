import EntityRecognition
import SwiftUI
import VaultFormat

/// The recognized-content controls of the quick entry: in task mode the date control and the
/// recognized expressions, in both modes the recognized names, and a calendar draft's unknown
/// attendees. iPad, Mac and accessibility sizes show them as one row above the capsule
/// (``Part/row``). The two-row iPhone capsule takes them into its top row instead: the date
/// control in the trailing slot (``Part/date``), the chips between it and the mode words
/// (``Part/chips``), so the capsule grows no row while the keyboard is up.
struct QuickEntryTaskControls: View {
    enum Part: Sendable {
        /// Date control and chips together, as one row that scrolls sideways.
        case row
        /// The task date control alone (task mode only).
        case date
        /// The chips without the date control, as a strip that scrolls sideways.
        case chips
    }

    @Bindable var model: QuickEntryModel
    @Binding var showsPicker: Bool
    var part: Part = .row
    /// Called after an attendee chip put its name into the text.
    var onAddAttendee: () -> Void = {}

    @Environment(\.locale) private var locale

    /// Whether ``Part/chips`` has anything to show for this model.
    static func hasChips(_ model: QuickEntryModel) -> Bool {
        let taskChips =
            model.mode == .task
            && (!model.taskExpressions.isEmpty
                || (model.recurrenceExpression == nil && model.taskRecurrence != nil))
        return taskChips || !model.recognizedNames.isEmpty || !model.unknownAttendees.isEmpty
            || !model.suggestedNames.isEmpty
    }

    var body: some View {
        switch part {
        case .date:
            if model.mode == .task { dateButton }
        case .chips:
            if Self.hasChips(model) {
                strip(includesDate: false)
                    .modifier(QuickEntryChipFade())
            }
        case .row:
            if model.mode == .task || Self.hasChips(model) {
                strip(includesDate: true)
            }
        }
    }

    /// It scrolls sideways instead of wrapping or clipping.
    private func strip(includesDate: Bool) -> some View {
        let names = model.recognizedNames
        let attendees = model.unknownAttendees
        let suggested = model.suggestedNames
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if model.mode == .task {
                    if includesDate { dateButton }
                    // A recurrence recognized in the text is one of the chips instead.
                    if model.recurrenceExpression == nil, let recurrence = model.taskRecurrence {
                        TaskRecurrenceLabel(recurrence: recurrence)
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                    }
                    ForEach(model.taskExpressions) { expression in
                        chip(expression)
                    }
                }
                ForEach(names) { name in
                    chip(name)
                }
                ForEach(attendees, id: \.self) { name in
                    attendeeChip(name)
                }
                ForEach(suggested, id: \.self) { name in
                    suggestedNameChip(name)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    /// The whole chip is the button: the name stays in the text as plain words, without a link.
    private func chip(_ name: QuickEntryModel.NameRecognition) -> some View {
        let undo = { model.undoRecognition(name) }
        return Button(action: undo) {
            HStack(spacing: 4) {
                switch name.kind {
                case .person?: Image(systemName: "person")
                case .place?: Image(systemName: "mappin")
                default: EmptyView()
                }
                // An ambiguous name is asked about on sending; the mark says so before.
                Text(verbatim: name.isAmbiguous ? name.spelling + "?" : name.spelling)
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.ink.secondaryText)
            }
            .font(.ink.meta)
            .foregroundStyle(name.isAmbiguous ? Color.ink.warning : Color.ink.text)
            .modifier(QuickEntryPill(stroke: name.isAmbiguous ? Color.ink.warning : Color.ink.control))
            .tapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Tanındı: \(name.spelling)"))
        .accessibilityValue(name.isAmbiguous ? Text("Gönderince hangisi olduğu sorulur") : Text(verbatim: ""))
        .accessibilityHint(Text("Tanımayı geri al"))
        .accessibilityAction(named: Text("Tanımayı geri al"), undo)
    }

    private func attendeeChip(_ name: String) -> some View {
        Button {
            model.addUnknownAttendee(name)
            onAddAttendee()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.ink.secondaryText)
                Text(verbatim: name)
                    .lineLimit(1)
            }
            .font(.ink.meta)
            .foregroundStyle(Color.ink.text)
            .modifier(QuickEntryPill(stroke: Color.ink.control))
            .tapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Katılımcıyı ekle: \(name)"))
    }

    /// A diary suggestion's person or place the vault does not know by that kind: the name
    /// enters the text only once its entity exists (or now answers to it), pinned.
    private func suggestedNameChip(_ name: SuggestionLine.Mention) -> some View {
        Button {
            Task { @MainActor in
                await model.addSuggestedName(name)
                onAddAttendee()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.ink.secondaryText)
                Image(systemName: name.kind == .person ? "person" : "mappin")
                Text(verbatim: name.name)
                    .lineLimit(1)
            }
            .font(.ink.meta)
            .foregroundStyle(Color.ink.text)
            .modifier(QuickEntryPill(stroke: Color.ink.control))
            .tapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            name.kind == .person ? Text("Kişi olarak ekle: \(name.name)") : Text("Konum olarak ekle: \(name.name)"))
    }

    /// The whole chip is the button: it turns the expression back into plain words.
    private func chip(_ expression: QuickEntryModel.TaskExpression) -> some View {
        let undo = { model.undoRecognition(expression) }
        return Button(action: undo) {
            HStack(spacing: 4) {
                if case .recurrence = expression.value { Image(systemName: "repeat") }
                Text(verbatim: title(expression))
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.ink.secondaryText)
            }
            .font(.ink.meta)
            .foregroundStyle(Color.ink.text)
            .modifier(QuickEntryPill(stroke: Color.ink.control))
            .tapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Tanındı: \(spokenTitle(expression))"))
        .accessibilityHint(Text("Tanımayı geri al"))
        .accessibilityAction(named: Text("Tanımayı geri al"), undo)
    }

    private func title(_ expression: QuickEntryModel.TaskExpression) -> String {
        // The date control beside the chips already shows the day; the chip names the words.
        guard case .recurrence(let recurrence) = expression.value else { return expression.spelling }
        return recurrenceTitle(recurrence)
    }

    private func spokenTitle(_ expression: QuickEntryModel.TaskExpression) -> String {
        switch expression.value {
        case .priority(.high): localized("Yüksek öncelik")
        case .priority: localized("Orta öncelik")
        case .recurrence(let recurrence): recurrenceTitle(recurrence)
        case .date: expression.spelling
        }
    }

    private func recurrenceTitle(_ recurrence: TaskRecurrence) -> String {
        var title: String
        switch recurrence.frequency {
        case .weekday(let day): title = weekdayName(day)
        case .interval(let count, let unit):
            title = TaskRecurrence.intervalLabel(count: count, unit: unit, locale: locale)
        }
        if recurrence.whenDone { title += " · " + localized("Tamamlanınca") }
        return title
    }

    /// Same names as the catalog's weekday titles, as a plain string for the chip.
    private func weekdayName(_ day: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = PresentationLocalization.resolvedLocale(locale)
        // Recurrence days count from Monday, calendar symbols from Sunday.
        return calendar.standaloneWeekdaySymbols[(day + 1) % 7]
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: PresentationLocalization.bundle(locale), locale: locale)
    }

    private var dateButton: some View {
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
            .lineLimit(1)
            // In the capsule's top row the strip beside it gives way, never the date.
            .fixedSize()
            .font(.ink.meta)
            .foregroundStyle(model.dateIsAssumed ? Color.ink.warning : Color.ink.accent)
            .modifier(QuickEntryPill(stroke: model.dateIsAssumed ? Color.ink.warning : Color.ink.control))
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

/// Shared outline of the date control and the chips beside it.
private struct QuickEntryPill: ViewModifier {
    let stroke: Color

    func body(content: Content) -> some View {
        // Padding sandwich, as on the capsule below: a stroked capsule draws end-cap brackets.
        content
            .padding(.horizontal, 8 - InkStroke.control).padding(.vertical, 4 - InkStroke.control)
            .background(Color.ink.well, in: Capsule())
            .padding(InkStroke.control)
            .background(stroke, in: Capsule())
    }
}

/// The chip strip in the capsule's top row (``QuickEntryTaskControls/Part/chips``): a chip cut
/// by the row's end fades out instead of ending on a hard edge. The strip's content ends one
/// fade width early, so scrolled to its end the last chip is whole and unfaded.
struct QuickEntryChipFade: ViewModifier {
    static let width: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .contentMargins(.trailing, Self.width, for: .scrollContent)
            .mask {
                HStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: Self.width)
                }
            }
    }
}
