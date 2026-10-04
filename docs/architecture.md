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

Ekranlar `App/Screens/Today`, `Days`, `Entities` ve `Settings` altında; ortak görünüm parçaları `App/Screens/Shared`, platform gezinmesi `App/Navigation` altında tutulur.

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

Aşama 0'da kasa varsayılan olarak uygulamanın yerel `Documents/Vault/` klasöründe oluşturulur; seçilen başka bir klasör güvenlik kapsamlı yer imiyle cihazda saklanır, bayat yer imi erişim başladıktan sonra yenilenir, geçici erişim hatasında yer imi korunarak yerel kasaya dönülür ve kullanıcı bilgilendirilir, yalnız bozuk yer imi silinir (iCloud konumu kullanıcı kararından sonra eklenecek). Dosya izleyici kök ve taranan alt dizinlerde Dispatch dizin kaynaklarını kullanır; ön plandaki 5 saniyelik zamanlayıcı ve ön plana dönüş tetiğiyle birlikte bildirimleri 300 ms birleştirip arka planda `refresh(vaultRoot:)` çağırır. Dizin kaynakları dosya içeriğinin yerinde düzenlenmesini güvenilir biçimde görmez; bunlar ön plandaki zamanlayıcı ve ön plana dönüş yenilemesiyle yakalanır, arka planda ise dizin olayları yenilemeyi tetiklemeye devam eder. En fazla 256 dizin kaynağı açılır; kalan dizinler ve kaynak açılamayan dizinler yalnız ön plan zamanlayıcısıyla denetlenir ve sayıları arayüzde bildirilir. İndeks kasa yolunun SHA-256 özetiyle adlandırılmış ayrı bir Application Support veritabanında tutulur; arayüz sayıları tutarlı bir `snapshot()` sorgusundan alınır.

Bildirimler yalnız App katmanında `NotificationPlanner` ile snapshot/cihaz tercihleri/yerel saatten üretilir, `NotificationService` seri yeniden planlama ve izin durumunu protokolle ayrılmış `UserNotifications` merkezine uygular; indeks yayınları iki saniye birleştirilir, uygulama kapalıyken yedi günlük planın içeriği yeniden hesaplanmaz.

App Intents, yer imi kapsamını ve indeksi açan ortak `IntentActions`/`IndexStore` üzerinden olay, görev ve hedef kaydı yazar; `AppShortcutsProvider` tr/en Siri cümlelerini sunar ve `IntentNavigation` Bugün ekranına yönlendirir.

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
- **Tarih ayrıştırma (`DateParsing`):** Doğal dil tarih ifadeleri.
- **Hedef hesapları (`GoalTracking`):** Dönem/yıl ilerlemesi, zincir, en uzun seri ve ısı haritası.
- **Özetler (`Summaries`):** Haftalık/aylık sayılar, ilk beş kişi/konum, hedef ve görev durumu, önceki dönem farkları.

Kısıt: Yalnızca Foundation ve SQLite katmanı. Bu sayede aynı kod uygulamada, widget'ta ve testlerde çalışır; ileride başka dile çevirmek kolay olur.

Paket hedeflere ayrılır. `VaultFormat` hedefi ayrıştırıcıyı, yazıcıyı, birleştirmeyi ve modelleri taşır; paket bağımlılığı yoktur ve Foundation dışında bir çerçeve kullanmaz. `VaultIndex` hedefi GRDB ve `VaultFormat` üzerine kurulur; dosyalara yazmaz, tam yeniden üretim ve küçük sorgu API’si sunar.

`VaultStore`, uygulamanın mevcut kasa belgelerini düzenleyen tek kapısıdır; aynı kasa kökündeki yazmaları ortak seri bir Foundation işlem kuyruğunda sıralar. Her işlem belgeyi diskten yeniden okur, `VaultFormat` ile düzenler, dosyaya yazar (mevcut dosyayı atomik değiştirir; sabit bağlantı desteklenmiyorsa yeni dosyayı dışlayıcı oluşturur) ve ardından yalnız değişen yolu `VaultIndex` ile günceller; indeks hatası yazılmış dosyayı geri almaz ve `indexUpdateFailed(path:underlying:)` ile dosyanın yazıldığı açıkça bildirilir.

İlk kullanım ve kasa hazırlama sırasında App katmanındaki `VaultImportBootstrap` yalnız eksik klasör, şablon ve `.app/vault.json` oluşturur; mevcut dosyaları değiştirmez. Core’un genel belge yazıcısı bu yapısal yolları kabul etmediğinden yeni dosyalar geçici dosya ve dışlayıcı sabit bağlantıyla yayımlanır; sabit bağlantı desteklenmiyorsa dışlayıcı oluşturma kullanılır. Eksik `type` eklemeleri `VaultStore` üzerinden yapılır.

