import SwiftUI
import VaultFormat

/// What a calendar row or button opens. One sheet per route; the detail swaps to the form in place.
enum CalendarSheetRoute: Identifiable {
    /// `day`: the page's day, for "Olay taslağı"; nil on the person page (no quick entry there).
    case detail(CalendarEvent, day: CalendarDate?)
    case create(CalendarDate)
    /// `birthday`: the person file's birthday field, when it has a readable one.
    case birthday(CalendarPersonNames, birthday: PersonBirthday?)

    var id: String {
        switch self {
        case .detail(let event, _): "detail:" + event.id
        case .create(let day): "create:" + day.description
        case .birthday(let names, _): "birthday:" + names.fullName
        }
    }
}

/// Our own Şafak form instead of EventKitUI: EventKitUI does not exist on the Mac and draws the
/// system's look; the fake source keeps the flow unit-testable (decision 2026-11-11).
struct CalendarSheet: View {
    let route: CalendarSheetRoute

    var body: some View {
        NavigationStack {
            switch route {
            case .detail(let event, let day): CalendarEventDetail(event: event, day: day)
            case .create(let day): CalendarEventForm(original: nil, day: day, onDone: nil)
            case .birthday(let names, let birthday): CalendarBirthdayForm(names: names, birthday: birthday)
            }
        }
    }
}

/// Time and caption lines of an event, shared by the day section, the person page and the detail.
struct CalendarEventText {
    let locale: Locale

    private var bundle: Bundle { PresentationLocalization.bundle(locale) }

    func start(_ event: CalendarEvent) -> String {
        if event.isAllDay { return String(localized: "Tüm gün", bundle: bundle, locale: locale) }
        return event.start.formatted(.dateTime.hour().minute().locale(locale))
    }

    /// "19:00–20:00"; an event that ends on another day names that day: "23:00 – 12 Kas 01:00".
    /// Nil all day long.
    func range(_ event: CalendarEvent) -> String? {
        if event.isAllDay { return nil }
        let start = event.start.formatted(.dateTime.hour().minute().locale(locale))
        if LocalDay.today(at: event.start) != LocalDay.today(at: event.end) {
            let end = event.end.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale))
            return start + " – " + end
        }
        return start + "–" + event.end.formatted(.dateTime.hour().minute().locale(locale))
    }

    /// Today's row, where the start already sits on the left: "19:00–20:00" as the drawing has it,
    /// but an event ending on another day names only its end ("Bitiş 12 Kas 00:20"), not the
    /// start twice. Nil all day long.
    func rowRange(_ event: CalendarEvent) -> String? {
        if event.isAllDay { return nil }
        guard LocalDay.today(at: event.start) != LocalDay.today(at: event.end) else { return range(event) }
        let end = event.end.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale))
        return String(localized: "Bitiş \(end)", bundle: bundle, locale: locale)
    }

    func title(_ event: CalendarEvent) -> String {
        event.title.isEmpty ? String(localized: "Başlıksız etkinlik", bundle: bundle, locale: locale) : event.title
    }

    /// "İş · Her hafta": the calendar's name, and the repeat when there is one.
    func caption(_ event: CalendarEvent) -> String {
        var parts: [String] = []
        if !event.calendarTitle.isEmpty { parts.append(event.calendarTitle) }
        if event.recurrence != .none { parts.append(recurrence(of: event)) }
        return parts.joined(separator: " · ")
    }

    /// "Her hafta", or with a dated end "Her hafta · 1 Oca 2027'ye kadar".
    func recurrence(of event: CalendarEvent) -> String {
        let rule = recurrence(event.recurrence)
        guard let end = event.recurrenceEnd else { return rule }
        let day = end.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
        return rule + " · " + String(localized: "\(day) tarihine kadar", bundle: bundle, locale: locale)
    }

    /// The failed write's message, by what went wrong.
    func message(_ error: CalendarWriteError) -> String {
        switch error {
        case .notFound:
            String(
                localized: "Etkinlik takvimde değişmiş. Listeyi yenileyip yeniden dene.", bundle: bundle, locale: locale
            )
        case .readOnly: String(localized: "Bu etkinlik burada düzenlenemez.", bundle: bundle, locale: locale)
        case .noCalendar: String(localized: "Yazılabilir takvim yok.", bundle: bundle, locale: locale)
        case .unsupported, .failed: String(localized: "Etkinlik takvime yazılamadı.", bundle: bundle, locale: locale)
        }
    }

    func recurrence(_ value: CalendarRecurrence) -> String {
        String(localized: String.LocalizationValue(value.catalogKey), bundle: bundle, locale: locale)
    }

    /// "11 Kas Çar · 19:00–20:00", or all day long the date alone.
    func span(_ event: CalendarEvent) -> String {
        let day = event.start.formatted(.dateTime.day().month(.abbreviated).weekday(.abbreviated).locale(locale))
        guard let range = range(event) else { return day }
        return day + " · " + range
    }

    /// "12 Nis Cmt" or, all day long, the date alone; with the time otherwise.
    func when(_ event: CalendarEvent) -> String {
        let day = event.start.formatted(.dateTime.day().month(.abbreviated).weekday(.abbreviated).locale(locale))
        if event.isAllDay { return day }
        return day + " · " + event.start.formatted(.dateTime.hour().minute().locale(locale))
    }
}

