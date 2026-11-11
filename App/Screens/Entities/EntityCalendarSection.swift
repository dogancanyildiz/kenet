import SwiftUI
import VaultFormat

/// The person's upcoming calendar events, matched by name or alias in the title or among the
/// attendees (decision 2026-11-11). The vault stays as it is: nothing here writes a file.
@MainActor @Observable
final class EntityCalendarModel {
    private(set) var result: CalendarPersonEvents?

    func load(calendar: CalendarService, names: CalendarPersonNames, now: Date) async {
        // From the start of today: an event already under way today still counts.
        let answer = await calendar.personEvents(names: names, from: Calendar.current.startOfDay(for: now))
        guard !Task.isCancelled else { return }
        result = answer
    }
}

struct EntityCalendarLoadKey: Hashable {
    let fullName: String
    let aliases: [String]
    let changes: Int
    let canRead: Bool
}

/// List rows of the section; the model is loaded from the page (an empty row is never mounted).
struct EntityCalendarSection: View {
    let names: CalendarPersonNames
    /// The person file's birthday field, read only; it fills the form's date.
    let birthday: PersonBirthday?
    let model: EntityCalendarModel
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var route: CalendarSheetRoute?
    @ScaledMetric(relativeTo: .body) private var badgeSide: CGFloat = 32

    var body: some View {
        if let result = model.result {
            Section {
                // The action is a small link right of the title, like "Bağ kur" (drawing). When the
                // dated label does not fit, the date goes; only at large text the link goes under.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        header(result)
                        birthdayButton(result, dated: true).fixedSize()
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        header(result)
                        birthdayButton(result, dated: false).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        header(result)
                        birthdayButton(result, dated: false)
                    }
                }
                // On the always-present header row: a sheet on a `Section` never presents.
                .sheet(item: $route) { CalendarSheet(route: $0) }
                .inkListRow()
                // One card per event, as the page's timeline rows: calendar badge, title, the day
                // under it, a chevron.
                ForEach(result.upcoming) { event in
                    row(event).inkListRow()
                }
            }
        }
    }

    /// The section title; the event count beside it ("2 etkinlik") when no action sits there.
    private func header(_ result: CalendarPersonEvents) -> SectionHeader {
        let showsCount = result.birthday != nil && !result.upcoming.isEmpty
        return SectionHeader(
            "Yaklaşan etkinlikler",
            counter: showsCount
                ? PresentationLocalization.string(localized: "\(result.upcoming.count) etkinlik", locale: locale)
                : nil)
    }

    @ViewBuilder private func birthdayButton(_ result: CalendarPersonEvents, dated: Bool) -> some View {
        if result.birthday == nil {
            Button {
                route = .birthday(names, birthday: birthday)
            } label: {
                // A small link beside the section title (drawing), not a title-sized one: the
                // text button style's own font is the larger byline.
                birthdayLabel(dated: dated)
                    .font(.subheadline.weight(.semibold))
                    .tapTarget()
            }
            .buttonStyle(InkTextButtonStyle())
            .accessibilityIdentifier("button.entity.addBirthday")
        }
    }

    /// "Doğum günü ekle", with the file's date when there is one: "Doğum günü ekle · 12 Nis".
    private func birthdayLabel(dated: Bool) -> Text {
        guard dated, let birthday, let day = birthday.firstDay(currentYear: 2000) else {
            return Text("Doğum günü ekle")
        }
        let date = LocalDay.instant(for: day).formatted(.dateTime.day().month(.abbreviated).locale(locale))
        return Text("Doğum günü ekle · \(date)")
    }

    private func row(_ event: CalendarEvent) -> some View {
        let text = CalendarEventText(locale: locale)
        let meta = ([text.when(event)] + [text.caption(event)].filter { !$0.isEmpty }).joined(separator: " · ")
        return Button {
            route = .detail(event, day: nil)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "calendar")
                    .font(.footnote)
                    .foregroundStyle(Color.ink.accent)
                    .frame(width: badgeSide, height: badgeSide)
                    .background(
                        Color.ink.accentSoft, in: RoundedRectangle(cornerRadius: InkCorner.xs, style: .continuous)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: text.title(event))
                        .font(.subheadline)
                        .foregroundStyle(.ink.text)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: meta)
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.ink.tertiaryText)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(minHeight: 56)
            .modifier(InkCardModifier(cornerRadius: InkCorner.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("row.entity.calendarEvent")
    }
}
