import SwiftUI

extension KanbanColumn {
    /// Localized column title for VoiceOver action names.
    var localizedTitle: String {
        if let name { return name }
        switch destination {
        case .status(let status):
            switch status {
            case .todo, .unknown: return String(localized: "Yapılacak")
            case .inProgress: return String(localized: "Devam")
            case .done: return String(localized: "Bitti")
            case .cancelled: return String(localized: "İptal")
            }
        case .project: return String(localized: "Projesiz")
        case .person: return String(localized: "Kişisiz")
        }
    }

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