/// One event's detail: time, calendar, repeat and attendees; edit, draft and delete.
struct CalendarEventDetail: View {
    let event: CalendarEvent
    let day: CalendarDate?
    @Environment(CalendarService.self) private var calendar
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var isEditing = false
    @State private var isConfirmingDelete = false

    private var text: CalendarEventText { CalendarEventText(locale: PresentationLocalization.resolvedLocale(locale)) }

    var body: some View {
        if isEditing {
            // "Vazgeç" goes back to the detail; a save closes the sheet.
            CalendarEventForm(original: event, day: day, onDone: { dismiss() }, onCancel: { isEditing = false })
        } else {
            reading
        }
    }

    private var reading: some View {
        List {
            InkPageTitleRow(verbatim: text.title(event))
            if let error = calendar.writeError {
                InfoBand(kind: .error, verbatim: text.message(error)).inkListRow()
            }
            InkCard(padded: false) {
                VStack(alignment: .leading, spacing: 0) {
                    row("Zaman", value: text.span(event))
                    if !event.calendarTitle.isEmpty {
                        InkCardDivider()
                        row("Takvim", value: event.calendarTitle, color: event.color)
                    }
                    if event.recurrence != .none {
                        InkCardDivider()
                        row("Tekrar", value: text.recurrence(of: event))
                    }
                    let people = event.attendees.filter { !$0.name.isEmpty }.map(\.name)
                    if !people.isEmpty {
                        InkCardDivider()
                        row("Katılımcılar", value: people.joined(separator: ", "))
                    }
                }
                .padding(.horizontal, InkSpacing.cardPadding)
            }
            .inkListRow()
            if !event.isEditable {
                Text("Bu etkinlik burada düzenlenemez.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
            }
            if event.isEditable || day != nil {
                actions.inkListRow()
            }
        }
        .listStyle(.plain)
        .inkPageScrollColumn()
        // The title is the user's text: on its own line under "Kapat", never beside it.
        .inkSheet(verbatim: text.title(event), closeIdentifier: "button.calendarEvent.close", titleInBar: false)
        .accessibilityIdentifier("sheet.calendarEvent")
        .confirmationDialog("Etkinlik silinsin mi?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            if event.recurrence == .none {
                Button("Etkinliği sil", role: .destructive) { delete(.thisEvent) }
            } else {
                Button("Yalnız bu etkinlik", role: .destructive) { delete(.thisEvent) }
                Button("Bu ve sonrakiler", role: .destructive) { delete(.futureEvents) }
            }
            Button("Vazgeç", role: .cancel) {}
        }
        .onDisappear { calendar.clearWriteError() }
    }

