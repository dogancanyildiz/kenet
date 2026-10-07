import SwiftUI
import VaultFormat

struct TaskDatePicker: View {
    @State private var selected: Date
    let current: CalendarDate?
    /// A sheet already draws on paper under a manşet that names the field; a popover needs its
    /// own surface and label.
    let isOnPage: Bool
    let commit: (CalendarDate?) -> Void

    init(current: CalendarDate?, isOnPage: Bool = false, commit: @escaping (CalendarDate?) -> Void) {
        self.current = current
        self.isOnPage = isOnPage
        self.commit = commit
        _selected = State(initialValue: LocalDay.instant(for: current ?? LocalDay.today()))
    }

    var body: some View {
        if isOnPage {
            // The sheet scaffold already supplies the page margin.
            content
        } else {
            content
                .padding()
                .frame(minWidth: 280)
                .inkSurface()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isOnPage {
                picker.labelsHidden()
            } else {
                picker
            }
            HStack {
                Button("Tarihi kaldır") { commit(nil) }
                    .disabled(current == nil)
                    .buttonStyle(InkTextButtonStyle())
                Spacer()
                if isOnPage {
                    Button("Tarihi seç") { commit(LocalDay.today(at: selected)) }
                        .buttonStyle(InkTextButtonStyle())
                        .fontWeight(.semibold)
                } else {
                    Button("Tarihi seç") { commit(LocalDay.today(at: selected)) }
                        .buttonStyle(InkPrimaryButtonStyle())
                }
            }
        }
    }

    private var picker: some View {
        DatePicker("Görev tarihi", selection: $selected, displayedComponents: .date)
            .environment(\.calendar, Calendar(identifier: .gregorian))
    }
}
