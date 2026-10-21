import SwiftUI
import VaultFormat

/// Snapshot hosts wait on this until the week's data has been read.
struct WeeklyReviewReadyKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// The optional weekly look back: five steps that only show and collect, then a preview of the
/// lines and "Günlüğe yaz". Each step can be passed; what is not included is not written.
///
/// The sheet holds a draft, so the bar has "Vazgeç" alone and the one action lives in the page:
/// leaving writes nothing. Use inside the sheet's `NavigationStack`.
struct WeeklyReviewView: View {
    @State private var model: WeeklyReviewModel
    @State private var leavePrompt = false
    @FocusState private var noteFocused: Bool
    private let onFinish: (WeeklyReviewResult) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    init(
        store: IndexStore, today: CalendarDate, calendar: Calendar, locale: Locale,
        defaults: UserDefaults = .standard, step: WeeklyReviewStep = .numbers, note: String = "",
        onFinish: @escaping (WeeklyReviewResult) -> Void = { _ in }
    ) {
        let model = WeeklyReviewModel(
            store: store, today: today, calendar: calendar, locale: locale, defaults: defaults, step: step)
        model.note = note
        _model = State(initialValue: model)
        self.onFinish = onFinish
    }

    private var bundle: Bundle { PresentationLocalization.bundle(locale) }

    private var stepText: String {
        let number = model.step.rawValue + 1
        let count = WeeklyReviewStep.allCases.count
        return String(localized: "Adım \(number)/\(count)", bundle: bundle, locale: locale)
    }

    private var rangeText: String {
        let style = Date.FormatStyle(locale: locale).day().month().year()
        let range = model.range
        return LocalDay.instant(for: range.lowerBound).formatted(style) + " – "
            + LocalDay.instant(for: range.upperBound).formatted(style)
    }

