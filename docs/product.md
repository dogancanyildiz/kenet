# Ürün

**Amaç:** Bu belge Kenet'in ne olduğunu, neden var olduğunu ve hangi vaatlere dayandığını anlatır.

**Kapsam:**

- Ürün tanımı, ürün vaatleri, ilkeler ve kullanıcı günü akışı
- Özellik ağacı ve her modülün bugünkü durumu
- Konumlanma, kapsam dışı işler, dağıtım ve riskler

**NOT:** Durum bilgisi 2026-10-12 tarihli `dev` dalını ve [yol haritasını](roadmap.md) izler.

## Ürün tanımı

| Öğe | İçerik |
|---|---|
| Ad | Kenet. "Journal" çalışma adıdır ve mağazada görünmez. |
| Tek cümle | Gün içinde yazdığın kısa olayları kişilere, konumlara ve zamana kendiliğinden bağlayan; görevleri ve hedefleri de aynı yerde tutan, verisi düz Markdown olan kişisel günlük. |
| Platform | iPhone, iPad ve Mac. iPad kararı 2026-10-16'dadır; mağaza listesinin iPad ekran görüntüleri sürümde gelir. Mac uygulaması mağazaya sonra girer. |
| Veri | Obsidian uyumlu Markdown kasa. SQLite yalnız indekstir. |
| Arayüz dili | Kullanıcının dili. Başlangıçta Türkçe ve İngilizce. |

Kenet kişisel bir günlüktür. Kullanıcı gün içinde kısa olaylar yazar. Uygulama bu olayları kişilere, konumlara ve zamana bağlar. Görevler ve hedefler aynı kasada durur.

## Ürün gerekçesi

| İhtiyaç | Bugünkü yol | Sorun |
|---|---|---|
| Çevrede olup biteni net görmek: kimlerle, nerede, ne yaşandı | Obsidian'da klasörler ve elle bağlantılar | Yol çalışır ama zahmetlidir. |
| Görev, zincir, takvim, kanban ve not | Birkaç ayrı uygulama | İhtiyaçlar dağınıktır. |

Proje sahibi bu ihtiyaçları tek uygulamada toplamak ister. Kenet'in yerini alacağı uygulamaları [Yerini alacağı uygulamalar](#yerini-alacağı-uygulamalar) tablosu gösterir.

## Ürün vaatleri

**Şema, üç ürün vaadini ve her vaadi koruyan kuralı gösterir.**

```mermaid
mindmap
  root((Ürün vaatleri))
    Veri kullanıcınındır
      Markdown gerçek kaynaktır
      SQLite yalnız indekstir
      Kasa yereldir, hesap yoktur
      Uygulama gitse de dosyalar kalır
    Hiçbir şey kaybolmaz
      Önce dosyaya yaz, sonra indeksi güncelle
      Tanımadığına dokunma
      Çakışmada kaybeden sürüm conflicts klasörüne gider
      Silmede onay ya da geri alma
      Daha yeni format sürümünü gören istemci yazmaz
    Başka platforma taşınabilir
      Kasa Obsidian ile aynıdır
      Dosya yapısı İngilizce ve sabittir
      Uygulamaya özgü sözdizimi yoktur
      Uygulama kasayı şifrelemez
      Açık biçim başka platformda ayrı istemciye izin verir
```

Üç vaat, [ajan kurallarındaki](../AGENTS.md) değişmez kuralların gerekçesidir. Bir özellik bir vaadi bozuyorsa, vaat özellikten önce gelir. Kasa biçimini [Kasa biçimi](vault-format.md) belgesi tanımlar.

## İlkeler

| No | İlke | Anlamı |
|---|---|---|
| 1 | Bir satır yazmak 10 saniyeden kısa sürer | Widget, hızlı giriş ve otomatik bağlama süs değildir. Bu üçü uygulamanın yaşama şartıdır. |
| 2 | Sen yaz, uygulama bağlasın | Kullanıcı klasörleme ve etiketleme yapmaz. |
| 3 | Veri kullanıcınındır | Veri düz Markdown, yerel ve taşınabilirdir. Kullanıcı uygulamayı silse de dosyalar okunur durumda kalır. |
| 4 | Tek çekirdek, çok ekran | Her yeni özellik aynı dosyaların üstünde yeni bir ekrandır. Hiçbir özellik yeni veri deposu açmaz. |
| 5 | Geri bir şey verir | Uygulama yalnız kayıt tutmaz. Kişi geçmişi, zincirler ve özetler kullanıcıya yazmaya devam etmek için sebep verir. |
| 6 | Belirsizse sor | Yanlış otomatik bağlama, sormaktan kötüdür. |

