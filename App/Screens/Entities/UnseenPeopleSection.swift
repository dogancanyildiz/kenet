import SwiftUI

struct UnseenPeopleSection: View {
    let store: IndexStore
    let people: [EntitySummary]
    var select: ((EntitySummary) -> Void)? = nil
    var initiallyExpanded: Bool = false
    @AppStorage(PeopleInsightsPreference.key) private var threshold = PeopleInsightsPreference.defaultDays
    @Environment(IntentNavigation.self) private var navigation
    @Environment(\.clockNow) private var clockNow
    @Environment(\.displayScale) private var displayScale
    @State private var expanded: Bool

    init(
        store: IndexStore,
        people: [EntitySummary],
        select: ((EntitySummary) -> Void)? = nil,
        initiallyExpanded: Bool = false
    ) {
        self.store = store
        self.people = people
        self.select = select
        self.initiallyExpanded = initiallyExpanded
        _expanded = State(initialValue: initiallyExpanded)
    }

    /// Bumped once a minute so the day boundary moves the list without a vault change.
    @State private var minute = 0

    // The rows are direct `List` children: a wrapping container (`TimelineView`,
    // `DisclosureGroup`) keeps the row modifiers from reaching the list and leaves a white row.
    var body: some View {
        let _ = minute
        let groups = UnseenPeople.compute(
            people: people, content: store.content,
            today: LocalDay.today(at: clockNow()), threshold: threshold)
        Button {
            expanded.toggle()
        } label: {
            SectionHeader(
                title: String(localized: "Bir süredir görüşmediklerin"),
                isExpanded: expanded
            )
            .frame(minHeight: TapTarget.minimumLength, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(expanded ? Text("Genişletilmiş") : Text("Daraltılmış"))
        .inkListRow()
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                minute &+= 1
            }
        }
        if expanded {
            if groups.overdue.isEmpty {
                Text("Bu süreyi aşan kayıt yok.")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                    .inkListRow()
            }
            ForEach(groups.overdue) { person in
                personRow(person)
                    .inkListRow()
            }
            if !groups.never.isEmpty {
                Text("Henüz hiç")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                    .inkListRow()
                ForEach(groups.never) { person in
                    personRow(person)
                        .inkListRow()
                }
            }
            Rectangle()
                .fill(Color.ink.rule)
                .frame(height: InkStroke.hairline(scale: displayScale))
                .accessibilityHidden(true)
                .inkListRow()
        }
    }

    private func personRow(_ person: UnseenPerson) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Group {
                if let select {
                    Button {
                        select(person.entity)
                    } label: {
                        personLabel(person)
                    }.buttonStyle(.plain)
                } else {
                    NavigationLink(value: person.entity) { personLabel(person) }
                }
            }
            Spacer(minLength: 0)
            Button {
                navigation.mention(person.entity, vault: store.vaultURL)
            } label: {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(.ink.accent)
                    .tapTarget()
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Hızlı girişte an")
        }
    }

    private func personLabel(_ person: UnseenPerson) -> some View {
        MarginRow(kind: .vault, time: nil) {
            Text(verbatim: person.entity.name)
                .foregroundStyle(.ink.text)
        } secondary: {
            VStack(alignment: .leading, spacing: 2) {
                if let qualifier = person.entity.qualifier {
                    Text(verbatim: qualifier)
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                }
                if let days = person.elapsedDays {
                    Group {
                        if days >= 7 {
                            Text("\(days / 7) haftadır")
                        } else {
                            Text("\(days) gündür")
                        }
                    }
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                }
            }
        }
    }
}