    private var hasNote: Bool { !model.note.allSatisfy(\.isWhitespace) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: InkSpacing.section) {
                InkPageTitle("Haftalık inceleme", byline: stepText)
                VStack(alignment: .leading, spacing: InkSpacing.row) {
                    switch model.step {
                    case .numbers: numbersStep
                    case .tasks: tasksStep
                    case .people: peopleStep
                    case .goals: goalsStep
                    case .note: noteStep
                    case .preview: previewStep
                    }
                    #if !os(macOS)
                        controls.padding(.top, InkSpacing.row)
                    #endif
                }
                .padding(.horizontal, InkSpacing.margin)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #if os(macOS)
            // The Mac sheet opens at a fixed size: a long preview would leave "Günlüğe yaz" under
            // the fold, so the step's buttons stay above the bottom bar.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                controls
                .padding(.horizontal, InkSpacing.margin)
                .padding(.vertical, InkSpacing.row)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ink.paper)
            }
        #endif
        .inkSheet(
            "Haftalık inceleme", cancelIdentifier: "button.weeklyReview.cancel",
            isCancelEnabled: model.canClose, onCancel: requestLeave
        )
        // One pass writes once: while the text is being written nothing can be pressed or closed.
        .disabled(!model.canClose)
        .interactiveDismissDisabled(!model.canClose || hasNote)
        .confirmationDialog("Kaydedilmemiş değişiklikler", isPresented: $leavePrompt) {
            Button("At", role: .destructive) { dismiss() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Yazdığın not günlüğe eklenmedi.")
        }
        .preference(key: WeeklyReviewReadyKey.self, value: model.content != nil && !model.isLoading)
        .task(id: model.store.lastUpdated) { await model.load() }
        .onChange(of: model.result) { _, result in
            guard let result else { return }
            onFinish(result)
            dismiss()
        }
        // The page changes under the same title: VoiceOver starts over and reads the new step.
        .onChange(of: model.step) { AccessibilityNotification.ScreenChanged().post() }
        .accessibilityIdentifier("screen.weeklyReview")
    }

    private func requestLeave() {
        guard model.canClose else { return }
        if hasNote { leavePrompt = true } else { dismiss() }
    }

    // MARK: - Steps

    @ViewBuilder private var numbersStep: some View {
        InkTabs(
            selection: $model.week,
            items: [
                InkTabItem("Bu hafta", value: WeeklyReviewWeek.current, identifier: "tab.weeklyReview.current"),
                InkTabItem("Geçen hafta", value: WeeklyReviewWeek.previous, identifier: "tab.weeklyReview.previous"),
            ], identifier: "tabs.weeklyReview.week",
            accessibilityLabelPrefix: String(localized: "Hafta", bundle: bundle, locale: locale))
        // One text, so that at large sizes the range wraps as a sentence.
        Text(verbatim: rangeText)
            .font(.ink.byline)
            .foregroundStyle(Color.ink.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, InkSpacing.row)
        section(
            .numbers, title: String(localized: "Haftanın sayıları", bundle: bundle, locale: locale),
            empty: "Bu dönemde kayıt yok."
        ) { content in
            weekRhythm
            if content.events > 0 { metric(content.events, "Olay sayısı") }
            if content.completedTasks > 0 { metric(content.completedTasks, "Tamamlanan") }
            if content.writtenDays > 0 { metric(content.writtenDays, "Yazılan gün") }
        }
    }

    /// Seven short columns over the numbers, the week before behind them, and the change in events.
    @ViewBuilder private var weekRhythm: some View {
        RhythmStrip(items: model.rhythmItems, legend: [], barHeight: 40, isCompact: true)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(verbatim: String(localized: "Ritim", bundle: bundle, locale: locale)))
        if let change = model.rhythmChange {
            Text(verbatim: change)
                .font(.ink.meta)
                .monospacedDigit()
                .foregroundStyle(Color.ink.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, InkSpacing.row)
        }
    }

    @ViewBuilder private var tasksStep: some View {
        section(
            .tasks, title: String(localized: "Açık görevler", bundle: bundle, locale: locale),
            count: model.content?.openTaskCount, empty: "Bu haftadan açık görev kalmadı."
        ) { content in
            ForEach(Array(content.openTasks.enumerated()), id: \.offset) { _, text in
                vaultLine(text)
            }
            let rest = content.openTaskCount - content.openTasks.count
            if rest > 0 {
                hint(verbatim: String(localized: "ve \(rest) görev daha", bundle: bundle, locale: locale))
            }
        }
    }

    @ViewBuilder private var peopleStep: some View {
        section(
            .people, title: String(localized: "Bir süredir görüşmediklerin", bundle: bundle, locale: locale),
            empty: "Vadesi gelen görüşme yok."
        ) { content in
            ForEach(Array(content.people.enumerated()), id: \.offset) { _, name in
                vaultLine(name)
            }
        }
    }

    @ViewBuilder private var goalsStep: some View {
        section(
            .goals, title: String(localized: "Hedefler", bundle: bundle, locale: locale),
            empty: "Günlük ya da haftalık hedef yok."
        ) { content in
            ForEach(content.goals) { goal in
                HStack(alignment: .firstTextBaseline, spacing: InkSpacing.section) {
                    Text(verbatim: goal.name)
                        .font(.ink.content)
                        .foregroundStyle(Color.ink.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: WeeklyReviewContent.standingText(goal.standing, locale: locale))
                        .font(.ink.value)
                        .foregroundStyle(Color.ink.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder private var noteStep: some View {
        SectionHeader(title: String(localized: "Not", bundle: bundle, locale: locale))
        hint("Haftaya dair eklemek istediğin bir şey varsa yaz; boş bırakabilirsin.")
        TextField(
            "Not", text: $model.note, prompt: Text("Haftaya dair not").font(.ink.placeholder), axis: .vertical
        )
        .lineLimit(4...12)
        .textFieldStyle(.plain)
        .font(.ink.content)
        .foregroundStyle(Color.ink.text)
        .focused($noteFocused)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Color.ink.well,
            in: RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
                .strokeBorder(
                    InkButtonChrome.color(for: InkFilterFieldChrome.borderToken(isFocused: noteFocused)),
                    lineWidth: InkStroke.control)
        )
        .accessibilityIdentifier("field.weeklyReview.note")
    }

    @ViewBuilder private var previewStep: some View {
        let lines = model.previewLines
        SectionHeader(title: String(localized: "Önizleme", bundle: bundle, locale: locale))
        if let blocked = model.blockedText {
            InfoBand(kind: .warning, verbatim: blocked)
        }
        if let error = model.errorText {
            InfoBand(kind: .error, verbatim: error)
        }
        if lines.isEmpty {
            EmptyState("Yazılacak bir şey seçilmedi.")
        } else {
            hint("Bugünün günlük yazısının sonuna aynen eklenir.")
            // The lines as they will stand in the file, marks included.
            VStack(alignment: .leading, spacing: InkSpacing.row) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    vaultLine(line)
                }
            }
            .accessibilityIdentifier("text.weeklyReview.preview")
        }
    }

    // MARK: - Pieces

    /// One collecting step: what the week holds, and whether its sentences go into the output.
    @ViewBuilder private func section<Rows: View>(
        _ section: WeeklyReviewSection, title: String, count: Int? = nil, empty: LocalizedStringKey,
        @ViewBuilder rows: (WeeklyReviewContent) -> Rows
    ) -> some View {
        SectionHeader(title: title, count: count, isLoading: model.isLoading)
        if let error = model.loadErrorText {
            InfoBand(kind: .error, verbatim: error)
        }
        if let content = model.content {
            if model.lines(for: section).isEmpty {
                EmptyState(empty)
            } else {
                rows(content)
                WeeklyReviewIncludeToggle(
                    isOn: Binding(
                        get: { model.isIncluded(section) }, set: { model.setIncluded(section, $0) })
                )
                // The same words on four pages: VoiceOver also says what is included.
                .accessibilityLabel(
                    Text(verbatim: title + ", " + String(localized: "Çıktıya ekle", bundle: bundle, locale: locale))
                )
                .accessibilityIdentifier("toggle.weeklyReview.include")
            }
        }
    }

    /// The step's buttons: "İleri" (or "Atla"), and on the last step "Günlüğe yaz"; "Geri" after
    /// the first step. In the page on iPhone, above the bottom bar on Mac.
    private var controls: some View {
        HStack(spacing: InkSpacing.section) {
            if model.step == .preview {
                Button("Günlüğe yaz") { Task { await model.write() } }
                    .buttonStyle(InkPrimaryButtonStyle())
                    .disabled(!model.canWrite)
                    .accessibilityIdentifier("button.weeklyReview.write")
            } else {
                // A step that leaves nothing in the output is being skipped, not confirmed.
                Button(model.isSkipped(model.step) ? "Atla" : "İleri") { model.advance() }
                    .buttonStyle(InkPrimaryButtonStyle())
                    .accessibilityIdentifier("button.weeklyReview.next")
            }
            if model.step.previous != nil {
                Button("Geri") { model.back() }
                    .buttonStyle(InkTextButtonStyle())
                    .accessibilityIdentifier("button.weeklyReview.back")
            }
        }
    }

    private func metric(_ value: Int, _ title: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: InkSpacing.section) {
            Text(title)
                .font(.ink.content)
                .foregroundStyle(Color.ink.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: value.formatted(.number.locale(locale)))
                .font(.ink.value)
                .foregroundStyle(Color.ink.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private func vaultLine(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.ink.content)
            .foregroundStyle(Color.ink.text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hint(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.ink.meta)
            .foregroundStyle(Color.ink.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, InkSpacing.row)
    }

    private func hint(verbatim text: String) -> some View {
        Text(verbatim: text)
            .font(.ink.meta)
            .foregroundStyle(Color.ink.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Presents the weekly review over the screen that offers it; `onFinish` gets the notice to
    /// show once the sheet has closed on a written review. The review day is read when the
    /// sheet opens and stays, also when midnight passes while it is open.
    func weeklyReviewSheet(
        isPresented: Binding<Bool>, store: IndexStore, onFinish: @escaping (WeeklyReviewNotice) -> Void
    ) -> some View {
        modifier(WeeklyReviewSheet(isPresented: isPresented, store: store, onFinish: onFinish))
    }
}

private struct WeeklyReviewSheet: ViewModifier {
    @Binding var isPresented: Bool
    let store: IndexStore
    let onFinish: (WeeklyReviewNotice) -> Void
    @Environment(\.clockNow) private var clockNow
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            NavigationStack {
                WeeklyReviewView(
                    store: store, today: LocalDay.today(at: clockNow(), timeZone: calendar.timeZone),
                    calendar: calendar, locale: locale
                ) { onFinish(WeeklyReviewNotice($0, locale: locale)) }
            }
        }
    }
}

/// The meta line of the entry row: said only while the current week is already reviewed.
struct WeeklyReviewEntryStatus: View {
    @AppStorage(WeeklyReviewPreference.key) private var reviewedWeekStart = ""
    @Environment(\.clockNow) private var clockNow
    @Environment(\.calendar) private var calendar

    var body: some View {
        let today = LocalDay.today(at: clockNow(), timeZone: calendar.timeZone)
        if WeeklyReviewWeek.current.range(containing: today, calendar: calendar).lowerBound.description
            == reviewedWeekStart
        {
            Text("Bu hafta yapıldı")
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
        }
    }
}

/// "Çıktıya ekle" under a collecting step's rows. On iOS the row is a 44 pt touch target: the
/// switch alone is 28 pt, so the label carries the height and the switch sits in its middle,
/// with no gap above (the row's own height is the gap).
struct WeeklyReviewIncludeToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text("Çıktıya ekle")
                .frame(minHeight: Self.minimumHeight)
                // The row as VoiceOver and the touch-target audit measure it, not the text's own line.
                .contentShape(.accessibility, Rectangle())
        }
        .contentShape(.accessibility, Rectangle())
        .font(.ink.meta)
        .foregroundStyle(Color.ink.secondaryText)
        .padding(.top, Self.topPadding)
    }

    private static var minimumHeight: CGFloat? {
        #if os(iOS)
            TapTarget.minimumLength
        #else
            nil
        #endif
    }

    private static var topPadding: CGFloat {
        #if os(iOS)
            0
        #else
            InkSpacing.row
        #endif
    }
}
