import SwiftUI

extension KanbanMoveTarget {
    /// Localized column title for VoiceOver action names and headers.
    /// Pass the SwiftUI environment locale so `-testLanguage` does not override snapshot pinning.
    func localizedTitle(locale: Locale = .current) -> String {
        if let name { return name }
        switch destination {
        case .status(let status):
            switch status {
            case .todo, .unknown: return PresentationLocalization.string(localized: "Yapılacak", locale: locale)
            case .inProgress: return PresentationLocalization.string(localized: "Devam", locale: locale)
            case .done: return PresentationLocalization.string(localized: "Bitti", locale: locale)
            case .cancelled: return PresentationLocalization.string(localized: "İptal", locale: locale)
            }
        case .project: return PresentationLocalization.string(localized: "Projesiz", locale: locale)
        case .person: return PresentationLocalization.string(localized: "Kişisiz", locale: locale)
        }
    }

    /// Convenience for call sites outside a view (defaults to ``Locale.current``).
    var localizedTitle: String { localizedTitle(locale: .current) }

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
