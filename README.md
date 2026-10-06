# journal (çalışma adı)

Kişiler, konumlar ve olaylar etrafında dönen; görevleri, hedefleri ve alışkanlık zincirlerini tek yerde toplayan kişisel günlük uygulaması. iPhone ve Mac için SwiftUI ile yazılır. Veriler Obsidian uyumlu düz Markdown dosyalarında durur.

**Durum (2026-10-05):** Aşama 0–7'nin kullanıcı kararı gerektirmeyen teknik maddeleri tamam; aşamaların gerçek kullanım ölçütleri henüz ölçülmedi. Ekim 2026 heyet incelemesinin ardından sıradaki iş sağlamlaştırma (Aşama 8) ve seçilen tasarım dilinin (Mürekkep) uygulanmasıdır (Aşama 9). iCloud eşitlemesi, widget'lar ve TestFlight kimlik kararını bekliyor. Sürüm kesilmedi.

## Kurulum

Xcode projesi `project.yml` dosyasından üretilir ve repoya girmez:

```sh
brew install xcodegen
xcodegen generate
open Journal.xcodeproj
```

Şemalar: `Journal_iOS`, `Journal_macOS`, `VaultFormat` (Core testleri).

## Geliştirme

- Gerekenler: Xcode 26 ya da üstü (CI: macOS 26 / Xcode 26.6, Linux: Swift 6.4). Komut satırından `xcodebuild` ve `swift` için `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` gerekebilir.
- Core testleri: `swift test --package-path Packages/Core -Xswiftc -warnings-as-errors`
- Uygulama testleri: `xcodebuild test -project Journal.xcodeproj -scheme Journal_macOS -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` (iOS için `Journal_iOS` şeması ve bir iPhone simülatörü; arayüz testleri `-only-testing:JournalUITests`).
- Ekran görüntüsü testleri (iOS birim katmanı): `xcodebuild test -project Journal.xcodeproj -scheme Journal_iOS -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:JournalTests_iOS/ScreenSnapshotTests CODE_SIGNING_ALLOWED=NO`. Referansları yenilemek: `sh .github/scripts/record-screen-snapshots.sh` (veya CI'da `Ekran görüntüsü referansları` işini elle tetikleyip artifact'ı `Tests/JournalTests/Snapshots/__Snapshots__/` altına koy). Mac için aynı `ScreenSnapshotCase` listesine `#if os(macOS)` ile `NSHostingView` stratejisi eklenebilir; kapı şimdilik iOS.
- Biçim ve belge denetimi: `swift format lint --strict --recursive Packages App Tests` ve `sh .github/scripts/check-docs.sh`.
- İmzasız çalıştırma: CI ve yerel testler `CODE_SIGNING_ALLOWED=NO` ile koşar; cihaza kurulum için Xcode'da kendi takımını seç.

## Belgeler

| Belge | İçerik |
|---|---|
| [docs/product.md](docs/product.md) | Ne yapıyoruz, neden, ilkeler, kapsam dışı olanlar |
| [docs/roadmap.md](docs/roadmap.md) | Aşamalar, içerikleri ve çıkış ölçütleri |
| [docs/vault-format.md](docs/vault-format.md) | Kasa ve dosya formatı (platformlar arası sözleşme) |
| [docs/screens.md](docs/screens.md) | Ekranlar, içerikleri ve geçişler |
| [docs/design.md](docs/design.md) | Tasarım dili: yön, belirteçler, kurallar ve sıradaki seçenekler |
| [docs/architecture.md](docs/architecture.md) | Teknik mimari ve stack |
| [docs/decisions.md](docs/decisions.md) | Karar günlüğü ve açık sorular |
| [docs/fixtures.md](docs/fixtures.md) | Test verisi klasörü: kurallar, kategoriler, kurgusal adlar |

Ajanlar (Claude Code ve diğerleri) için kurallar: [AGENTS.md](AGENTS.md)

## Belge kuralı

Yeni bilgi önce mevcut belgelerden uygun olana eklenir. Gerçekten ayrı bir konu varsa `docs/` altında yeni belge açılır ve yukarıdaki tabloya eklenir.
