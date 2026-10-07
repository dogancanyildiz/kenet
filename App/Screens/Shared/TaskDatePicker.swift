import SwiftUI
import VaultFormat

struct TaskDatePicker: View {
    @State private var selected: Date
    let current: CalendarDate?
    let commit: (CalendarDate?) -> Void

    init(current: CalendarDate?, commit: @escaping (CalendarDate?) -> Void) {
        self.current = current
        self.commit = commit
        _selected = State(initialValue: LocalDay.instant(for: current ?? LocalDay.today()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("Görev tarihi", selection: $selected, displayedComponents: .date)
                .environment(\.calendar, Calendar(identifier: .gregorian))
            HStack {
                Button("Tarihi kaldır") { commit(nil) }
                    .disabled(current == nil)
                    .buttonStyle(InkTextButtonStyle())
                Spacer()
                Button("Tarihi seç") { commit(LocalDay.today(at: selected)) }
                    .buttonStyle(InkPrimaryButtonStyle())
            }
        }
        .padding()
        .frame(minWidth: 280)
        .inkSurface()
    }
}
