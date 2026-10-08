import SwiftUI

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

struct NotificationSettingsView: View {
    @Environment(NotificationService.self) private var service
    @Environment(\.openURL) private var openURL
    var body: some View {
        @Bindable var service = service
        List {
            #if os(iOS)
                InkPageTitleRow("Bildirimler")
            #endif
            Section {
                SectionHeader("İzin")
                    .inkListRow()
                Text(service.authorization.title)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.text)
                    .inkListRow()
                if service.authorization.canRequest {
                    Button("Bildirimlere izin ver") { Task { await service.requestAccess() } }
                        .buttonStyle(InkTextButtonStyle())
                        .disabled(service.isRequesting)
                        .inkListRow()
                }
                Button("Sistem ayarlarını aç") { openSettings() }
                    .buttonStyle(InkTextButtonStyle())
                    .inkListRow()
            }
            Section {
                SectionHeader("Hatırlatmalar")
                    .inkListRow()
                Toggle("Görev hatırlatmaları", isOn: $service.preferences.tasksEnabled)
                    .inkListRow()
                InkTimePicker(title: "Görev saati", selection: time(\.taskTime))
                    .disabled(!service.preferences.tasksEnabled)
                    .inkListRow()
                Toggle("Günlük hedef hatırlatmaları", isOn: $service.preferences.goalsEnabled)
                    .inkListRow()
                InkTimePicker(title: "Hedef saati", selection: time(\.goalTime))
                    .disabled(!service.preferences.goalsEnabled)
                    .inkListRow()
                Toggle("Akşam günlük hatırlatması", isOn: $service.preferences.journalEnabled)
                    .inkListRow()
                InkTimePicker(title: "Günlük saati", selection: time(\.journalTime))
                    .disabled(!service.preferences.journalEnabled)
                    .inkListRow()
                Toggle("Bildirimlerde içeriği gizle", isOn: $service.preferences.hideContent)
                    .inkListRow()
                Text("Afiş, bildirim merkezi ve kilit ekranında görev metni ve hedef adları gösterilmez.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
                Text("Uygulama kapalıyken planlanan hatırlatmalar değişmez.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
            }
            Section {
                SectionHeader("Planlananlar")
                    .inkListRow()
                Button("Şimdi yeniden planla") { Task { await service.replanNow() } }
                    .buttonStyle(InkTextButtonStyle())
                    .disabled(service.isPlanning || service.isRequesting)
                    .inkListRow()
                if service.isPlanning {
                    InkProgress(kind: .indeterminate(label: "Bildirimler planlanıyor…"))
                        .inkListRow()
                }
                if let error = service.errorText {
                    Text(verbatim: error)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        .inkListRow()
                }
                if service.pending.isEmpty {
                    Text("Planlanan bildirim yok.")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        .inkListRow()
                }
                ForEach(service.pending) { request in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: request.title)
                            .font(.ink.content)
                            .foregroundStyle(Color.ink.text)
                        Text(request.date, format: .dateTime.day().month().year().hour().minute())
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                            .monospacedDigit()
                        Text(verbatim: request.id)
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    .inkListRow()
                }
            }
        }
        .listStyle(.plain)
        .inkToggle()
        .inkPageNavigationTitle("Bildirimler")
        .inkPageColumn()
        .inkPage()
        .task { if AppLaunchPolicy.allowsAutomaticStart() { await service.replanNow() } }
    }
    private func time(_ key: WritableKeyPath<NotificationPreferences, NotificationTime>) -> Binding<Date> {
        Binding(
            get: { service.preferences.fieldDate(key, on: LocalDay.today(), timeZone: .current) },
            set: { service.preferences.setTime(key, from: $0, timeZone: .current) })
    }
    private func openSettings() {
        #if os(iOS)
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        #elseif os(macOS)
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        #endif
    }
}

extension NotificationAuthorization {
    var title: LocalizedStringKey {
        switch self {
        case .notDetermined: "Bildirim izni henüz istenmedi."
        case .denied: "Bildirim izni kapalı. Sistem ayarlarından açabilirsin."
        case .authorized: "Bildirimlere izin verildi."
        case .provisional: "Bildirimler sessiz olarak teslim edilir."
        case .ephemeral: "Bildirim izni geçici olarak verildi."
        case .unknown: "Bildirim izin durumu okunamadı."
        }
    }
}
