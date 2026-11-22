# Kenet

**Amaç:** README depoya giriş noktasıdır: uygulamayı, en kısa kurulumu ve belgeleri tek sayfada verir.

**Kapsam:**

- Ürün özeti, proje durumu ve platformlar
- Hızlı başlangıç
- Belge tablosu ve lisans

## Ürün özeti

**Tablo, uygulamanın adını, kod adını ve temel yapısını verir.**

| Konu | Bilgi |
|---|---|
| Uygulama adı | Kenet |
| Kod adı | `Kenet`: Xcode şemaları, hedefler ve modül de bu adı taşır |
| Depo | `github.com/dogancanyildiz/kenet` |
| Arayüz | SwiftUI; iPhone, iPad ve Mac |
| Veri | Obsidian uyumlu düz Markdown dosyaları; SQLite yalnız indeks |
| Ad kararı | Karar günlüğü, 2026-10-07 |

Kenet, kişiler, konumlar ve olaylar üzerine kurulu bir kişisel günlük uygulamasıdır. Uygulama görevleri, hedefleri ve hedef zincirlerini aynı yerde toplar. Ayrıntı [Ürün](docs/product.md) belgesindedir.

## Proje durumu

| Konu | Durum |
|---|---|
| Son sürüm | `v0.9.0`, `main` dalında |
| Test dağıtımı | TestFlight dahili test; iPhone, iPad ve Mac |
| Aktif aşama | [Yol haritasına](docs/roadmap.md) bak |

## Platformlar

**Tablo, desteklenen platformları ve dağıtım yollarını verir.**

| Platform | En düşük sistem | Düzen | Dağıtım |
|---|---|---|---|
| iPhone | iOS 26.0 | Sekmeli | TestFlight dahili test; cihaz ailesi `TARGETED_DEVICE_FAMILY: "1,2"` |
| iPad | iPadOS 26.0 | Dar pencerede sekmeli; 1000 pt ve üstünde 3 sütun | TestFlight dahili test; iPhone ile aynı uygulama |
| Mac | macOS 26.0 | Kenar çubuklu | TestFlight dahili test (`testflight.sh --mac`, Mac App Store paketi); geliştirme makinesine `.github/scripts/install-mac.sh` |

**NOT:** iPad desteği 2026-10-16 kararıyla açıldı; cihaz ailesine iPad girdi ve geri alınamaz. Mağaza listesindeki iPad ekran görüntüleri sürümde gelir.

## Hızlı başlangıç

**Komutlar projeyi üretir, Core testlerini koşar ve projeyi Xcode'da açar.**

```sh
brew install xcodegen
xcodegen generate
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --package-path Packages/Core -Xswiftc -warnings-as-errors
open Kenet.xcodeproj
```

Xcode 26 ya da üstü gerekir. Testler imzasız koşar; takım kimliği gerekmez. Öteki her adımı [Geliştirme](docs/development.md) belgesi anlatır.

| İş | Yer |
|---|---|
| Araçlar, şemalar, uygulama testleri | [Kurulum adımları](docs/development.md#kurulum-adımları) |
| Görüntü referansları | [Ekran görüntüsü testleri](docs/development.md#ekran-görüntüsü-testleri) |
| Ekran turu | [Ekran turu](docs/development.md#ekran-turu) |
| CI işleri | [CI](docs/development.md#ci) |
| Cihaza kurulum, TestFlight ve CD | [Cihaza kurulum ve TestFlight](docs/development.md#cihaza-kurulum-ve-testflight) |
| Yapı numarası | [Yapı numarası](docs/development.md#yapı-numarası) |
| Betikler | [Betik envanteri](docs/development.md#betik-envanteri) |

## Belgeler

**Tablo, `docs/` altındaki her belgeyi ve cevapladığı soruyu verir.**

| Belge | İçerik |
|---|---|
| [docs/roadmap.md](docs/roadmap.md) | Ne, ne zaman yapılır? Aktif aşama burada yazar. |
| [docs/product.md](docs/product.md) | Ürün nedir ve neden vardır? |
| [docs/screens.md](docs/screens.md) | Hangi öğe nerede durur ve ne yapar? |
| [docs/vault-format.md](docs/vault-format.md) | Dosyada ne nerede yazılır? Platformlar arası sözleşme. |
| [docs/design.md](docs/design.md) | Arayüz nasıl görünür ve neden? |
| [docs/decisions.md](docs/decisions.md) | Neden böyle karar verildi? |
| [docs/architecture.md](docs/architecture.md) | Sistem nasıl çalışır? |
| [docs/development.md](docs/development.md) | Yapı nasıl kurulur, sınanır ve dağıtılır? |
| [docs/fixtures.md](docs/fixtures.md) | Test verisi nedir ve nerededir? |

Ajan kuralları, okuma sırası ve belge kuralları [AGENTS.md](AGENTS.md) içindedir. `.github/scripts/check-docs.sh` tabloda olmayan belgeyi reddeder.

## Lisans

Tüm hakları saklıdır; ayrıntı `LICENSE` dosyasında. Depo incelenmek üzere herkese açıktır, açık kaynak lisansı verilmemiştir.
