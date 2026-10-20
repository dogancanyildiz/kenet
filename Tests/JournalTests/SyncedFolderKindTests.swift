import Foundation
import Testing

@testable import Journal

/// Tablo ve bağdaştırıcı testleri: eşitlenen klasör türlerinin yol kalıpları,
/// dosya sistemi yazımları (büyük/küçük harf, NFC/NFD, /private/var ve sembolik bağ)
/// ile isUbiquitous bayrağı üzerinden tespiti.
struct SyncedFolderKindTests {
    struct TableRow: Sendable, CustomTestStringConvertible {
        let path: String
        let isUbiquitous: Bool?
        let expected: SyncedFolderKind?
        let title: String

        var testDescription: String {
            "\(title): \(path) (isUbiquitous: \(String(describing: isUbiquitous))) -> \(String(describing: expected))"
        }
    }

    private static let tableCases: [TableRow] = [
        // MARK: - Yerel klasörler (nil)
        TableRow(
            path: "/Users/ornek/Documents/Vault",
            isUbiquitous: false,
            expected: nil,
            title: "Yerel Documents/Vault (isUbiquitous=false)"
        ),
        TableRow(
            path: "/Users/ornek/Documents/Vault",
            isUbiquitous: nil,
            expected: nil,
            title: "Yerel Documents/Vault (isUbiquitous=nil)"
        ),
        TableRow(
            path: "Documents/Vault",
            isUbiquitous: nil,
            expected: nil,
            title: "Göreli Documents/Vault"
        ),
        TableRow(
            path: "/Users/ornek/Desktop/Vault",
            isUbiquitous: nil,
            expected: nil,
            title: "Yerel Desktop/Vault"
        ),
        TableRow(
            path: "/private/var/mobile/Containers/Data/Application/ABC-123/Documents/Vault",
            isUbiquitous: false,
            expected: nil,
            title: "iOS yerel uygulama Documents (/private/var)"
        ),
        TableRow(
            path: "/var/mobile/Containers/Data/Application/ABC-123/Documents/Vault",
            isUbiquitous: nil,
            expected: nil,
            title: "iOS yerel uygulama Documents (/var)"
        ),

        // MARK: - iCloud Belgeler / Masaüstü (isUbiquitous)
        TableRow(
            path: "/Users/ornek/Documents/Vault",
            isUbiquitous: true,
            expected: .iCloudDrive,
            title: "iCloud Belgeler (isUbiquitous=true)"
        ),
        TableRow(
            path: "/Users/ornek/Desktop/Vault",
            isUbiquitous: true,
            expected: .iCloudDrive,
            title: "iCloud Masaüstü (isUbiquitous=true)"
        ),
        TableRow(
            path: "/Users/ornek/OzelKlasor/Vault",
            isUbiquitous: true,
            expected: .iCloudDrive,
            title: "iCloud bayraklı herhangi bir yol"
        ),

        // MARK: - iCloud Drive yol kalıpları
        TableRow(
            path: "/Users/ornek/Library/Mobile Documents/com~apple~CloudDocs/Documents/Vault",
            isUbiquitous: nil,
            expected: .iCloudDrive,
            title: "iCloud Drive tam yol"
        ),
        TableRow(
            path: "/Users/ornek/Library/Mobile Documents/com~apple~CloudDocs",
            isUbiquitous: nil,
            expected: .iCloudDrive,
            title: "iCloud Drive CloudDocs kök klasörü"
        ),
        TableRow(
            path: "/Users/ornek/Library/Mobile Documents/iCloud~com~example~app/Documents",
            isUbiquitous: nil,
            expected: .iCloudDrive,
            title: "Library/Mobile Documents/ (CloudDocs harici kapsayıcı)"
        ),
        TableRow(
            path: "/Users/ornek/Library/Mobile Documents",
            isUbiquitous: nil,
            expected: .iCloudDrive,
            title: "Library/Mobile Documents takısız yol"
        ),
        TableRow(
            path: "/Users/ornek/Kutuk/com~apple~CloudDocs/Vault",
            isUbiquitous: nil,
            expected: .iCloudDrive,
            title: "com~apple~CloudDocs bağımsız kalıbı"
        ),

        // MARK: - Dropbox yol kalıpları
        TableRow(
            path: "/Users/ornek/Library/CloudStorage/Dropbox/Vault",
            isUbiquitous: nil,
            expected: .dropbox,
            title: "Dropbox CloudStorage alt klasörü"
        ),
        TableRow(
            path: "/Users/ornek/Library/CloudStorage/Dropbox",
            isUbiquitous: nil,
            expected: .dropbox,
            title: "Dropbox CloudStorage kök klasörü"
        ),
        TableRow(
            path: "/Users/ornek/Library/CloudStorage/Dropbox-Personal/Vault",
            isUbiquitous: nil,
            expected: .dropbox,
            title: "Dropbox-Personal CloudStorage yolu"
        ),
        TableRow(
            path: "/Users/ornek/Library/CloudStorage/Dropbox (Personal)/Vault",
            isUbiquitous: nil,
            expected: .dropbox,
            title: "Dropbox (Personal) CloudStorage yolu"
        ),

        // MARK: - OneDrive yol kalıpları
        TableRow(
            path: "/Users/ornek/Library/CloudStorage/OneDrive-Personal/Vault",
            isUbiquitous: nil,
            expected: .oneDrive,
            title: "OneDrive-Personal CloudStorage yolu"
        ),
        TableRow(
            path: "/Users/ornek/Library/CloudStorage/OneDrive-Sirket/Vault",
            isUbiquitous: nil,
            expected: .oneDrive,
            title: "OneDrive-Sirket CloudStorage yolu"
        ),
        TableRow(
            path: "/Users/ornek/Library/CloudStorage/OneDrive/Vault",
            isUbiquitous: nil,
            expected: .oneDrive,
            title: "OneDrive/ alt klasörü"
        ),
        TableRow(
            path: "/Users/ornek/Library/CloudStorage/OneDrive",
            isUbiquitous: nil,
            expected: .oneDrive,
            title: "OneDrive kök klasörü"
        ),

        // MARK: - Google Drive yol kalıpları
        TableRow(
            path: "/Users/ornek/Library/CloudStorage/GoogleDrive-ornek@example.com/Drive'ım/Vault",
            isUbiquitous: nil,
            expected: .googleDrive,
            title: "GoogleDrive- hesabı yolu"
        ),
        TableRow(
            path: "/Users/ornek/Library/CloudStorage/GoogleDrive-kurum.org/Vault",
            isUbiquitous: nil,
            expected: .googleDrive,
            title: "GoogleDrive- kurum yolu"
        ),
        TableRow(
            path: "/Users/ornek/Library/CloudStorage/GoogleDrive/Vault",
            isUbiquitous: nil,
            expected: .googleDrive,
            title: "GoogleDrive/ alt klasörü"
        ),
        TableRow(
            path: "/Users/ornek/Library/CloudStorage/GoogleDrive",
            isUbiquitous: nil,
            expected: .googleDrive,
            title: "GoogleDrive kök klasörü"
        ),

        // MARK: - File Provider Storage
        TableRow(
            path: "/private/var/mobile/Containers/Shared/AppGroup/6C38A8E6/File Provider Storage/Vault",
            isUbiquitous: nil,
            expected: .fileProvider,
            title: "File Provider Storage (/private/var)"
        ),
        TableRow(
            path: "/var/mobile/Containers/Shared/AppGroup/6C38A8E6/File Provider Storage/Vault",
            isUbiquitous: nil,
            expected: .fileProvider,
            title: "File Provider Storage (/var)"
        ),
        TableRow(
            path: "/Users/ornek/Library/Application Support/File Provider Storage/Vault",
            isUbiquitous: nil,
            expected: .fileProvider,
            title: "macOS File Provider Storage"
        ),

        // MARK: - /private/var ve sembolik bağ yazımları
        TableRow(
            path: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Vault",
            isUbiquitous: nil,
            expected: .iCloudDrive,
            title: "/private/var iCloudDrive"
        ),
        TableRow(
            path: "/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Vault",
            isUbiquitous: nil,
            expected: .iCloudDrive,
            title: "/var sembolik bağ iCloudDrive"
        ),
        TableRow(
            path: "/private/var/mobile/Containers/Shared/AppGroup/UUID/File Provider Storage/Notes",
            isUbiquitous: nil,
            expected: .fileProvider,
            title: "/private/var File Provider Storage"
        ),
        TableRow(
            path: "/var/mobile/Containers/Shared/AppGroup/UUID/File Provider Storage/Notes",
            isUbiquitous: nil,
            expected: .fileProvider,
            title: "/var sembolik bağ File Provider Storage"
        ),
        TableRow(
            path: "/private/tmp/Library/CloudStorage/Dropbox/Vault",
            isUbiquitous: nil,
            expected: .dropbox,
            title: "/private/tmp Dropbox"
        ),
        TableRow(
            path: "/tmp/Library/CloudStorage/Dropbox/Vault",
            isUbiquitous: nil,
            expected: .dropbox,
            title: "/tmp sembolik bağ Dropbox"
        ),

        // MARK: - Büyük / küçük harf dayanıklılığı
        TableRow(
            path: "/USERS/GOKHAN/LIBRARY/MOBILE DOCUMENTS/VAULT",
            isUbiquitous: nil,
            expected: .iCloudDrive,
            title: "Büyük harf Library/Mobile Documents/"
        ),
        TableRow(
            path: "/users/ornek/library/mobile documents/vault",
            isUbiquitous: nil,
            expected: .iCloudDrive,
            title: "Küçük harf library/mobile documents/"
        ),
        TableRow(
            path: "/USERS/GOKHAN/COM~APPLE~CLOUDDOCS/VAULT",
            isUbiquitous: nil,
            expected: .iCloudDrive,
            title: "Büyük harf COM~APPLE~CLOUDDOCS"
        ),
        TableRow(
            path: "/Users/Gokhan/Library/CloudStorage/DROPBOX/Vault",
            isUbiquitous: nil,
            expected: .dropbox,
            title: "Büyük harf DROPBOX"
        ),
        TableRow(
            path: "/users/ornek/library/cloudstorage/dropbox/vault",
            isUbiquitous: nil,
            expected: .dropbox,
            title: "Küçük harf dropbox"
        ),
        TableRow(
            path: "/USERS/GOKHAN/LIBRARY/CLOUDSTORAGE/ONEDRIVE-PERSONAL/VAULT",
            isUbiquitous: nil,
            expected: .oneDrive,
            title: "Büyük harf ONEDRIVE-PERSONAL"
        ),
        TableRow(
            path: "/users/ornek/library/cloudstorage/onedrive-personal/vault",
            isUbiquitous: nil,
            expected: .oneDrive,
            title: "Küçük harf onedrive-personal"
        ),
        TableRow(
            path: "/USERS/GOKHAN/LIBRARY/CLOUDSTORAGE/GOOGLEDRIVE-USER@GMAIL.COM/VAULT",
            isUbiquitous: nil,
            expected: .googleDrive,
            title: "Büyük harf GOOGLEDRIVE-"
        ),
        TableRow(
            path: "/users/ornek/library/cloudstorage/googledrive-ornek@example.com/vault",
            isUbiquitous: nil,
            expected: .googleDrive,
            title: "Küçük harf googledrive-"
        ),
        TableRow(
            path: "/PRIVATE/VAR/MOBILE/CONTAINERS/SHARED/APPGROUP/UUID/FILE PROVIDER STORAGE/VAULT",
            isUbiquitous: nil,
            expected: .fileProvider,
            title: "Büyük harf FILE PROVIDER STORAGE"
        ),
        TableRow(
            path: "/private/var/mobile/containers/shared/appgroup/uuid/file provider storage/vault",
            isUbiquitous: nil,
            expected: .fileProvider,
            title: "Küçük harf file provider storage"
        ),

        // MARK: - NFD (decomposed Unicode) dayanıklılığı
        TableRow(
            path: "/Users/" + "Gökhan".decomposedStringWithCanonicalMapping + "/Library/CloudStorage/Dropbox/Kasa",
            isUbiquitous: nil,
            expected: .dropbox,
            title: "NFD kullanıcı adıyla Dropbox"
        ),
        TableRow(
            path: "/Users/ornek/Library/CloudStorage/Dropbox/" + "Günlük".decomposedStringWithCanonicalMapping,
            isUbiquitous: nil,
            expected: .dropbox,
            title: "NFD klasör adıyla Dropbox"
        ),
        TableRow(
            path: "/Users/" + "Şükrü".decomposedStringWithCanonicalMapping
                + "/Library/Mobile Documents/com~apple~CloudDocs/Kasa",
            isUbiquitous: nil,
            expected: .iCloudDrive,
            title: "NFD kullanıcı adıyla iCloud"
        ),
        TableRow(
            path: "/Users/ornek/Library/CloudStorage/OneDrive-" + "İşletme".decomposedStringWithCanonicalMapping
                + "/Kasa",
            isUbiquitous: nil,
            expected: .oneDrive,
            title: "NFD hesap adıyla OneDrive"
        ),
        TableRow(
            path: "/Users/ornek/Library/CloudStorage/GoogleDrive-"
                + "öğrenci@üniversite.edu".decomposedStringWithCanonicalMapping + "/Kasa",
            isUbiquitous: nil,
            expected: .googleDrive,
            title: "NFD hesap adıyla GoogleDrive"
        ),
        TableRow(
            path: "/var/mobile/" + "Kütüphane".decomposedStringWithCanonicalMapping + "/File Provider Storage/Kasa",
            isUbiquitous: nil,
            expected: .fileProvider,
            title: "NFD yol File Provider Storage"
        ),
    ]

