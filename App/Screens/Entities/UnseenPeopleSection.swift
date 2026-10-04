import SwiftUI

struct UnseenPeopleSection: View {
    let store: IndexStore
    let people: [EntitySummary]
    var select: ((EntitySummary) -> Void)? = nil
    @AppStorage(PeopleInsightsPreference.key) private var threshold = PeopleInsightsPreference.defaultDays
    @Environment(IntentNavigation.self) private var navigation
    @State private var expanded = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let groups = UnseenPeople.compute(
                people: people, content: store.content,
                today: LocalDay.today(at: context.date), threshold: threshold)
            DisclosureGroup("Bir süredir görüşmediklerin", isExpanded: $expanded) {
                if groups.overdue.isEmpty { Text("Bu süreyi aşan kayıt yok.").foregroundStyle(.secondary) }
                ForEach(groups.overdue) { person in personRow(person) }
                if !groups.never.isEmpty {
                    Text("Henüz hiç").font(.caption).foregroundStyle(.secondary)
                    ForEach(groups.never) { person in personRow(person) }
                }
            }
        }
    }
    private func personRow(_ person: UnseenPerson) -> some View {
        HStack {
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
            Spacer()
            Button {
                navigation.mention(person.entity, vault: store.vaultURL)
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless).accessibilityLabel("Hızlı girişte an")
        }
    }
    private func personLabel(_ person: UnseenPerson) -> some View {
        VStack(alignment: .leading) {
            EntityRow(entity: person.entity)
            if let days = person.elapsedDays {
                Group {
                    if days >= 7 { Text("\(days / 7) haftadır") } else { Text("\(days) gündür") }
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