Başka belgeler ilkeleri numarayla anar: "İlke 6" belirsiz eşleşmede sorma kuralıdır.

## Kullanıcı günü akışı

**Şema, bir satırın yazmadan bağlamaya, sonra görev, hedef ve geri dönüş ekranlarına yolunu gösterir.**

```mermaid
flowchart TD
  G1[Bugün ekranında hızlı giriş] --> Y
  G2[Mac hızlı giriş penceresi] --> Y
  G3[Siri ve Kısayollar] --> Y
  Y[Yaz: tek satır] --> M{Olay mı, görev mi}
  M -->|Olay| T
  M -->|Görev| TR[Cümleden tarih, öncelik ve tekrarı oku] --> T
  T[Tanı: bilinen ad, takma ad, @ anma, GPS konum önerisi] --> E{Eşleşme kesin mi}
  E -->|Evet| B[Bağla: wikilink yaz]
  E -->|Belirsiz| S[Kullanıcıya sor] --> B
  E -->|Bilinmeyen ad| N[Düz metin bırak ya da yeni varlık öner]
  B --> D[Gün dosyasına yaz, sonra indeksi güncelle]
  N --> D
  D --> K1[Görev: Bugün, Görevler, Kanban, zaman çizelgesi]
  D --> K2[Hedef: elle, bildirimle ya da konuma girince işaretle]
  D --> K3[Geri dönüş: kişi sayfası, zincir, özet, haftalık inceleme]
  K1 --> GK[Günü kapat: açık görevleri bugüne, yarına ya da haftaya taşı]
```

Uygulama satırı önce gün dosyasına yazar, sonra indeksi günceller. Siri ve Kısayollar yolu soru sormaz: kesin anmaları bağlar, belirsiz ve bilinmeyen adları düz bırakır. Hedef işaretleme satırdan bağımsız bir eylemdir.

## Yerini alacağı uygulamalar

| Şu an | Ne için kullanılıyor | Karşılığı | Aşama | Durum |
|---|---|---|---|---|
| Alışkanlık uygulaması | Zincir widget'ı | Hedefler ve ana ekran widget'ı | 3, 11 | Hedefler ve zincir hazır. Widget Aşama 11'dedir ve kimlik kararını bekler. |
| Lockday | Kilit ekranında takvim etkinlikleri | Kilit ekranı widget'ı | 11 | Yok. Kimlik kararını bekler. |
| Notion | Kanban, zaman çizelgesi | Görevler'de Kanban ve zaman çizelgesi | 5 | Hazır. |
| Obsidian | Notlar | Aynı formatta kasa; Obsidian Mac'te yedek editör olarak kalabilir | - | Kasa uyumlu. Uygulama var olan kasayı yerinde açar. |

Widget maddeleri Aşama 3'ten Aşama 11'e geçti. Gerçek kullanım ölçütü iki uygulamanın telefondan silinmesidir: alışkanlık uygulaması ve Lockday.

## Özellik ağacı

**Şema, ürünün modüllerini ve her modülün ana özelliklerini gösterir.**

```mermaid
mindmap
  root((Kenet))
    Günlük
      Saatli ve saatsiz olaylar
      Serbest günlük yazısı
      Hızlı giriş ve Mac hızlı giriş penceresi
      Tam metin arama
    Kişiler ve konumlar
      Şablonlu varlık sayfaları
      Zaman akışı ve son görüşme
      Özel varlık tipleri
      Rehberden içe aktarma
    Görevler
      Doğal dille tarih
      Tekrar ve öncelik
      Kanban ve zaman çizelgesi
      Proje sayfaları
    Hedefler
      Gün, hafta ve yıl dönemi
      Zincir, ısı haritası, zincir affı
    Otomasyon
      Bildirimler
      GPS konum önerisi
      Konuma girince hedef işaretleme
      Siri ve Kısayollar
    Geri dönüş
      Haftalık ve aylık özet
      Graph ve harita
      Bu gün geçmişte
      Haftalık inceleme ve günü kapat
      Görüşme ritmi ve önemli tarihler
    Kasa ve güvenlik
      İlk kullanım
      Obsidian kasasını hazırlama
      Uygulama kilidi
      Eşitleme güvenliği
    Widget'lar ve uzantılar
      Ana ekran zinciri
      Kilit ekranı
      Hızlı giriş widget'ı
      Mac widget'ları
      Paylaşım uzantısı
```