    /// The rare actions on one small row with icons (drawing: Hedefler's edit and delete row);
    /// when the row does not fit (large text) they stack.
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                editButton
                draftButton
                Spacer(minLength: 0)
                deleteButton
            }
            VStack(alignment: .leading, spacing: 4) {
                editButton
                draftButton
                deleteButton
            }
        }
    }

    /// Icon and word close together (a `Label` spaces them as a list row does).
    private func actionLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline.weight(.medium))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var editButton: some View {
        if event.isEditable {
            Button {
                calendar.clearWriteError()
                isEditing = true
            } label: {
                actionLabel("Düzenle", systemImage: "pencil")
            }
            .buttonStyle(InkTextButtonStyle())
            .tapTarget()
            .accessibilityIdentifier("button.calendarEvent.edit")
        }
    }

    @ViewBuilder private var draftButton: some View {
        if let day {
            Button {
                CalendarDraftInbox.shared.post(event, on: day)
                dismiss()
            } label: {
                actionLabel("Olay taslağı", systemImage: "square.and.pencil")
            }
            .buttonStyle(InkTextButtonStyle())
            .tapTarget()
            .accessibilityIdentifier("button.calendarEvent.draft")
        }
    }

    @ViewBuilder private var deleteButton: some View {
        if event.isEditable {
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                actionLabel("Etkinliği sil", systemImage: "trash")
            }
            .buttonStyle(InkDestructiveButtonStyle())
            .tapTarget()
            .disabled(calendar.isWriting)
            .accessibilityIdentifier("button.calendarEvent.delete")
        }
    }

    private func delete(_ span: CalendarEditSpan) {
        Task { if await calendar.delete(event, span: span) { dismiss() } }
    }

    /// `color`: the calendar's own color, as a dot before its name.
    private func row(_ key: LocalizedStringKey, value: String, color: CalendarEventColor? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(.subheadline)
                .foregroundStyle(Color.ink.secondaryText)
            Spacer(minLength: 8)
            if let color {
                CalendarColorDot(color: color)
            }
            Text(verbatim: value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.ink.text)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: TapTarget.minimumLength)
        .accessibilityElement(children: .combine)
    }
}

/// New event or a change to one. Writes only to the calendar, never to the vault.
struct CalendarEventForm: View {
    let original: CalendarEvent?
    let day: CalendarDate?
    /// Nil: the form is the sheet's root and dismisses itself.
    let onDone: (() -> Void)?
    /// "Vazgeç"; nil: as `onDone`.
    let onCancel: (() -> Void)?
    @Environment(CalendarService.self) private var calendar
    @Environment(\.dismiss) private var dismiss
    @Environment(\.clockNow) private var clockNow
    @State private var draft: CalendarEventDraft?
    @State private var calendars: [CalendarTarget] = []
    @State private var spans: [CalendarEditSpan] = []
    @Environment(\.locale) private var locale

    private var text: CalendarEventText { CalendarEventText(locale: PresentationLocalization.resolvedLocale(locale)) }

    init(
        original: CalendarEvent?, day: CalendarDate?, onDone: (() -> Void)?, onCancel: (() -> Void)? = nil
    ) {
        self.original = original
        self.day = day
        self.onDone = onDone
        self.onCancel = onCancel
        _draft = State(initialValue: original.map(CalendarEventDraft.init(event:)))
    }

    private var title: LocalizedStringKey { original == nil ? "Yeni etkinlik" : "Etkinliği düzenle" }

    var body: some View {
        List {
            InkPageTitleRow(title)
            if let error = calendar.writeError {
                InfoBand(kind: .error, verbatim: text.message(error)).inkListRow()
            }
            if let binding = Binding($draft) {
                fields(binding)
            } else {
                ProgressView().inkListRow()
            }
        }
        .listStyle(.plain)
        .inkPageScrollColumn()
        .inkToggle()
        .disabled(calendar.isWriting)
        .inkSheet(
            title, confirm: original == nil ? .create : .save,
            isConfirmEnabled: (draft?.canSave ?? false) && !calendars.isEmpty, isBusy: calendar.isWriting,
            isCancelEnabled: !calendar.isWriting, cancelIdentifier: "button.calendarEvent.cancel",
            confirmIdentifier: "button.calendarEvent.save", onCancel: cancel
        ) { confirm() }
        .accessibilityIdentifier("sheet.calendarEventForm")
        .interactiveDismissDisabled(calendar.isWriting)
        .confirmationDialog(
            "Tekrarlayan etkinlik", isPresented: Binding(get: { !spans.isEmpty }, set: { if !$0 { spans = [] } }),
            titleVisibility: .visible
        ) {
            ForEach(spans, id: \.self) { span in
                Button(span == .thisEvent ? "Yalnız bu etkinlik" : "Bu ve sonrakiler") { save(span) }
            }
            Button("Vazgeç", role: .cancel) {}
        }
        .task {
            calendars = await calendar.writableCalendars()
            let fallback = await calendar.resolvedDefaultCalendarID(among: calendars)
            if draft == nil, let day {
                draft = .new(on: day, now: clockNow(), calendarID: fallback ?? calendars.first?.id)
            } else if draft?.calendarID == nil {
                draft?.calendarID = fallback ?? calendars.first?.id
            }
        }
        .onDisappear { calendar.clearWriteError() }
    }

