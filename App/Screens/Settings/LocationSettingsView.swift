import SwiftUI

#if os(iOS)
    import UIKit
#endif

struct LocationSettingsView: View {
    @Environment(LocationService.self) private var location
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var location = location
        Group {
            Section {
                SectionHeader("Konum")
                    .inkListRow()
                InkCard(padded: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Toggle("Konum önerisi", isOn: $location.isEnabled)
                            .frame(minHeight: InkButtonChrome.minimumHeight)
                            .padding(.horizontal, InkSpacing.cardPadding)
                        InkCardDivider()
                        switch location.authorization {
                        case .notDetermined:
                            Text("Konum izni henüz verilmedi.")
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.secondaryText)
                                .frame(
                                    maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading
                                )
                                .padding(.horizontal, InkSpacing.cardPadding)
                            InkCardDivider()
                            Button("Konum önerileri için izin ver") { location.requestAccess() }
                                .disabled(location.isRequesting)
                                .frame(
                                    maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading
                                )
                                .padding(.horizontal, InkSpacing.cardPadding)
                        case .authorized, .always:
                            Text("Konum erişimine izin verildi.")
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.text)
                                .frame(
                                    maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading
                                )
                                .padding(.horizontal, InkSpacing.cardPadding)
                        case .denied:
                            Text("Konum erişimi reddedildi.")
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.secondaryText)
                                .frame(
                                    maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading
                                )
                                .padding(.horizontal, InkSpacing.cardPadding)
                        case .restricted:
                            Text("Konum erişimi bu cihazda kısıtlanmış.")
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.secondaryText)
                                .frame(
                                    maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading
                                )
                                .padding(.horizontal, InkSpacing.cardPadding)
                        }
                        InkCardDivider()
                        Button("Sistem ayarlarını aç") {
                            #if os(iOS)
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            #else
                                if let url = URL(
                                    string:
                                        "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
                                ) {
                                    openURL(url)
                                }
                            #endif
                        }
                        .frame(maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading)
                        .padding(.horizontal, InkSpacing.cardPadding)
                    }
                }
                .inkListRow()
                Text("Hızlı girişteki konum önerisi tek seferlik konumla çalışır; olayına kendiliğinden eklenmez.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
            }
            #if os(iOS)
                GeofenceSettingsView()
            #endif
        }
        .onAppear { location.refreshAuthorization() }
    }
}
