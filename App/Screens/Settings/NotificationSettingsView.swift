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
        Form {
            Section("İzin") {
                Text(service.authorization.title)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.text)
                if service.authorization.canRequest {
                    Button("Bildirimlere izin ver") { Task { await service.requestAccess() } }.disabled(
                        service.isRequesting)
                }
                Button("Sistem ayarlarını aç") { openSettings() }
            }
            Section("Hatırlatmalar") {
                Toggle("Görev hatırlatmaları", isOn: $service.preferences.tasksEnabled)
                DatePicker("Görev saati", selection: time(\.taskTime), displayedComponents: .hourAndMinute)
                    .disabled(!service.preferences.tasksEnabled)
                Toggle("Günlük hedef hatırlatmaları", isOn: $service.preferences.goalsEnabled)
                DatePicker("Hedef saati", selection: time(\.goalTime), displayedComponents: .hourAndMinute)
                    .disabled(!service.preferences.goalsEnabled)
                Toggle("Akşam günlük hatırlatması", isOn: $service.preferences.journalEnabled)
                DatePicker("Günlük saati", selection: time(\.journalTime), displayedComponents: .hourAndMinute)
                    .disabled(!service.preferences.journalEnabled)
                Toggle("Bildirimlerde içeriği gizle", isOn: $service.preferences.hideContent)
                Text("Afiş, bildirim merkezi ve kilit ekranında görev metni ve hedef adları gösterilmez.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                Text("Uygulama kapalıyken planlanan hatırlatmalar değişmez.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
            }
            Section("Planlananlar") {
                Button("Şimdi yeniden planla") { Task { await service.replanNow() } }.disabled(
                    service.isPlanning || service.isRequesting)
                if service.isPlanning {
                    InkProgress(kind: .indeterminate(label: "Bildirimler planlanıyor…"))
                }
                if let error = service.errorText {
                    Text(verbatim: error)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                }
                if service.pending.isEmpty {
                    Text("Planlanan bildirim yok.")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
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
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Bildirimler")
        .inkPage()
        .inkPageColumn()
        .task { if AppLaunchPolicy.allowsAutomaticStart() { await service.replanNow() } }
    }
    private func time(_ key: WritableKeyPath<NotificationPreferences, NotificationTime>) -> Binding<Date> {
        Binding(
            get: {
                let time = service.preferences[keyPath: key]
                return NotificationPlanner.fireDate(LocalDay.today(), time: time, timeZone: .current) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                service.preferences[keyPath: key] = NotificationTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
            })
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
