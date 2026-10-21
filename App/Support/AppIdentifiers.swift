import Foundation

/// Permanent identifiers registered with Apple (docs/architecture.md, "Kimlikler"). None can change
/// after the first upload that uses it: the iCloud container holds the vault, the App Group holds
/// what the app shares with its widgets and extensions.
///
/// `project.yml` carries the same values as build settings (`APP_BUNDLE_IDENTIFIER`,
/// `KENET_ICLOUD_CONTAINER`, `KENET_APP_GROUP`); the entitlements files read those settings.
/// `ReleaseConfigurationTests` keeps the two in step.
enum AppIdentifiers {
    static let bundle = "com.dogancanyildiz.kenet"
    static let iCloudContainer = "iCloud.com.dogancanyildiz.kenet"
    static let appGroup = "group.com.dogancanyildiz.kenet"
}
