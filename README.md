# Kenet

Depo: `github.com/dogancanyildiz/kenet`. Şema, hedef ve modül adı `Journal` kod adıdır; uygulamanın adı Kenet'tir (karar günlüğü, 2026-10-07).

Kişiler, konumlar ve olaylar etrafında dönen; görevleri, hedefleri ve alışkanlık zincirlerini tek yerde toplayan kişisel günlük uygulaması. iPhone ve Mac için SwiftUI ile yazılır. Veriler Obsidian uyumlu düz Markdown dosyalarında durur.

**Durum (2026-10-07):** İlk sürüm `v0.9.0` `main`'dedir; `dev`'den alınan yapılar TestFlight'ta dahili testte (yalnız iPhone). Aşama 0–9'un teknik maddeleri tamam: Mürekkep tasarım dili ve denetim kalıpları bütün iPhone ekranlarında. Açık kalanlar: gerçek cihazda gözle doğrulama, Mac'in aynı kalıplara taşınması, iPad düzeni. iCloud eşitlemesi ve widget'lar kalan kimlik kararlarını (iCloud kapsayıcısı, App Group) bekliyor. Dal rolleri: `main` ürünün aldığı sürüm, `dev` test.

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
- Ekran görüntüsü testleri: doğrulamak için `SNAPSHOT_TESTING_RECORD=never sh .github/scripts/record-screen-snapshots.sh`, referansları yenilemek için `sh .github/scripts/record-screen-snapshots.sh`. Betik kümeleri ad kuralından bulur (`…SnapshotTests`) ve en eski kurulu iOS runtime'ındaki iPhone 17'yi seçer; referanslar CI ile aynı cihaz ve runtime'da (iPhone 17, iOS 26.5) üretilmelidir, başka cihazda kaydedilen referans CI'da düşer. Betik koşmadan önce uygulamayı simülatörden kaldırır: kurulu kalan uygulamanın kayıtlı durumu görüntüleri kaydırır. Mac görüntü kümeleri (`…MacSnapshotTests`) CI'da koşmaz, yalnız yerelde doğrulanır: `SNAPSHOT_TESTING_RECORD=all xcodebuild test -project Journal.xcodeproj -scheme Journal_macOS -destination 'platform=macOS' -only-testing:JournalTests_macOS/<Küme> CODE_SIGNING_ALLOWED=NO` kaydeder.
- Ekran turu (tasarım işinde önce / sonra karşılaştırması): `sh .github/scripts/screen-tour.sh <çıktı klasörü> [simülatör kimliği]` uygulamayı örnek kasayla simülatörde gezer ve her ekranın görüntüsünü `NN-ekran-durum.png` adıyla klasöre yazar; ulaşılamayan adımlar `atlananlar.txt` dosyasına düşer, test düşmez. Tur (`ScreenTourUITests`) yalnız bu betikle koşar, olağan arayüz testi koşusunda ve CI'da atlanır. Mac uygulaması için `sh .github/scripts/screen-tour.sh --mac <çıktı klasörü>` aynı adlarla pencere görüntülerini yazar (`ScreenTourMacUITests`, `Journal_macOS_ScreenTour` şeması; yalnız Mac'te olan ekranlar 30'dan numaralanır); tur sürerken fare ve klavye testin elindedir, uygulama ayrı bir bundle kimliği ve geçici ev klasörüyle açıldığı için gerçek kasaya ve ayarlara dokunulmaz. Çıktı depo dışında bir klasöre verilir; Kasa ayar sayfası görüntüsü makine yolunu gösterebilir, görüntüler depoya ve PR'a eklenmez.
- Biçim ve belge denetimi: `swift format lint --strict --recursive Packages App Tests` ve `sh .github/scripts/check-docs.sh`.
- İmzasız çalıştırma: CI ve yerel testler `CODE_SIGNING_ALLOWED=NO` ile koşar; takım kimliği gerekmez.

### Cihaza kurulum ve TestFlight

Bundle kimliği `com.dogancanyildiz.kenet` (`project.yml` içinde `APP_BUNDLE_IDENTIFIER`); uygulamanın görünen adı Kenet, kod adı `Journal`. İlk sürüm yalnız iPhone'dur.

1. Takım kimliği repoya girmez. `cp Config/Local.xcconfig.example Config/Local.xcconfig` ile yerel dosyayı oluştur ve `XXXXXXXXXX` yerine kendi takım kimliğini yaz (dosya `.gitignore`'dadır).
2. `xcodegen generate`. Takım yerel dosyadan okunduğu için proje yeniden üretilince seçim kaybolmaz; Xcode'da takımı elle seçme (seçim üretilen projeye yazılır ve silinir).
3. Cihaza kurulum: `Journal_iOS` şeması, hedef olarak iPhone, Çalıştır. İmzalama otomatiktir.
4. TestFlight (dahili test): `dev` dalında `sh .github/scripts/testflight.sh`. Betik HEAD'i geçici bir kopyaya çıkarıp oradan arşivler (Xcode'un çalışma klasöründe yeniden yazdığı dosyalar yapıya girmez), paketteki kimliği, sürümü, yapı numarasını ve belge paylaşımı anahtarlarını denetler, onay alınca yükler. `--check` imzasız arşivleyip yalnız denetler, `--yes` onay sormaz. Xcode'da aynı Apple hesabıyla oturum açık olmalıdır. Elle yol: `Journal_iOS` şeması, hedef "Any iOS Device", Product → Archive, Organizer'da Distribute App → TestFlight Internal Only; bu yolda Xcode'un değiştirdiği dosyalar arşive girer, önce `git status` temiz olmalıdır.

Yapı numarası (`CFBundleVersion`) elle yazılmaz: derlemede `git rev-list --count HEAD` değeri Info.plist'e yazılır, iOS ve Mac aynı numarayı alır. App Store Connect aynı sürümde aynı yapı numarasını ikinci kez kabul etmez; yeni yükleme için en az bir yeni commit gerekir ve arşiv `dev` ya da `main` üzerinden alınır (iş dalındaki sayı squash sonrası `dev`'dekinden büyük olabilir). Git geçmişi yoksa ya da kopya sığsa (`fetch-depth: 1`) numara `1` kalır ve derleme uyarı verir; o yapı yüklenmez. Sürüm numarası `VERSION` dosyasından gelir.

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

## Lisans

Tüm hakları saklıdır; ayrıntı `LICENSE` dosyasında. Depo incelenmek üzere herkese açıktır, açık kaynak lisansı verilmemiştir.