| Modül | İçerik | Aşama | Durum |
|---|---|---|---|
| Günlük | Saat damgalı kısa olaylar ve aynı güne ait serbest uzun yazı; günler arasında gezinme, tam metin arama, Mac hızlı giriş penceresi | 1 | Hazır |
| Kişiler ve konumlar | Düzenlenebilir şablonlu varlık sayfaları, serbest ek alanlar, varlığın geçtiği her şeyin zaman akışı, varlık adını değiştirme | 1 | Hazır |
| Görevler | Bugüne ya da ileri tarihe atanan, kişi ve konumlara bağlanabilen görevler; doğal dille tarih; cihaz takvimini salt okuma | 2 | Hazır |
| Hedefler | Günlük, haftalık ve yıllık hedefler; zincir ve ilerleme takibi. Alışkanlık hedefin günlük biçimidir. | 3 | Hazır |
| Otomasyon | Görev ve hedef bildirimleri, akşam günlük hatırlatması, GPS konum önerisi, konuma girince hedef işaretleme, Siri ve Kısayollar | 4 | Hazır |
| Proje görünümleri | Kanban, zaman çizelgesi, proje sayfaları, tekrarlayan görevler, öncelik | 5 | Hazır |
| Özetler | Haftalık ve aylık örüntüler, sayılara dayalı; kişi sayfasında son görüşme özeti; graph ve harita | 6 | Hazır. Yapay zekalı yazılı geri bildirim "Sonraki fikirler"dedir ve karar açıktır. |
| Kasa ve güvenlik | İlk kullanım, var olan Obsidian kasasını yerinde açma, uygulama kilidi, özel varlık tipleri | 7 | Hazır |
| Bağlam ve geri dönüş | Bu gün geçmişte, takvimden olay taslağı, bağlanmamış anmalar, önemli tarihler, görüşme ritmi, zincir affı, suçlamasız taşıma, günü kapat, haftalık inceleme, rehberden kişi içe aktarma, bu güne bağlananlar | 10 | Kısmen. Hızlı girişte tanınan alanların kutu içi vurgusu kullanıcı kararını bekler; çipler ve geri alma hazırdır. |
| Eşitleme | iCloud kasası, dosya koordinasyonu, gün kopyası birleştirme, eşitleme durumu göstergesi | 11 | Kısmen. Koordinasyon ve Core'daki birleştirme hazırdır; iCloud kapsayıcısı kimlik kararını bekler. |
| Widget'lar ve uzantılar | Zincir, günün görevleri, takvim etkinlikleri, hızlı giriş; kilit ekranı, Denetim Merkezi, Mac widget'ları, paylaşım uzantısı | 11 | Yok. Kimlik kararını bekler. |

"Hazır", yol haritasındaki `[x]` ile aynı anlamdadır: özellik kodda var, testlerden ve CI'dan geçti. Gerçek kullanım ölçütleri ayrıdır ve [yol haritası](roadmap.md) onları izler.

## Ayırt eden bağlam

| Bağlam | Ne sağlar |
|---|---|
| Kişi sayfası | Bir kişiyle yaşananlar ve o kişiyle ilgili açık görevler birlikte görünür. |
| Konum | Bir konuma girmek bir hedefi işaretleyebilir. |
| Tek veri | Her şey aynı dosyalarda durur. Bu yüzden örüntüler görünür olur. |

Kenet, görev ya da alışkanlık uygulamalarıyla tek tek yarışmaz. Kenet'in farkı bağlamdır.

## Konumlanma

Ekim 2026 sektör taraması benzer ürünlerin o günkü durumunu karşılaştırdı. Taramanın sonucu karar değildir, yön bilgisidir.

### Ayırt eden yönler

| Konu | Tarama sonucu |
|---|---|
| Tanıma | Yazarken kişi ve konumu kendiliğinden tanıyan, emin değilse soran bir ticari ürün bulunmadı. Benzer ürünlerde kullanıcı bağlantıyı elle kurar ya da buluttaki bir yapay zeka kurar. |
| Gerçek kaynak | Dosya gerçek kaynaktır, dışa aktarmaya gerek yoktur ve kasa Obsidian ile aynıdır. Markdown dışa aktarması tek başına fark değildir. |
| Vaat cümlesi önerisi | "Yaz; kim, nerede ve ne zaman kendiliğinden bağlansın. Dosyalar hep senin." |

### Geride kalınan alanlar

