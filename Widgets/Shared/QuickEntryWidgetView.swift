import SwiftUI

/// Stateless entry point: no vault or snapshot is read.
struct QuickEntryWidgetView: View {
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "square.and.pencil")
                .font(.largeTitle)
                .foregroundStyle(WidgetTheme.accent)
            Spacer(minLength: 0)
            Text("widget.write.title")
                .font(WidgetTheme.name)
                .foregroundStyle(WidgetTheme.text)
            Text(date, format: .dateTime.day().month(.wide))
                .font(WidgetTheme.meta)
                .foregroundStyle(WidgetTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
