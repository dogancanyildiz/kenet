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

Paket hedeflere ayrılır. `VaultFormat` hedefi ayrıştırıcıyı, yazıcıyı, birleştirmeyi ve modelleri taşır; paket bağımlılığı yoktur ve Foundation dışında bir çerçeve kullanmaz. İndeks ve sorgular SQLite'a bağlanan ayrı bir hedefte kurulur.

Varlık tipleri (kişi, konum ve ileride eklenecekler) koda dağılmaz; her tip tek bir veri tanımıdır: tip adı, varsayılan klasör, ayrılmış alanlar. Bu tanımlar şimdilik Core içinde durur ve indeks tipi serbest metin olarak tutar. Özel tipler ve şirket paketi geldiğinde (aşama 7) aynı tanım kasadaki bir şema dosyasından okunur; dosyanın biçimi o zaman `vault-format.md` içinde belirlenir.

## İndeks

- Her cihazda yerel, kasanın dışında, eşitlenmez.
- Dosyalardan eksiksiz yeniden üretilebilir; bozulursa silinip yeniden kurulur.
- Şema sürümü veritabanında tutulur. Uygulamanın beklediği sürümle uyuşmuyorsa indeks silinip dosyalardan yeniden kurulur; şema göçü yazılmaz.
- Taslak tablolar: `files` (yol, değişiklik zamanı, özet), `entities` (tip, ad, takma adlar, alanlar), `blocks` (dosya, dosya içi sıra, tür, metin, tarih, durum, varsa blok kimliği), `links` (kaynak dosya ve blok, hedef ad, çözülen varlık), `goal_logs` (anahtar, tarih, değer), `search` (FTS5).
- Bloğun anahtarı dosya ve dosya içi sıradır; blok kimliği isteğe bağlı bir sütundur. Kimliksiz satırlar, günlük paragrafları ve frontmatter'daki bağlantılar da blok ve bağlantı kaynağı olarak indekslenir.
- Hedefi henüz kasada olmayan bağlantı da tutulur; varlık oluştuğunda çözülür.
- Artımlı güncelleme: açılışta ve dosya değişiminde yalnızca özeti değişen dosyalar yeniden işlenir.

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
