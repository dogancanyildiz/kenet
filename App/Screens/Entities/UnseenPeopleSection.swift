import SwiftUI

struct UnseenPeopleSection: View {
    let store: IndexStore
    let people: [EntitySummary]
    var select: ((EntitySummary) -> Void)? = nil
    @AppStorage(PeopleInsightsPreference.key) private var threshold = PeopleInsightsPreference.defaultDays
    @Environment(IntentNavigation.self) private var navigation
    @Environment(\.clockNow) private var clockNow
    @State private var expanded = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let groups = UnseenPeople.compute(
                people: people, content: store.content,
                today: LocalDay.today(at: clockNow()), threshold: threshold)
            DisclosureGroup(isExpanded: $expanded) {
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
            } label: {
                SectionHeader(title: String(localized: "Bir süredir görüşmediklerin"))
            }
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
