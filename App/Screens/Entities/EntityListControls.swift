import SwiftUI

struct EntityListControls: View {
    @Binding var order: EntityOrdering
    @Binding var search: String

    var body: some View {
        VStack {
            Picker("Sıralama", selection: $order) {
                Text("Ada göre").tag(EntityOrdering.name)
                Text("Son geçişe göre").tag(EntityOrdering.recent)
            }
            TextField("Kişi veya konum ara", text: $search).textFieldStyle(.roundedBorder)
        }.padding(.horizontal)
    }
}
