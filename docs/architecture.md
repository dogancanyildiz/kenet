# Mimari

## Stack

| Katman | Seçim |
|---|---|
| Arayüz | SwiftUI, tek projeden iOS ve macOS |
| Çekirdek | `Core` Swift paketi, Apple arayüz ve sistem çerçevelerine bağımsız |
| Veri | Markdown dosyaları (gerçek kaynak) |
| İndeks | SQLite, GRDB, FTS5 |
| Senkronizasyon | iCloud Drive (uygulamanın kendi kapsayıcısı) |
| Widget | WidgetKit, App Intents |
| Takvim | EventKit (salt okunur) |
| Konum | CoreLocation |
| Yerelleştirme | String Catalog (tr, en) |

## Proje yapısı

- Xcode projesi `project.yml` ile tanımlanır ve XcodeGen üretir; `Journal.xcodeproj` takip edilmez. Tek `Journal` hedefi iOS ve macOS için iki şema üretir; kaynaklar `App/` klasörüyle eşlenir, `Core` paketi yerel yoldan bağlanır.
- Bundle kimliği şimdilik geçici (`com.dravcore.journal.dev`, yalnızca simülatör ve yerel çalıştırma). Kalıcı kimlik, iCloud kapsayıcısı ve App Group kullanıcı kararıyla gelir.
- Sürüm numarası kök dizindeki `VERSION` dosyasından derleme sırasında Info.plist'e yazılır.
- Uygulama metinleri `App/Resources/Localizable.xcstrings` içinde (kaynak dil Türkçe, çeviri İngilizce).

## Veri akışı

```
Kullanıcı girişi
   -> Core: satırı üret, dosyaya yaz
   -> Core: değişen dosyayı ayrıştır, indeksi güncelle
   -> Arayüz: indeksten oku, göster

Dış değişiklik (iCloud, Obsidian)
   -> Dosya izleyici
   -> Core: değişen dosyayı yeniden indeksle
   -> Arayüz güncellenir
```

Yazma yönü her zaman dosyadan indekse doğrudur.

## Core paketi

Sorumlulukları:

- **Ayrıştırıcı:** Frontmatter, bölümler, olay ve görev satırları, bağlantılar, blok kimlikleri.
- **Yazıcı:** Yalnızca hedef satırı değiştiren, dosyanın geri kalanını birebir koruyan düzenleme.
- **Birleştirme:** Çakışan iki sürümü tek içerikte birleştiren saf işlev (kurallar: `vault-format.md`).
- **Modeller:** Gün, olay, görev, varlık (kişi, konum), hedef.
- **Yeniden adlandırma:** Varlık dosyasını yeniden adlandırma ve kasadaki tüm bağlantıları güncelleme.
- **Varlık tanıma:** Metinde bilinen adları ve takma adları bulma; birden fazla aday varsa bağlama göre (konum, yakınlık, sıklık) sıralama; emin olunamayan durumları arayüze bildirme.
- **İndeksleyici:** Tam ve artımlı indeksleme.
- **Sorgular:** Bugün, varlık zaman akışı, zincir hesabı, arama.
- **Tarih ayrıştırma:** Doğal dil tarih ifadeleri.

Kısıt: Yalnızca Foundation ve SQLite katmanı. Bu sayede aynı kod uygulamada, widget'ta ve testlerde çalışır; ileride başka dile çevirmek kolay olur.

Paket hedeflere ayrılır. `VaultFormat` hedefi ayrıştırıcıyı, yazıcıyı, birleştirmeyi ve modelleri taşır; paket bağımlılığı yoktur ve Foundation dışında bir çerçeve kullanmaz. `VaultIndex` hedefi GRDB ve `VaultFormat` üzerine kurulur; dosyalara yazmaz, tam yeniden üretim ve küçük sorgu API’si sunar.

Varlık tipleri (kişi, konum ve ileride eklenecekler) koda dağılmaz; her tip tek bir veri tanımıdır: tip adı, varsayılan klasör, ayrılmış alanlar. Bu tanımlar şimdilik Core içinde durur ve indeks tipi serbest metin olarak tutar. Özel tipler ve şirket paketi geldiğinde (aşama 7) aynı tanım kasadaki bir şema dosyasından okunur; dosyanın biçimi o zaman `vault-format.md` içinde belirlenir.

## İndeks

