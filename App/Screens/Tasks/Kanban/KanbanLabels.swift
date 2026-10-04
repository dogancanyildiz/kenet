import SwiftUI

extension KanbanColumn {
    var title: Text {
        if let name { return Text(verbatim: name) }
        switch destination {
        case .status(let status):
            switch status {
            case .todo, .unknown: return Text("Yapılacak")
            case .inProgress: return Text("Devam")
            case .done: return Text("Bitti")
            case .cancelled: return Text("İptal")
            }
        case .project: return Text("Projesiz")
        case .person: return Text("Kişisiz")
        }
    }
}