| Alan | Bugünkü durum |
|---|---|
| Fotoğraf | "Sonraki fikirler"de. |
| Bu gün geçmişte | Hazır, Aşama 10. |
| Widget ve kilit ekranı girişleri | Aşama 11. Kimlik kararını bekler. |
| Paylaşım uzantısı | Aşama 11. |
| Sesle giriş | "Sonraki fikirler"de. |
| Cihazlar arası eşitleme | Aşama 11, kısmen hazır. |
| Başka günlük uygulamalarından içe aktarma | "Sonraki fikirler"de: Day One ve Apple Journal. |
| Görsel kimlik | Aşama 9: Mürekkep tasarım dili ve "Geçme" uygulama simgesi seçildi. Gerçek cihazda gözle doğrulama açıktır. |

Tarama, sekiz alanın hepsini o gün eksik buldu. Tablo her alanın 2026-10-12 durumunu gösterir.

### Kaçınılacak davranışlar

| Davranış | İlgili kural ya da özellik |
|---|---|
| Veriyi ya da var olan özelliği sonradan kilitlemek | Veri kullanıcınındır vaadi. Yazılı "veri kilidi yok" taahhüdü Aşama 12'de açıktır. |
| Zorunlu hesap ve sunucu denetimi | Hesap sistemi kapsam dışıdır. |
| Suçlayan zincirler | Zincir affı ve suçlamasız taşıma, Aşama 10. |
| Sormadan kişi oluşturmak | İlke 6. |
| Kullanıcının yazdığını sessizce yeniden yorumlamak | Tanımadığına dokunma kuralı. |
| Uygulamaya özgü sözdizimi | Obsidian uyumlu kasa biçimi. |
| Kasayı uygulama düzeyinde şifrelemek | Şifreleme Obsidian uyumunu bozar. Uygulama kilidi kasayı şifrelemez. |

## Kapsam dışı işler

| İş | Not |
|---|---|
| Genel amaçlı veritabanı oluşturucu | Notion benzeri bir araç değildir. |
| Tam özellikli Markdown editörü | İlk aşamalarda yoktur. |
| Kullanıcının var olan Obsidian kasasını yeniden düzenlemek ya da dosyalarını taşımak | Uygulama var olan kasayı yerinde açar ve hazırlar. Ayrıntı [Kasa biçimi](vault-format.md) belgesindedir. |
| Ekip kullanımı, hesap sistemi, kendi eşitleme sunucusu | - |
| Android ve Windows | Proje tutarsa ekip ayrı istemci yazar. Kasa biçimi açık olduğu için kilitlenme yoktur. |

## Ertelenen işler

| İş | Durum |
|---|---|
| Yapay zeka özellikleri | Karar açıktır, [açık soru 4](decisions.md#açık-sorular). Uygulama yapay zeka olmadan tam çalışır. |
| Şirket şema paketi: şirket yapısı, çalışanlar, sorumluluklar | "Sonraki fikirler"de. |

## Dağıtım

| Konu | Durum |
|---|---|
| Sıra | Önce yalnız kişisel kullanım, sonra mağaza yayını. |
| Test | İlk sürüm `v0.9.0` 2026-10-07'de `main`'e çıktı. TestFlight'ta dahili test sürer; TestFlight yapıları `dev`'den gelir. |
| Ad ve kimlik | Ad Kenet, bundle kimliği `com.dogancanyildiz.kenet`. Karar günlüğü, 2026-10-07. |
| Cihaz | iOS hedefi iPhone ve iPad içindir. Karar günlüğü, 2026-10-16. |
| Repo | Herkese açık. |
| Lisans | Tüm hakları saklıdır. Karar günlüğü, 2026-10-07. |
| Gelir modeli | Karar açıktır, [açık soru 3](decisions.md#açık-sorular). |
| Arayüz dili | Kullanıcının dili. Başlangıçta Türkçe ve İngilizce. |

## En büyük riskler

| Risk | Açıklama | Karşı önlem |
|---|---|---|
| Kapsam | Beş ayrı uygulamalık iş. | Aşamalar sırayla ilerler ve her modül gerçek kullanımda sınanır. |
| Yazmayı bırakmak | Kullanıcı veri girmezse uygulama boş kalır. | İlke 1 ve İlke 5. |
| Hatalı tanıma | Aynı adlı kişiler ve yanlış bağlantılar. | İlke 6. |
| Başkalarına ait kişisel veri | Günlük başka kişilerin bilgisini taşır. | Yerel depolama esastır. |

**NOT:** Aşama 0–7 çıkış ölçütleri beklenmeden art arda yazıldı. Ölçütler geçerlidir ve gerçek kullanımla kapanır.

## İlgili belgeler

- [Yol haritası](roadmap.md)
- [Kararlar](decisions.md)
- [Kasa biçimi](vault-format.md)
- [Ekranlar](screens.md)
- [Tasarım dili](design.md)