- Her cihazda yerel, kasanın dışında, eşitlenmez.
- Dosyalardan eksiksiz yeniden üretilebilir; bozulursa silinip yeniden kurulur.
- Şema sürümü veritabanında tutulur. Uygulamanın beklediği sürümle uyuşmuyorsa indeks silinip dosyalardan yeniden kurulur; şema göçü yazılmaz.
- `files`: NFC yol birincil anahtarı ve tarih indeksi; tür, gün tarihi, değişiklik zamanı, bayt boyutu, SHA-256 ve UTF-8 okunabilirliği.
- `entities`: dosya anahtarı; tip, görünen ad, ayırt edici, karşılaştırma anahtarı ve hedef alanları. `aliases`: dosya + sıra anahtarı; takma ad ve karşılaştırma anahtarı.
- `blocks`: dosya + sıfır tabanlı sıra anahtarı; tür, bir tabanlı dahil satır aralığı, metin, bölüm, saat, görev durumu ve ham durum, isteğe bağlı kimlik, başlık düzeyi ve sahiplik. Sahip kimlikler benzersiz kısmi indeksle korunur.
- `links`: kaynak dosya + sıra anahtarı; kaynak blok ya da frontmatter anahtarı/kaydı, fiziksel satır ve bayt aralığı, hedef ve indeksli `targetKey` karşılaştırma anahtarı, çapa türü/metni, görünen metin, gömme ve çözülen dosya. Çözülemeyen hedef `NULL` kalır.
- `goal_logs`: dosya + hedef anahtarı ve hedef anahtarı indeksi; gün, değer türü ve kaynak değer yazımı. Boolean değerler `true`/`false`, sayılar kaynak yazımı, diğer türler ham yazım taşır.
- `search`: FTS5; blok metinleri, varlık adları ve takma adlar; NFC metin üzerinde `unicode61 remove_diacritics 0`. Kullanıcı sorgusu boşluklarda bölünür; her parça çift tırnaklı deyim, son parça önek eşleşmesidir. Dosya ve blok sütunları aranmaz.
- `PRAGMA user_version = 2`; farklı sürümde tüm indeks tabloları silinip güncel boş şema kurulur. Çağıran `rebuild(vaultRoot:)` ile dosyalardan doldurur; göç yapılmaz. Açılışta SQLite NOTADB/CORRUPT hatasında dosya ve `-wal`/`-shm`/`-journal` yardımcıları silinip boş şema kurulur; diğer hatalar fırlatılır.
- Karşılaştırma anahtarı ve bağlantı çözümü `VaultIndex` içinde yapılır: NFC + yerelden bağımsız Unicode küçük harf. Boş hedef kaynağa, `/` içeren hedef köke göre uzantısız yola, diğer hedefler uzantısız dosya adına gider; yol hedefinde baştaki `/` ve `./` atılır. Çakışmada kod noktası sırasındaki ilk yol kazanır; `name` ve `aliases` yalnız varlık aramasında kullanılır.
- Tam yeniden üretim tek GRDB işlemi içinde tarar ve doldurur; hata eski içeriği korur. Geçersiz UTF-8 dosya okunamaz `note` türünde yalnız `files` satırı üretir; okuma, tarama ve veritabanı hataları fırlatılır. Sembolik bağlantılar izlenmeden atlanır; aynı NFC yola dönüşen iki dosyadan fiziksel yolun bayt sırasında önce geleni indekslenir. `rebuild` sonucu atlanan fiziksel yolları ve nedenlerini bildirir. Her dosya bir kez okunur, belge tutulmadan içerik ve bağlantı satırları yazılır; dosyalar bitince bağlantılar yol/anahtar tablolarıyla çözülür.
- Paragraf, olay/görev aralıkları ve başlıklar dışındaki ardışık boş olmayan gövde satırlarıdır; kod çitleri metin olarak dahildir. Başlık paragrafı böler; tanınan bölüm başlıkları blok üretmez, diğer başlıklar `heading` bloğu olarak işaretsiz metin ve düzey taşır; tanınmayan bölüm ve ön içerik `other` taşır. İç içe görevlerin bağlantısı en içteki bloğa bağlanır.
- `refresh(vaultRoot:)` aynı tarayıcıyla kasayı karşılaştırır; `update(paths:vaultRoot:)` NFC kasa içi dosya veya dizin bildirimleriyle kapsamı sınırlar: zaman/boyut değişince SHA-256 okunur, özet aynıysa yalnız gözlenen metadata güncellenir, farklıysa dosyanın tüm içerik satırları tek işlemde yenilenir, eksik dosyalar silinir. Değişen yolların dosya adı/yol anahtarlarına sahip bağlantılar (çözülmüş yinelenen adlar dahil) ve yeni içerikteki bağlantılar yeniden çözülür; `name`/`aliases` varlık araması içindir. Eski ve yeni blok kimliklerinin sahipliği yol ve dosya içi sıra üzerinden yeniden hesaplanır; hata tüm değişiklikleri geri alır, ortak `RebuildResult` eklenen/güncellenen/silinen NFC yolları ve kapsamda atlanan fiziksel yolları bildirir.
- Bildirim kapsamı kasa köküne göre NFC ve yerelden bağımsız küçük harf anahtarıyla karşılaştırılır; izleyici yeniden adlandırmada eski ve yeni yolu bildirir, eksik bildirimleri sonraki `refresh` düzeltir.
- Tarama tam, ayrıştırma ve yazma artımlıdır; büyük kasalarda taramanın bildirilen alt ağaçlarla sınırlanması sonraki iştir.

