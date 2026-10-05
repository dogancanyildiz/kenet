import Summaries
import SwiftUI

struct SummariesView: View {
    let store: IndexStore
    @State private var model: SummariesModel
    init(store: IndexStore) {
        self.store = store
        _model = State(initialValue: SummariesModel(store: store))
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.isLoading { ProgressView() }
                    if let error = model.errorText { Text(verbatim: error).foregroundStyle(.red) }
                    if let summary = model.summary {
                        if summary.isEmpty { Text("Bu dönemde kayıt yok.").foregroundStyle(.secondary) }
                        Text("Önceki dönemle fark").font(.caption).foregroundStyle(.secondary)
                        GroupBox("Günlük") {
                            VStack(spacing: 10) {
                                SummaryMetric(
                                    title: "Olay sayısı", value: summary.counts.events, change: summary.change.events)
                                SummaryMetric(
                                    title: "Yazılan gün", value: summary.counts.writtenDays,
                                    change: summary.change.writtenDays)
                            }.padding(.top, 8)
                        }
                        SummaryEntityCard(
                            store: store, title: "Kişiler", entities: summary.people,
                            mentions: summary.counts.peopleMentions, first: summary.counts.firstPeople,
                            mentionChange: summary.change.peopleMentions, firstChange: summary.change.firstPeople)
                        SummaryEntityCard(
                            store: store, title: "Konumlar", entities: summary.places,
                            mentions: summary.counts.placeMentions, first: summary.counts.firstPlaces,
                            mentionChange: summary.change.placeMentions, firstChange: summary.change.firstPlaces)
                        SummaryGoalCard(goals: summary.goals)
                        GroupBox("Görevler") {
                            VStack(spacing: 10) {
                                SummaryMetric(
                                    title: "Oluşturulan", value: summary.counts.createdTasks,
                                    change: summary.change.createdTasks)
                                SummaryMetric(
                                    title: "Tamamlanan", value: summary.counts.completedTasks,
                                    change: summary.change.completedTasks)
                                SummaryMetric(
                                    title: "Dönem sonunda geciken", value: summary.counts.overdueTasks,
                                    change: summary.change.overdueTasks)
                                SummaryMetric(
                                    title: "Tarihsiz açık", value: summary.counts.undatedTasks,
                                    change: summary.change.undatedTasks)
                            }.padding(.top, 8)
                        }
                    }
                }.padding().frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Özetler").toolbar { SearchButton() }
        .task(id: requestID) { await model.load() }
        .onChange(of: store.vaultURL) { _, _ in model.reset() }
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
                        .tapTarget()
                }
                .accessibilityLabel("Sonraki dönem").disabled(!model.canGoNext)
            }.font(.subheadline)
            Button(LocalizedStringKey(model.period == .week ? "Bu hafta" : "Bu ay")) { model.current() }
        }.padding()
    }
}
