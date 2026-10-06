import Summaries
import SwiftUI
import VaultFormat

struct SummariesView: View {
    let store: IndexStore
    @State private var model: SummariesModel
    init(store: IndexStore, today: @escaping () -> CalendarDate = { LocalDay.today() }) {
        self.store = store
        _model = State(initialValue: SummariesModel(store: store, today: today))
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if model.isLoading {
                        InkProgress(kind: .indeterminate(label: "Yükleniyor…"))
                    }
                    if let error = model.errorText {
                        InfoBand(kind: .error, verbatim: error)
                    }
                    if let summary = model.summary {
                        if summary.isEmpty {
                            EmptyState("Bu dönemde kayıt yok.")
                        }
                        Text("Önceki dönemle fark")
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                        dailySection(summary)
                        SummaryEntityCard(
                            store: store, title: String(localized: "Kişiler"), entities: summary.people,
                            mentions: summary.counts.peopleMentions, first: summary.counts.firstPeople,
                            mentionChange: summary.change.peopleMentions,
                            firstChange: summary.change.firstPeople)
                        SummaryEntityCard(
                            store: store, title: String(localized: "Konumlar"), entities: summary.places,
                            mentions: summary.counts.placeMentions, first: summary.counts.firstPlaces,
                            mentionChange: summary.change.placeMentions,
                            firstChange: summary.change.firstPlaces)
                        SummaryGoalCard(goals: summary.goals)
                        tasksSection(summary)
                    }
                }
                .padding(InkSpacing.margin)
                .inkPageColumn()
            }
        }
        .inkPage()
        .inkPageTitle("Özetler")
        .toolbar { SearchButton() }
        .task(id: requestID) { await model.load() }
        .onChange(of: store.vaultURL) { _, _ in model.reset() }
    }

    private func dailySection(_ summary: PeriodSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "Günlük"))
            SummaryMetric(
                title: "Olay sayısı", value: summary.counts.events, change: summary.change.events)
            SummaryMetric(
                title: "Yazılan gün", value: summary.counts.writtenDays,
                change: summary.change.writtenDays)
        }
    }

    private func tasksSection(_ summary: PeriodSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "Görevler"))
            SummaryMetric(
                title: "Oluşturulan", value: summary.counts.createdTasks,
                change: summary.change.createdTasks)
            SummaryMetric(
                title: "Tamamlanan", value: summary.counts.completedTasks,
                change: summary.change.completedTasks)
            SummaryMetric(
                title: "Dönem sonunda devreden", value: summary.counts.overdueTasks,
                change: summary.change.overdueTasks)
            SummaryMetric(
                title: "Tarihsiz açık", value: summary.counts.undatedTasks,
                change: summary.change.undatedTasks)
        }
    }

    private var requestID: String {
        model.period.rawValue + "|" + model.day.description + "|" + (store.vaultURL?.path ?? "") + "|"
            + String(store.lastUpdated?.timeIntervalSince1970 ?? 0)
    }
    private var controls: some View {
        VStack(spacing: 10) {
            Picker("Özet dönemi", selection: $model.period) {
                Text("Hafta").tag(SummaryPeriod.week)
                Text("Ay").tag(SummaryPeriod.month)
            }.pickerStyle(.segmented)
            HStack {
                Button {
                    model.previous()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(Color.ink.accent)
                        .tapTarget()
                }
                .accessibilityLabel("Önceki dönem").disabled(!model.canGoPrevious)
                Spacer()
                Text(LocalDay.instant(for: model.range.lowerBound), format: .dateTime.day().month().year())
                Text(verbatim: "–")
                Text(LocalDay.instant(for: model.range.upperBound), format: .dateTime.day().month().year())
                Spacer()
                Button {
                    model.next()
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.ink.accent)
                        .tapTarget()
                }
                .accessibilityLabel("Sonraki dönem").disabled(!model.canGoNext)
            }
            .font(.ink.byline)
            .foregroundStyle(Color.ink.text)
            Button(LocalizedStringKey(model.period == .week ? "Bu hafta" : "Bu ay")) {
                model.current()
            }
            .buttonStyle(InkTextButtonStyle())
        }
        .padding(InkSpacing.margin)
    }
}