## Senkronizasyon

- Kasa, uygulamanın iCloud kapsayıcısındadır ve Dosyalar ile Finder'da görünür.
- Sunucu, hesap ya da özel senkronizasyon servisi yoktur.
- iCloud kapalıysa kasa yerelde durur.
- Kasa konumu ilk açılışta belirlenir (iCloud açıksa kapsayıcı, değilse yerel) ve cihazda kaydedilir. iCloud sonradan açılsa ya da kapansa uygulama kendiliğinden diğer konuma geçmez; kayıtlı konuma erişilemiyorsa yeni kasa açmaz, durumu bildirir. Konumlar arası taşıma, kullanıcının başlattığı ayrı bir işlemdir.
- Çakışmada satırlar blok kimliğine göre birleştirilir, birleştirilemeyen içerik kopya olarak saklanır. iCloud'un aynı gün için ayırdığı kopya dosyalar da aynı işlevle birleştirilir (kurallar: `vault-format.md`).
- Kasadaki tüm dosyalar cihazda tutulur: indirilmemiş dosya için indirme istenir, dosya geldikçe indekslenir. Arayüz eldeki içeriği gösterir ve eşitlemenin sürdüğünü belirtir.

## Widget'lar

- Widget hedefi `Core` paketini kullanır.
- Uygulama ve widget ortak bir App Group üzerinden veri paylaşır.
- Widget'tan yapılan işaretleme App Intent ile `Core` yazıcısını çağırır; mantık tek yerdedir.
- Widget'ların iCloud'daki kasaya doğrudan mı yoksa App Group'taki bir anlık görüntü üzerinden mi erişeceği aşama 3 başında denenerek kararlaştırılır.

## Platform düzeni

- **iPhone:** Alt sekmeler; öncelik hızlı giriş ve hızlı bakış.
- **Mac:** Kenar çubuğu ve çok sütunlu düzen; kanban, zaman çizelgesi ve not düzenleme burada.
- Ekranlar ortak SwiftUI görünümleridir; düzen platforma göre değişir.
- Ekranların ayrıntısı: `screens.md`.

## Taşınabilirlik

Android ve Windows şu an kapsam dışı. İleride mümkün kalması için:

1. Format `vault-format.md` belgesinde eksiksiz tanımlıdır.
2. `Core`, Apple çerçevelerine bağımlı değildir.
3. `Fixtures/` altındaki örnek dosyalar ve beklenen çıktılar dilden bağımsızdır.

Çekirdek şimdiden ortak bir teknolojiyle (Rust, Kotlin Multiplatform) yazılmaz.

## Test

- Ayrıştırıcı ve yazıcı: örnek dosya tabanlı testler.
- Gidiş dönüş: oku ve değiştirmeden yaz, çıktı birebir aynı olmalı.
- İndeks: örnek kasadan üretilen indeks beklenen sorgu sonuçlarını vermeli.
- Birleştirme: sonuç sürümlerin sırasından bağımsız olmalı, tekrarlandığında değişmemeli, hiçbir satırı kaybetmemeli.
- Dayanıklılık: bozuk frontmatter, tanınmayan sözdizimi, boş dosya hata üretmemeli.