    @ViewBuilder private func fields(_ draft: Binding<CalendarEventDraft>) -> some View {
        InkCard(padded: false) {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Başlık", text: draft.title)
                    .font(.ink.content)
                    .frame(minHeight: TapTarget.minimumLength)
                    .accessibilityIdentifier("field.calendarEvent.title")
                InkCardDivider()
                Toggle("Tüm gün", isOn: draft.isAllDay)
                    .frame(minHeight: TapTarget.minimumLength)
                    .accessibilityIdentifier("toggle.calendarEvent.allDay")
                InkCardDivider()
                DatePicker(
                    "Başlangıç", selection: startBinding(draft),
                    displayedComponents: draft.wrappedValue.isAllDay ? [.date] : [.date, .hourAndMinute]
                )
                .frame(minHeight: TapTarget.minimumLength)
                InkCardDivider()
                // No `in:` range: a bounded compact picker drew its date numerically ("12.11.2026")
                // beside the start's "11 Kas 2026". The binding keeps the end at or after the start.
                DatePicker(
                    "Bitiş", selection: endBinding(draft),
                    displayedComponents: draft.wrappedValue.isAllDay ? [.date] : [.date, .hourAndMinute]
                )
                .frame(minHeight: TapTarget.minimumLength)
                InkCardDivider()
                // Same row as the date pickers: the label on the left, the value on the right.
                CalendarFormMenuRow(
                    "Tekrar", selection: draft.recurrence, options: recurrenceOptions,
                    identifier: "menu.calendarEvent.recurrence")
                InkCardDivider()
                // One occurrence of a series cannot move to another calendar: the menu is closed.
                CalendarFormMenuRow(
                    "Takvim", selection: calendarBinding(draft),
                    options: calendars.map { InkMenuOption(verbatim: $0.title, value: $0.id) },
                    identifier: "menu.calendarEvent.calendar"
                )
                .disabled((original?.recurrence ?? .none) != .none)
            }
            .font(.subheadline)
            .padding(.horizontal, InkSpacing.cardPadding)
        }
        .inkListRow()
        if calendars.isEmpty {
            Text("Yazılabilir takvim yok.")
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .inkListRow()
        }
    }

    private var recurrenceOptions: [InkMenuOption<CalendarRecurrence>] {
        var values = CalendarRecurrence.choices
        // A rule the plain choices cannot write stays on the menu, kept until changed.
        if let kept = original?.recurrence, !values.contains(kept) { values.append(kept) }
        // Under the label "Tekrar" the empty choice reads "Yok", not "Tekrar yok" (drawing: Görev).
        return values.map { InkMenuOption(LocalizedStringKey($0 == .none ? "Yok" : $0.catalogKey), value: $0) }
    }

    /// The end never goes before the start.
    private func endBinding(_ draft: Binding<CalendarEventDraft>) -> Binding<Date> {
        Binding(
            get: { draft.wrappedValue.end },
            set: { end in draft.wrappedValue.end = max(end, draft.wrappedValue.start) }
        )
    }

    /// Moving the start keeps the event's length.
    private func startBinding(_ draft: Binding<CalendarEventDraft>) -> Binding<Date> {
        Binding(
            get: { draft.wrappedValue.start },
            set: { start in
                let length = max(0, draft.wrappedValue.end.timeIntervalSince(draft.wrappedValue.start))
                draft.wrappedValue.start = start
                draft.wrappedValue.end = start.addingTimeInterval(length)
            })
    }

    private func calendarBinding(_ draft: Binding<CalendarEventDraft>) -> Binding<String> {
        Binding(get: { draft.wrappedValue.calendarID ?? "" }, set: { draft.wrappedValue.calendarID = $0 })
    }

    private func confirm() {
        guard let draft else { return }
        if let original {
            let choices = CalendarEventDraft.spans(saving: draft, over: original)
            if choices.count > 1 {
                spans = choices
                return
            }
            save(choices.first ?? .thisEvent)
        } else {
            save(.thisEvent)
        }
    }

    private func save(_ span: CalendarEditSpan) {
        guard let draft else { return }
        Task { if await calendar.save(draft, editing: original, span: span) { finish() } }
    }

    private func finish() {
        if let onDone { onDone() } else { dismiss() }
    }

    private func cancel() {
        if let onCancel { onCancel() } else { finish() }
    }
}