    @Test(arguments: tableCases)
    func detectPathTable(row: TableRow) {
        let result = SyncedFolderKind.detect(path: row.path, isUbiquitous: row.isUbiquitous)
        #expect(
            result == row.expected,
            "Beklenen \(String(describing: row.expected)) ancak \(String(describing: result)) alındı: \(row.title)")
    }

    // MARK: - URL Bağdaştırıcısı (detect(url:))

    @Test func detectURLWithNonExistentPathFallsBackToPathMatching() {
        let dropboxURL = URL(fileURLWithPath: "/Users/test/Library/CloudStorage/Dropbox/Vault")
        #expect(SyncedFolderKind.detect(url: dropboxURL) == .dropbox)

        let icloudURL = URL(fileURLWithPath: "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/Vault")
        #expect(SyncedFolderKind.detect(url: icloudURL) == .iCloudDrive)

        let onedriveURL = URL(fileURLWithPath: "/Users/test/Library/CloudStorage/OneDrive-Personal/Vault")
        #expect(SyncedFolderKind.detect(url: onedriveURL) == .oneDrive)

        let gdriveURL = URL(fileURLWithPath: "/Users/test/Library/CloudStorage/GoogleDrive-ornek@example.com/Vault")
        #expect(SyncedFolderKind.detect(url: gdriveURL) == .googleDrive)

        let fpPath = "/private/var/mobile/Containers/Shared/AppGroup/UUID/File Provider Storage/Vault"
        let fpURL = URL(fileURLWithPath: fpPath)
        #expect(SyncedFolderKind.detect(url: fpURL) == .fileProvider)

        let localURL = URL(fileURLWithPath: "/Users/test/Documents/Vault")
        #expect(SyncedFolderKind.detect(url: localURL) == nil)
    }

    // MARK: - Sembolik Bağ Çözümleme

    @Test func detectResolvesRealFileSystemSymbolicLink() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let symlinkURL = tempDir.appendingPathComponent("SymlinkVault")
        let targetURL = URL(fileURLWithPath: "/Users/test/Library/CloudStorage/Dropbox/TargetVault")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: targetURL)

        #expect(SyncedFolderKind.detect(path: symlinkURL.path) == .dropbox)
        #expect(SyncedFolderKind.detect(url: symlinkURL) == .dropbox)
    }
}
