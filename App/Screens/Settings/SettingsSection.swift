import SwiftUI

/// Top-level Settings destinations shared by iPhone (list) and Mac (tabs).
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case quickEntry
    case privacy
    case notifications
    case calendarAndLocation
    case vault
    case diagnostics

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .quickEntry: "Hızlı giriş"
        case .privacy: "Gizlilik"
        case .notifications: "Bildirimler"
        case .calendarAndLocation: "Takvim ve Konum"
        case .vault: "Kasa"
        case .diagnostics: "Tanılama"
        }
    }

    var symbol: String {
        switch self {
        case .quickEntry: "square.and.pencil"
        case .privacy: "lock"
        case .notifications: "bell"
        case .calendarAndLocation: "calendar"
        case .vault: "folder"
        case .diagnostics: "wrench.and.screwdriver"
        }
    }

    /// The line under the title in the iPhone and iPad hub: what the page holds.
    @MainActor var summary: LocalizedStringResource {
        switch self {
        case .quickEntry:
            DeviceIdiom.current == .phone ? "Siri, Kısayollar, Eylem düğmesi" : "Siri, Kısayollar"
        case .privacy: "Uygulama kilidi, kişi hatırlatmaları"
        case .notifications: "Hatırlatmalar, planlanan bildirimler"
        case .calendarAndLocation: "Takvim izni, konuma girince"
        case .vault: "Konum, varlık tipleri"
        case .diagnostics: "İndeks sayıları, kopya dosyalar"
        }
    }
}