`GoalTracking`, yalnız `VaultFormat` importu olan saf hedef katmanıdır: tanım, gün kaydı, dönem/yıl ilerlemesi, zincir/en uzun seri ve ısı haritası. İndeks tipleri kaynak alanlarından kurar; kayıt yazımı `VaultStore.settingGoalValue` ile dosya-önce yapılır. Takvim aritmetiği `CalendarDate` üzerinde ortak olup `DateParsing` tarafından da kullanılır.

`Summaries`, yalnız `VaultFormat` ve `GoalTracking` bağımlılıkları/importları olan saf değer hesaplarıdır; saat, dosya veya indeks erişimi yoktur. `VaultIndex.summaryInput(from:to:)` tek okuma snapshot'ında dönem günlerini/bağlantılarını, görevleri, hedef tanımlarını ve dönem sonuna kadar hedef geçmişini toplar. App seçilen ve önceki dönemi arka planda hesaplatır; kasa değişiminde yeniden yükler ve eski istek sonuçlarını eler. Özet dosyası veya indeks şeması eklenmez. Sayıların kapsamı `screens.md`, sabit beklentiler `fixtures.md` içinde tanımlıdır.

`DateParsing` (Tarih ayrıştırma) yalnız `VaultFormat` importu olan saf metin hedefidir. `DateExpressionParser`, çağıranın yerel günü ve sıralı dil tercihleriyle tek tarih, UTF-8 ifade aralığı, kalan metin ve güven döndürür; Foundation, saat veya dosya erişimi kullanmaz. Çıplak hafta günü bugünden sonraki ilk gündür (bugünse yedi gün sonra); `gelecek/next` bunun sonraki haftası, `bu/this` mevcut haftadaki gündür (geçtiyse sonraki hafta). Varsayılan hafta pazartesiden başlar; `weekStartsOnMonday=false` haftayı ve `next week` sonucunu pazardan başlatır. Hafta sonu cumartesidir, geçtiyse gelecek cumartesiye gider. Yılsız mutlak tarihte bugün dahil en yakın geçerli tarih seçilir; 29 Şubat için sonraki artık yıla kadar aranır. Noktalı yazım gün/ay, eğik çizgi dil sırasına göre Türkçe gün/ay ve İngilizce ay/gündür. Göreli ifadeler ve açık yıl kesin (`exact`); çıplak gün, çıplak hafta sonu ve yılsız mutlak tarih varsayım (`assumed`) taşır. İki yönde de geçerli eğik çizgi yazımı da varsayımdır. İlk konumdaki en uzun geçerli ifade seçilir; eşit uzunlukta dil sırası kullanılır. Sözcük içi, `@` anması, kod ve bağlantı içi taranmaz. İfade çıkarılırken bitişik boşluklar tek birleşme boşluğuna iner; kalan metnin diğer baytları korunur.

`EntityRecognition` yalnız `VaultFormat` bağımlılığı ve importu olan saf metin işleme hedefidir; bilinen kişi ve konumlar ile kullanım verileri çağıran tarafından değer olarak verilir. Dosya okumaz veya yazmaz; tanıma sonucu ve kullanıcı seçimleriyle ürettiği bağlantılı metni çağıran `VaultStore` üzerinden kaydeder.

İlk harfin büyük/küçük harfi farklı olan tek adaylı yazım öneridir; açık `@` dışında kesin bağlam varlığı olarak sayılmaz. Sıralama her çağrıda farklı adayın puanını bir kez hesaplayıp saklar; aynı aday başka anmalarda veya sıralama karşılaştırmalarında yeniden hesaplanmaz.

