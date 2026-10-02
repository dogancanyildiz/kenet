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
- **Modeller:** Gün, olay, görev, varlık (kişi, konum), hedef.
- **Yeniden adlandırma:** Varlık dosyasını yeniden adlandırma ve kasadaki tüm bağlantıları güncelleme.
- **Varlık tanıma:** Metinde bilinen adları ve takma adları bulma; birden fazla aday varsa bağlama göre (konum, yakınlık, sıklık) sıralama; emin olunamayan durumları arayüze bildirme.
- **İndeksleyici:** Tam ve artımlı indeksleme.
- **Sorgular:** Bugün, varlık zaman akışı, zincir hesabı, arama.
- **Tarih ayrıştırma:** Doğal dil tarih ifadeleri.

Kısıt: Yalnızca Foundation ve SQLite katmanı. Bu sayede aynı kod uygulamada, widget'ta ve testlerde çalışır; ileride başka dile çevirmek kolay olur.

Varlık tipleri (kişi, konum ve ileride eklenecekler) koda gömülmez, şema tanımından gelir. Şirket paketi ve özel tipler bu sayede eklenir.

## İndeks

- Her cihazda yerel, kasanın dışında, eşitlenmez.
- Dosyalardan eksiksiz yeniden üretilebilir; bozulursa silinip yeniden kurulur.
- Taslak tablolar: `files` (yol, değişiklik zamanı, özet), `entities` (tip, ad, takma adlar, alanlar), `blocks` (kimlik, dosya, tür, metin, tarih, durum), `links` (kaynak blok, hedef varlık), `goal_logs` (anahtar, tarih, değer), `search` (FTS5).
- Artımlı güncelleme: açılışta ve dosya değişiminde yalnızca özeti değişen dosyalar yeniden işlenir.

## Senkronizasyon

- Kasa, uygulamanın iCloud kapsayıcısındadır ve Dosyalar ile Finder'da görünür.
- Sunucu, hesap ya da özel senkronizasyon servisi yoktur.
- iCloud kapalıysa kasa yerelde durur.
- Çakışmada satırlar blok kimliğine göre birleştirilir, birleştirilemeyen içerik kopya olarak saklanır (kurallar: `vault-format.md`).
- Henüz indirilmemiş dosyalar için davranış aşama 0'da belirlenir.

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
- Dayanıklılık: bozuk frontmatter, tanınmayan sözdizimi, boş dosya hata üretmemeli.