/// "Doğum günü ekle": a yearly all-day event "<Ad> doğum günü". The date comes from the person
/// file's birthday field when it has one (`docs/vault-format.md`), else the user picks it.
struct CalendarBirthdayForm: View {
    let names: CalendarPersonNames
    let birthday: PersonBirthday?
    @Environment(CalendarService.self) private var calendar
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var dateCalendar
    @Environment(\.clockNow) private var clockNow
    @State private var date: Date?
    @State private var calendarID: String?
    @State private var calendars: [CalendarTarget]?
    @State private var isSaving = false
    /// The birthday is already on the calendar (added elsewhere, or by a second tap): say so.
    @State private var alreadyExists = false

    private var text: CalendarEventText { CalendarEventText(locale: PresentationLocalization.resolvedLocale(locale)) }

    var body: some View {
        List {
            InkPageTitleRow("Doğum günü ekle")
            if alreadyExists {
                InfoBand(kind: .info, "Bu kişinin doğum günü takvimde zaten var.")
                    .accessibilityIdentifier("band.birthday.exists")
                    .inkListRow()
            }
            if let error = calendar.writeError {
                InfoBand(kind: .error, verbatim: text.message(error)).inkListRow()
            }
            InkCard(padded: false) {
                DatePicker(
                    "Tarih", selection: Binding(get: { date ?? initialDate }, set: { date = $0 }),
                    displayedComponents: [.date]
                )
                .font(.subheadline)
                .frame(minHeight: TapTarget.minimumLength)
                .padding(.horizontal, InkSpacing.cardPadding)
                .accessibilityIdentifier("picker.birthday.date")
            }
            .inkListRow()
            Text("Her yıl tekrarlayan tüm gün etkinliği olarak takvime yazılır.")
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .inkListRow()
            if calendars?.isEmpty == true {
                Text("Yazılabilir takvim yok.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
            }
        }
        .listStyle(.plain)
        .inkPageScrollColumn()
        .disabled(calendar.isWriting || isSaving)
        .inkSheet(
            "Doğum günü ekle", confirm: .create, isConfirmEnabled: calendars?.isEmpty == false && !alreadyExists,
            isBusy: calendar.isWriting || isSaving, isCancelEnabled: !(calendar.isWriting || isSaving),
            cancelIdentifier: "button.birthday.cancel", confirmIdentifier: "button.birthday.save"
        ) { save() }
        .accessibilityIdentifier("sheet.birthday")
        .task {
            let found = await calendar.writableCalendars()
            calendarID = await calendar.resolvedDefaultCalendarID(among: found)
            calendars = found
        }
        .onDisappear { calendar.clearWriteError() }
    }

    /// The field's day (its yearless form on this year), else today.
    private var initialDate: Date {
        let today = LocalDay.today(at: clockNow())
        guard let day = birthday?.firstDay(currentYear: today.year) else { return clockNow() }
        return LocalDay.instant(for: day)
    }

    /// A second tap, or a birthday added meanwhile elsewhere, never writes a second series.
    private func save() {
        guard !isSaving else { return }
        isSaving = true
        let draft = CalendarEventDraft.birthday(
            name: names.fullName, on: date ?? initialDate, calendarID: calendarID, locale: locale)
        Task {
            defer { isSaving = false }
            let start = dateCalendar.startOfDay(for: clockNow())
            if await calendar.personEvents(names: names, from: start)?.birthday != nil {
                alreadyExists = true
                return
            }
            if await calendar.save(draft) { dismiss() }
        }
    }
}

/// A form row of the event sheet: the label on the left as the date pickers' ("Başlangıç"), the
/// chosen value on the right in the accent with the menu's arrows.
private struct CalendarFormMenuRow<Value: Hashable>: View {
    let label: LocalizedStringKey
    @Binding var selection: Value
    let options: [InkMenuOption<Value>]
    let identifier: String
    @Environment(\.isEnabled) private var isEnabled

    init(
        _ label: LocalizedStringKey, selection: Binding<Value>, options: [InkMenuOption<Value>],
        identifier: String
    ) {
        self.label = label
        _selection = selection
        self.options = options
        self.identifier = identifier
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(Color.ink.text)
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            Menu {
                Picker(selection: $selection) {
                    ForEach(options) { $0.text.tag($0.value) }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    (options.first { $0.value == selection }?.text ?? Text(verbatim: ""))
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(isEnabled ? Color.ink.accent : Color.ink.secondaryText)
                .tapTarget()
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel(Text(label))
            .accessibilityValue(options.first { $0.value == selection }?.text ?? Text(verbatim: ""))
            .accessibilityIdentifier(identifier)
        }
        .frame(minHeight: TapTarget.minimumLength)
    }
}