Belirsiz adayın bağlam puanı, aynı metinde kesin tanınan ve çağıranın bağlama eklediği farklı varlıklarla birlikte geçtiği gün sayılarının toplamıdır: konum için ağırlık 4, kişi için 1; adayın kendisi sayılmaz. Adaylar önce bu puan, sonra son geçiş günü (yeni önce), toplam bağlantı sayısı (çok önce) ve dosya yolunun Unicode kod noktası sırasıyla sıralanır. Eksik kullanım sıfır ve bilinmeyen tarih kabul edilir; belirsiz eşleşme puanla kesinleşmez. `VaultIndex` bütün kişi ve konumları takma adlarıyla tek sorguda getirir. Kullanım toplamı bütün çözülen bağlantıları sayar; son gün kaynak gün dosyasının tarihidir. Birlikte geçiş yalnız gün dosyalarında, aynı gün ve varlık çifti için bir kez sayılır; tekrar bağlantılar bu puanı artırmaz. Bu veriler dosyalardan üretilen sorgu sonuçlarıdır, şema değişmez. Foundation kullanmayan tanıma katmanında küçük harfli `String` anahtarların kanonik Unicode eşitliği ve hash davranışı NFC karşılaştırmasını sağlar; anahtarın saklanan baytları normalleştirilmez. İndeksin fiziksel anahtarları mevcut NFC kuralıyla saklanmaya devam eder.

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
- Görev blokları geçerli bitiş/başlangıç/tamamlanma tarihlerini, öncelik tokenını ve projeyi taşır; bitiş ve tamamlanma tarihleri indekslidir, görev metni tanınan alanlardan arındırılmıştır.
- `search`: FTS5; blok metinleri, varlık adları ve takma adlar; NFC metin üzerinde `unicode61 remove_diacritics 0`. Kullanıcı sorgusu boşluklarda bölünür; her parça çift tırnaklı deyim, son parça önek eşleşmesidir. Dosya ve blok sütunları aranmaz.
- `PRAGMA user_version = 3`; farklı sürümde tüm indeks tabloları silinip güncel boş şema kurulur. Çağıran `rebuild(vaultRoot:)` ile dosyalardan doldurur; göç yapılmaz. Açılışta SQLite NOTADB/CORRUPT hatasında dosya ve `-wal`/`-shm`/`-journal` yardımcıları silinip boş şema kurulur; diğer hatalar fırlatılır.
- Karşılaştırma anahtarı ve bağlantı çözümü `VaultIndex` içinde yapılır: NFC + yerelden bağımsız Unicode küçük harf. Boş hedef kaynağa, `/` içeren hedef köke göre uzantısız yola, diğer hedefler uzantısız dosya adına gider; yol hedefinde baştaki `/` ve `./` atılır. Çakışmada kod noktası sırasındaki ilk yol kazanır; `name` ve `aliases` yalnız varlık aramasında kullanılır.
- Tam yeniden üretim tek GRDB işlemi içinde tarar ve doldurur; hata eski içeriği korur. Geçersiz UTF-8 dosya okunamaz `note` türünde yalnız `files` satırı üretir; okuma, tarama ve veritabanı hataları fırlatılır. Sembolik bağlantılar izlenmeden atlanır; aynı NFC yola dönüşen iki dosyadan fiziksel yolun bayt sırasında önce geleni indekslenir. `rebuild` sonucu atlanan fiziksel yolları ve nedenlerini bildirir. Her dosya bir kez okunur, belge tutulmadan içerik ve bağlantı satırları yazılır; dosyalar bitince bağlantılar yol/anahtar tablolarıyla çözülür.
- Paragraf, olay/görev aralıkları ve başlıklar dışındaki ardışık boş olmayan gövde satırlarıdır; kod çitleri metin olarak dahildir. Başlık paragrafı böler; tanınan bölüm başlıkları blok üretmez, diğer başlıklar `heading` bloğu olarak işaretsiz metin ve düzey taşır; tanınmayan bölüm ve ön içerik `other` taşır. İç içe görevlerin bağlantısı en içteki bloğa bağlanır.
- `refresh(vaultRoot:)` aynı tarayıcıyla kasayı karşılaştırır; `update(paths:vaultRoot:)` NFC kasa içi dosya veya dizin bildirimleriyle kapsamı sınırlar: zaman/boyut değişince SHA-256 okunur, özet aynıysa yalnız gözlenen metadata güncellenir, farklıysa dosyanın tüm içerik satırları tek işlemde yenilenir, eksik dosyalar silinir. Değişen yolların dosya adı/yol anahtarlarına sahip bağlantılar (çözülmüş yinelenen adlar dahil) ve yeni içerikteki bağlantılar yeniden çözülür; `name`/`aliases` varlık araması içindir. Eski ve yeni blok kimliklerinin sahipliği yol ve dosya içi sıra üzerinden yeniden hesaplanır; hata tüm değişiklikleri geri alır, ortak `RebuildResult` eklenen/güncellenen/silinen NFC yolları ve kapsamda atlanan fiziksel yolları bildirir.
- Bildirim kapsamı kasa köküne göre NFC ve yerelden bağımsız küçük harf anahtarıyla karşılaştırılır; izleyici yeniden adlandırmada eski ve yeni yolu bildirir, eksik bildirimleri sonraki `refresh` düzeltir. Kök bir kez gerçek yola çözülür; silinmiş bildirimlerde en yakın mevcut üst dizinin gerçek yoluna kayıp kuyruk eklenerek `/private` yol yazımları aynı kasa kimliğinde birleştirilir.
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
- Mac hızlı giriş, MenuBarExtra ve Carbon RegisterEventHotKey üzerinden açılan nonactivating NSPanel içinde ortak QuickEntryBar/QuickEntryModel ve IndexStore kullanır; kısayol UserDefaults'ta saklanır, uygulama Dock'ta kalır.
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
