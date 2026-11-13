import SwiftUI
import VaultFormat

extension DayView {
    @ViewBuilder
    func scheduleRow(
        entry: DayScheduleEntry, isTimedSection: Bool, entitiesByID: [String: EntitySummary]
    ) -> some View {
        let isSelected = selectedScheduleItemID == entry.id
        let time = entry.time.map { EventTimeFormat.string(for: $0, locale: locale) }
        HStack(alignment: .top, spacing: 8) {
            // The card reads its time itself; the column is for the eye.
            Text(verbatim: isTimedSection ? (time ?? "") : "")
                .font(.ink.meta.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.ink.secondaryText)
                .frame(width: 52, alignment: .leading)
                .padding(.top, InkSpacing.cardPadding + 2)
                .accessibilityHidden(true)

            switch entry.kind {
            case .event(let event):
                scheduleEventCard(
                    entryID: entry.id, event: event, time: time, isSelected: isSelected,
                    entitiesByID: entitiesByID)
            case .task(let task):
                scheduleTaskCard(
                    entryID: entry.id, task: task, time: time, isSelected: isSelected,
                    entitiesByID: entitiesByID)
            }
        }
    }

    /// The wide past day's one "Program" card (drawing `j-mac2`): a small title with the counts,
    /// then every entry in time order, untimed ones last with "—" in the time column.
    func programCard(
        _ schedule: DaySchedulePresentation, presented: TodayPresentation,
        entitiesByID: [String: EntitySummary]
    ) -> some View {
        let tasks = schedule.allOrdered.filter { if case .task = $0.kind { true } else { false } }.count
        let events = schedule.allOrdered.count - tasks
        return InkCard {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Program")
                    .font(.ink.meta.weight(.semibold))
                    .foregroundStyle(Color.ink.secondaryText)
                    .accessibilityAddTraits(.isHeader)
                    // A section title, as ``SectionHeader``'s: not a page manşet.
                    .accessibilityIdentifier(SectionHeader.titleIdentifier)
                Spacer(minLength: 8)
                Text(
                    "\(Self.countNumber(events, locale: locale)) olay · \(Self.countNumber(tasks, locale: locale)) görev"
                )
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(schedule.allOrdered) { entry in
                    programRow(entry: entry, entitiesByID: entitiesByID)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("day.program")
    }

    @ViewBuilder
    func programRow(entry: DayScheduleEntry, entitiesByID: [String: EntitySummary]) -> some View {
        let isSelected = selectedScheduleItemID == entry.id
        let time = entry.time.map { EventTimeFormat.string(for: $0, locale: locale) }
        HStack(alignment: .top, spacing: 10) {
            Text(verbatim: time ?? "—")
                .font(.ink.meta)
                .monospacedDigit()
                .foregroundStyle(Color.ink.secondaryText)
                .frame(width: 44, alignment: .trailing)
                .padding(.top, 12)
                .accessibilityHidden(true)
            switch entry.kind {
            case .event(let event):
                programEventCard(
                    entryID: entry.id, event: event, time: time, isSelected: isSelected,
                    entitiesByID: entitiesByID)
            case .task(let task):
                programTaskCard(
                    entryID: entry.id, task: task, time: time, isSelected: isSelected,
                    entitiesByID: entitiesByID)
            }
        }
    }

    /// "Olay" / "Görev": the program card's small outlined kind label.
    func programKind(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption)
            .foregroundStyle(Color.ink.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(Color.ink.line, lineWidth: 1))
            .fixedSize()
            .accessibilityHidden(true)
    }

    /// "1 kişi · 1 konum": the people and places an event links, as the drawing's meta line.
    func programEventMeta(_ segments: [InkLinkSegment], subLineCount: Int, isSelected: Bool) -> String? {
        let bundle = PresentationLocalization.bundle(locale)
        let people = Set(segments.filter { $0.kind == .person }.map { $0.target ?? $0.text }).count
        let places = Set(segments.filter { $0.kind == .place }.map { $0.target ?? $0.text }).count
        var parts: [String] = []
        if people > 0 { parts.append(String(localized: "\(people) kişi", bundle: bundle, locale: locale)) }
        if places > 0 { parts.append(String(localized: "\(places) konum", bundle: bundle, locale: locale)) }
        if !isSelected, subLineCount > 0 {
            parts.append(String(localized: "\(subLineCount) alt satır", bundle: bundle, locale: locale))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The bar's colour: a person's link wins, then a place's; an unlinked event stays neutral.
    static func programBar(_ segments: [InkLinkSegment]) -> Color {
        if segments.contains(where: { $0.kind == .person }) { return Color.ink.person }
        if segments.contains(where: { $0.kind == .place }) { return Color.ink.place }
        return Color.ink.control
    }

    @ViewBuilder
    func programEventCard(
        entryID: String, event: EventRow, time: String?, isSelected: Bool,
        entitiesByID: [String: EntitySummary]
    ) -> some View {
        let segments = InkLinkMapping.segments(from: event.text, entitiesByID: entitiesByID)
        let allLines = DaySchedulePresentation.splitSegmentsByLine(segments)
        let firstSegments = allLines.first ?? []
        let subLines = Array(allLines.dropFirst())
        let meta = programEventMeta(segments, subLineCount: subLines.count, isSelected: isSelected)
        let kind = PresentationLocalization.string(localized: "Olay", locale: locale)
        let edit = { editingScheduleEvent = EventEditorModel(store: store, day: date, row: event) }

        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                InkLinkedText(
                    segments: firstSegments, font: .ink.content,
                    openURL: { openScheduleLink($0) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                if let meta {
                    Text(verbatim: meta)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                }
                if isSelected, !subLines.isEmpty {
                    ForEach(Array(subLines.enumerated()), id: \.offset) { _, subSegments in
                        InkLinkedText(
                            segments: subSegments, font: .ink.contentSmall,
                            isMuted: true, openURL: { openScheduleLink($0) })
                    }
                    .padding(.top, 2)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text(verbatim: Self.scheduleSpokenLabel(time: time, text: firstSegments.map(\.text).joined()))
            )
            .accessibilityValue(
                Text(
                    verbatim: ([kind] + [meta].compactMap { $0 }
                        + (isSelected ? subLines.map { $0.map(\.text).joined() } : []))
                        .joined(separator: ", "))
            )
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { tapScheduleCard(entryID, edit: edit) }
            .accessibilityAction(named: Text("Metni düzenle"), edit)
            .accessibilityAction(named: Text("Sil")) { deletingScheduleEvent = event }

            programKind("Olay")
        }
        .modifier(
            ProgramRowChrome(
                bar: Self.programBar(segments), isSelected: isSelected, isFinished: false,
                hairline: InkStroke.hairline(scale: displayScale))
        )
        .onTapGesture { tapScheduleCard(entryID, edit: edit) }
        .contextMenu {
            Button(action: edit) {
                Label("Metni düzenle", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deletingScheduleEvent = event
            } label: {
                Label("Sil", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    func programTaskCard(
        entryID: String, task: TaskRow, time: String?, isSelected: Bool,
        entitiesByID: [String: EntitySummary]
    ) -> some View {
        let box = TaskBoxPresentation(row: task, isCompleted: tasksModel.completed.contains(task.id))
        let isCompleted = box.state.isCompleted
        let segments = scheduleTaskSegments(for: task, isTimed: time != nil, entitiesByID: entitiesByID)
        let canToggle =
            !isCompleted && !tasksModel.completing.contains(task.id) && !store.isWriting && store.canAddEvent
        let meta = scheduleTaskMeta(for: task, isCompleted: isCompleted)
        let dates = isSelected ? scheduleTaskDates(task) : nil
        let edit = { editingScheduleTask = TaskEditorModel(store: store, row: task) }

        HStack(alignment: .center, spacing: 12) {
            TaskBox(
                state: box.state,
                action: canToggle ? { Task { await tasksModel.complete(task) } } : nil,
                accessibilityLabel: isCompleted ? "Tamamlandı" : "Görevi tamamla"
            )

            VStack(alignment: .leading, spacing: 3) {
                InkLinkedText(
                    segments: segments, font: .ink.content, isMuted: isCompleted,
                    openURL: { openScheduleLink($0) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: meta)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                if let dates {
                    Text(verbatim: dates)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text(verbatim: Self.scheduleSpokenLabel(time: time, text: segments.map(\.text).joined()))
            )
            .accessibilityValue(Text(verbatim: [meta, dates].compactMap { $0 }.joined(separator: ", ")))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { tapScheduleCard(entryID, edit: edit) }
            .accessibilityAction(named: Text("Metni düzenle"), edit)
            .accessibilityAction(named: Text("Sil")) { deletingScheduleTask = task }

            programKind("Görev")
        }
        .modifier(
            ProgramRowChrome(
                bar: isCompleted ? Color.ink.tertiaryText : Color.ink.accent, isSelected: isSelected,
                isFinished: isCompleted, hairline: InkStroke.hairline(scale: displayScale))
        )
        .onTapGesture { tapScheduleCard(entryID, edit: edit) }
        .contextMenu {
            Button(action: edit) {
                Label("Metni düzenle", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deletingScheduleTask = task
            } label: {
                Label("Sil", systemImage: "trash")
            }
        }
    }

    /// First tap selects the card, the second opens its editor.
    func tapScheduleCard(_ entryID: String, edit: () -> Void) {
        if selectedScheduleItemID == entryID { edit() } else { selectedScheduleItemID = entryID }
    }

    /// The card's spoken label: its time (when it has one), then its text. The meta line is its value.
    static func scheduleSpokenLabel(time: String?, text: String) -> String {
        ([time].compactMap { $0 } + [text]).joined(separator: ", ")
    }

    @ViewBuilder
    func scheduleEventCard(
        entryID: String, event: EventRow, time: String?, isSelected: Bool,
        entitiesByID: [String: EntitySummary]
    ) -> some View {
        let allLines = DaySchedulePresentation.splitSegmentsByLine(
            InkLinkMapping.segments(from: event.text, entitiesByID: entitiesByID))
        let firstSegments = allLines.first ?? []
        let subLines = Array(allLines.dropFirst())
        let meta = scheduleEventMeta(subLineCount: subLines.count, isSelected: isSelected)
        let edit = { editingScheduleEvent = EventEditorModel(store: store, day: date, row: event) }
        let tap = { tapScheduleCard(entryID, edit: edit) }

        // The drawing's card: an icon box on the leading side, "›" on the trailing one, no rule.
        ScheduleEntryCard(
            isSelected: isSelected,
            hairline: InkStroke.hairline(scale: displayScale),
            meta: meta,
            spokenLabel: Self.scheduleSpokenLabel(time: time, text: firstSegments.map(\.text).joined()),
            spokenValue: ([meta] + (isSelected ? subLines.map { $0.map(\.text).joined() } : []))
                .joined(separator: ", "),
            onTap: tap,
            onEdit: edit,
            onDelete: { deletingScheduleEvent = event },
            leading: {
                Image(systemName: "pencil")
                    .font(.ink.meta.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.ink.accent : Color.ink.text)
                    .frame(width: scheduleIconBox, height: scheduleIconBox)
                    .background(
                        RoundedRectangle(cornerRadius: InkCorner.xs, style: .continuous)
                            .fill(isSelected ? Color.ink.surface : Color.ink.well)
                    )
                    .accessibilityHidden(true)
            },
            title: {
                InkLinkedText(
                    segments: firstSegments, font: .ink.content,
                    openURL: { openScheduleLink($0) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            },
            extra: {
                if isSelected, !subLines.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(subLines.enumerated()), id: \.offset) { _, subSegments in
                            InkLinkedText(
                                segments: subSegments, font: .ink.contentSmall,
                                isMuted: true, openURL: { openScheduleLink($0) })
                        }
                    }
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.ink.line)
                            .frame(width: 2)
                            .accessibilityHidden(true)
                    }
                    .padding(.top, 4)
                }
            }
        )
    }

    @ViewBuilder
    func scheduleTaskCard(
        entryID: String, task: TaskRow, time: String?, isSelected: Bool,
        entitiesByID: [String: EntitySummary]
    ) -> some View {
        let box = TaskBoxPresentation(row: task, isCompleted: tasksModel.completed.contains(task.id))
        let isCompleted = box.state.isCompleted
        let segments = scheduleTaskSegments(for: task, isTimed: time != nil, entitiesByID: entitiesByID)
        // The box only closes a task: completing again does nothing, so a closed box has no action.
        let canToggle =
            !isCompleted && !tasksModel.completing.contains(task.id) && !store.isWriting && store.canAddEvent
        let meta = scheduleTaskMeta(for: task, isCompleted: isCompleted)
        let dates = isSelected ? scheduleTaskDates(task) : nil
        let edit = { editingScheduleTask = TaskEditorModel(store: store, row: task) }
        let tap = { tapScheduleCard(entryID, edit: edit) }

        ScheduleEntryCard(
            isSelected: isSelected,
            hairline: InkStroke.hairline(scale: displayScale),
            meta: meta,
            spokenLabel: Self.scheduleSpokenLabel(time: time, text: segments.map(\.text).joined()),
            spokenValue: [meta, dates].compactMap { $0 }.joined(separator: ", "),
            onTap: tap,
            onEdit: edit,
            onDelete: { deletingScheduleTask = task },
            leading: {
                TaskBox(
                    state: box.state,
                    action: canToggle ? { Task { await tasksModel.complete(task) } } : nil,
                    accessibilityLabel: isCompleted ? "Tamamlandı" : "Görevi tamamla"
                )
            },
            title: {
                InkLinkedText(
                    segments: segments, font: .ink.content, isMuted: isCompleted,
                    openURL: { openScheduleLink($0) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            },
            extra: {
                // The selected card's note line: the task's dates.
                if let dates {
                    Text(verbatim: dates)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                }
            }
        )
    }

    /// "Bitiş: 1 Eki · Başlangıç: 28 Eyl"; nil when the task carries no date.
    func scheduleTaskDates(_ task: TaskRow) -> String? {
        let bundle = PresentationLocalization.bundle(locale)
        func day(_ value: CalendarDate) -> String {
            LocalDay.instant(for: value).formatted(Date.FormatStyle(locale: locale).day().month(.abbreviated))
        }
        var parts: [String] = []
        if let start = task.start {
            parts.append(String(localized: "Başlangıç: \(day(start))", bundle: bundle, locale: locale))
        }
        if let due = task.due { parts.append(String(localized: "Bitiş: \(day(due))", bundle: bundle, locale: locale)) }
        if let done = task.done {
            parts.append(String(localized: "Tamamlandı: \(day(done))", bundle: bundle, locale: locale))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func scheduleEventMeta(subLineCount: Int, isSelected: Bool) -> String {
        let base = String(
            localized: "Olay", bundle: PresentationLocalization.bundle(locale), locale: locale)
        guard !isSelected, subLineCount > 0 else { return base }
        let suffix = String(
            localized: "\(subLineCount) alt satır",
            bundle: PresentationLocalization.bundle(locale), locale: locale)
        return "\(base) · \(suffix)"
    }

    func scheduleTaskMeta(for task: TaskRow, isCompleted: Bool) -> String {
        var parts = [
            String(
                localized: "Görev", bundle: PresentationLocalization.bundle(locale), locale: locale)
        ]
        if let project = task.project {
            parts.append(project)
        }
        if isCompleted {
            parts.append(
                String(
                    localized: "Tamamlandı",
                    bundle: PresentationLocalization.bundle(locale), locale: locale))
        }
        return parts.joined(separator: " · ")
    }

    func scheduleTaskSegments(
        for task: TaskRow, isTimed: Bool, entitiesByID: [String: EntitySummary]
    ) -> [InkLinkSegment] {
        var raw = InkLinkMapping.segments(from: task.text, entitiesByID: entitiesByID)
        if isTimed, let first = raw.first, first.kind == .plain {
            let stripped = DaySchedulePresentation.strippingLeadingTime(from: first.text)
            if stripped.isEmpty {
                raw.removeFirst()
            } else {
                raw[0] = InkLinkSegment(
                    id: first.id, text: stripped, kind: first.kind,
                    target: first.target, path: first.path)
            }
        }
        return DaySchedulePresentation.splitSegmentsByLine(raw).first ?? raw
    }

    func openScheduleLink(_ url: URL) {
        scheduleLinkDestination = EntityLinkDestination.from(
            url: url, entities: store.content.entities)
    }
}

/// Shared past-day schedule card chrome: leading slot, title, meta, optional extra, chevron.
struct ScheduleEntryCard<Leading: View, Title: View, Extra: View>: View {
    let isSelected: Bool
    let hairline: CGFloat
    let meta: String
    let spokenLabel: String
    let spokenValue: String
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let title: () -> Title
    @ViewBuilder let extra: () -> Extra

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            leading()

            VStack(alignment: .leading, spacing: 4) {
                title()

                Text(verbatim: meta)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)

                extra()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: spokenLabel))
            .accessibilityValue(Text(verbatim: spokenValue))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { onTap() }
            .accessibilityAction(named: Text("Metni düzenle"), onEdit)
            .accessibilityAction(named: Text("Sil"), onDelete)

            Image(systemName: "chevron.right")
                .font(.ink.meta.weight(.semibold))
                .foregroundStyle(Color.ink.tertiaryText)
                .accessibilityHidden(true)
        }
        .modifier(ScheduleCardChrome(isSelected: isSelected, hairline: hairline))
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button(action: onEdit) {
                Label("Metni düzenle", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Sil", systemImage: "trash")
            }
        }
    }
}
