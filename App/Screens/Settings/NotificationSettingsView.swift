import SwiftUI

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

struct NotificationSettingsView: View {
    @Environment(NotificationService.self) private var service
    @Environment(\.openURL) private var openURL
    @Environment(\.timeZone) private var timeZone
    @Environment(\.clockNow) private var clockNow
    var body: some View {
        @Bindable var service = service
        List {
            #if os(iOS)
                InkPageTitleRow("Bildirimler")
            #endif
            Section {
                SectionHeader("İzin")
                    .inkListRow()
                InkCard(padded: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if service.authorization.canRequest {
                            Button("Bildirimlere izin ver") { Task { await service.requestAccess() } }
                                .buttonStyle(InkTextButtonStyle())
                                .disabled(service.isRequesting)
                                .padding(.horizontal, InkSpacing.cardPadding)
                            InkCardDivider()
                        }
                        Button("Sistem ayarlarını aç") { openSettings() }
                            .buttonStyle(InkTextButtonStyle())
                            .padding(.horizontal, InkSpacing.cardPadding)
                    }
                }
                .inkListRow()
                // The permission's state is the card's footnote, as on every settings page.
                Text(service.authorization.title)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
            }
            Section {
                SectionHeader("Hatırlatmalar")
                    .inkListRow()
                InkCard(padded: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Toggle("Görev hatırlatmaları", isOn: $service.preferences.tasksEnabled)
                            .frame(minHeight: InkButtonChrome.minimumHeight)
                            .padding(.horizontal, InkSpacing.cardPadding)
                        InkCardDivider()
                        InkTimePicker(title: "Görev saati", selection: time(\.taskTime))
                            .disabled(!service.preferences.tasksEnabled)
                            .frame(minHeight: InkButtonChrome.minimumHeight)
                            .padding(.horizontal, InkSpacing.cardPadding)
                        InkCardDivider()
                        Toggle("Günlük hedef hatırlatmaları", isOn: $service.preferences.goalsEnabled)
                            .frame(minHeight: InkButtonChrome.minimumHeight)
                            .padding(.horizontal, InkSpacing.cardPadding)
                        InkCardDivider()
                        InkTimePicker(title: "Hedef saati", selection: time(\.goalTime))
                            .disabled(!service.preferences.goalsEnabled)
                            .frame(minHeight: InkButtonChrome.minimumHeight)
                            .padding(.horizontal, InkSpacing.cardPadding)
                        InkCardDivider()
                        Toggle("Akşam günlük hatırlatması", isOn: $service.preferences.diaryEnabled)
                            .frame(minHeight: InkButtonChrome.minimumHeight)
                            .padding(.horizontal, InkSpacing.cardPadding)
                        InkCardDivider()
                        InkTimePicker(title: "Günlük saati", selection: time(\.diaryTime))
                            .disabled(!service.preferences.diaryEnabled)
                            .frame(minHeight: InkButtonChrome.minimumHeight)
                            .padding(.horizontal, InkSpacing.cardPadding)
                        InkCardDivider()
                        Toggle("Görüşme hatırlatmaları", isOn: $service.preferences.peopleEnabled)
                            .frame(minHeight: InkButtonChrome.minimumHeight)
                            .padding(.horizontal, InkSpacing.cardPadding)
                        InkCardDivider()
                        InkTimePicker(title: "Görüşme saati", selection: time(\.peopleTime))
                            .disabled(!service.preferences.peopleEnabled)
                            .frame(minHeight: InkButtonChrome.minimumHeight)
                            .padding(.horizontal, InkSpacing.cardPadding)
                        InkCardDivider()
                        Toggle("Bildirimde içeriği göster", isOn: showsContent)
                            .frame(minHeight: InkButtonChrome.minimumHeight)
                            .padding(.horizontal, InkSpacing.cardPadding)
                    }
                }
                .inkListRow()
                Text(
                    "Kapalıyken afiş, bildirim merkezi ve kilit ekranı yalnız sayı ve genel başlık gösterir: görev metni, hedef adları ve kişi adları görünmez."
                )
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
                InkCard(padded: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Button("Şimdi yeniden planla") { Task { await service.replanNow() } }
                            .buttonStyle(InkTextButtonStyle())
                            .disabled(service.isPlanning || service.isRequesting)
                            .padding(.horizontal, InkSpacing.cardPadding)
                        if service.pending.isEmpty {
                            InkCardDivider()
                            Text("Planlanan bildirim yok.")
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.secondaryText)
                                .frame(
                                    maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading
                                )
                                .padding(.horizontal, InkSpacing.cardPadding)
                        }
                        ForEach(service.pending) { request in
                            InkCardDivider()
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, InkSpacing.cardPadding)
                            .padding(.vertical, 10)
                        }
                    }
                }
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
            }
        }
        .listStyle(.plain)
        .inkToggle()
        .inkPageNavigationTitle("Bildirimler")
        .inkPageScrollColumn()
        .inkPage()
        .task { if AppLaunchPolicy.allowsAutomaticStart() { await service.replanNow() } }
    }
    /// The page asks to show content; the stored preference keeps its `hideContent` name.
    private var showsContent: Binding<Bool> {
        Binding(
            get: { !service.preferences.hideContent },
            set: { service.preferences.hideContent = !$0 })
    }
    private func time(_ key: WritableKeyPath<NotificationPreferences, NotificationTime>) -> Binding<Date> {
        Binding(
            get: {
                service.preferences.fieldDate(
                    key, on: LocalDay.today(at: clockNow(), timeZone: timeZone), timeZone: timeZone)
            },
            set: { service.preferences.setTime(key, from: $0, timeZone: timeZone) })
    }
    private func openSettings() {
        #if os(iOS)
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        #elseif os(macOS)
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        #endif
    }
}

/// Gizlilik › Bildirim içeriği (iPhone, iPad): only the switch the row names and its footnote.
/// The same switch stays on the Bildirimler page, where Mac shows it.
struct NotificationContentSettingsView: View {
    @Environment(NotificationService.self) private var service

    var body: some View {
        List {
            #if os(iOS)
                InkPageTitleRow("Bildirim içeriği")
            #endif
            Section {
                InkCard(padded: false) {
                    Toggle(
                        "Bildirimde içeriği göster",
                        isOn: Binding(
                            get: { !service.preferences.hideContent },
                            set: { service.preferences.hideContent = !$0 })
                    )
                    .frame(minHeight: InkButtonChrome.minimumHeight)
                    .padding(.horizontal, InkSpacing.cardPadding)
                }
                .inkListRow()
                Text(
                    "Kapalıyken afiş, bildirim merkezi ve kilit ekranı yalnız sayı ve genel başlık gösterir: görev metni, hedef adları ve kişi adları görünmez."
                )
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .inkListRow()
            }
        }
        .listStyle(.plain)
        .inkToggle()
        .inkPageNavigationTitle("Bildirim içeriği")
        .inkPageScrollColumn()
        .inkPage()
        .accessibilityIdentifier("screen.settings.notificationContent")
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
