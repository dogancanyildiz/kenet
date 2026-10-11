import SwiftUI
import VaultFormat
import VaultIndex

/// Snapshot hosts wait until the unlinked-mention query has answered.
struct UnlinkedMentionsReadyKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// Loads unlinked spellings from outside the list. A `List` never mounts an empty row,
/// so a `.task` on the section would not start while there is nothing to draw.
struct UnlinkedMentionsLoader: View {
    let model: UnlinkedMentionsModel
    let file: String

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task(
                id: UnlinkedMentionsLoadKey(
                    file: file, vault: model.store.vaultURL, revision: model.store.lastUpdated)
            ) {
                guard model.store.lastUpdated != nil else { return }
                if let entity = model.store.knownEntities.first(where: { $0.file == file }) {
                    await model.load(entity)
                } else {
                    model.markUnavailable()
                }
            }
    }
}

struct UnlinkedMentionsLoadKey: Hashable {
    let file: String
    let vault: URL?
    let revision: Date?
}

/// Unlinked event and task spellings for one entity. Hidden when there is nothing to show.
struct UnlinkedMentionsSection: View {
    let model: UnlinkedMentionsModel
    @State private var expanded = false

    private var store: IndexStore { model.store }

    var body: some View {
        if model.showsStaleNotice || !model.mentions.isEmpty {
            Section {
                if model.showsStaleNotice {
                    InfoBand(kind: .warning, "Satır değişmiş, bağlanmadı.")
                        .accessibilityIdentifier("entity.unlinkedMentions.stale")
                        .inkListRow()
                }
                if !model.mentions.isEmpty {
                    SectionHeader("Bağlanmamış anmalar", count: model.mentions.count)
                        .accessibilityIdentifier("entity.unlinkedMentions")
                        .inkListRow()
                    let total = model.mentions.count
                    let limit = UnlinkedMentionList.visibleCount(total: total, expanded: expanded)
                    ForEach(Array(model.mentions.prefix(limit)), id: \.rowIdentity) { mention in
                        row(mention)
                    }
                    if UnlinkedMentionList.showsAll(total: total, expanded: expanded) {
                        Button {
                            expanded = true
                        } label: {
                            Text("Tümünü göster (\(total))")
                                .tapTarget()
                        }
                        .buttonStyle(InkTextButtonStyle())
                        .accessibilityIdentifier("button.unlinkedMention.showAll")
                        .inkListRow()
                    }
                }
            }
        }
    }

    private func row(_ mention: UnlinkedMention) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            NavigationLink {
                DayView(store: store, date: mention.date)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalDay.instant(for: mention.date), format: .dateTime.day().month().year())
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                    Text(MentionByteRange.styled(mention.lineText, utf8: mention.position.byteRange))
                        .font(.ink.content)
                        .foregroundStyle(.ink.text)
                    if mention.isAmbiguous {
                        Text("Başka bir kayıtla da eşleşiyor")
                            .font(.ink.meta)
                            .foregroundStyle(.ink.secondaryText)
                    }
                    if mention.isCaseMismatch {
                        Text("Yazımı farklı")
                            .font(.ink.meta)
                            .foregroundStyle(.ink.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .tapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("entity.unlinkedMention")
            if let entity = model.entity {
                Button {
                    Task { await model.link(mention, to: entity) }
                } label: {
                    Text("Bağla")
                        .tapTarget()
                        .accessibilityIdentifier("button.unlinkedMention.link")
                }
                .buttonStyle(InkTextButtonStyle())
                .disabled(model.isLinking)
            }
        }
        .inkListRow()
    }
}

extension UnlinkedMention {
    /// One spelling on one line. Two occurrences of the same name stay distinct.
    fileprivate var rowIdentity: String {
        "\(file)|\(position.line)|\(position.byteRange.lowerBound)|\(position.byteRange.upperBound)"
    }
}
