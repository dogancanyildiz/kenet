import SwiftUI

/// Top-level Settings destinations shared by iPhone (list) and Mac (tabs).
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case privacy
    case notifications
    case calendarAndLocation
    case vault
    case diagnostics

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .privacy: "Gizlilik"
        case .notifications: "Bildirimler"
        case .calendarAndLocation: "Takvim ve Konum"
        case .vault: "Kasa"
        case .diagnostics: "Tanılama"
        }
    }

    var symbol: String {
        switch self {
        case .privacy: "lock"
        case .notifications: "bell"
        case .calendarAndLocation: "calendar"
        case .vault: "folder"
        case .diagnostics: "wrench.and.screwdriver"
        }
    }
}
