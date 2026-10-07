# Ürün

## Tek cümle

Gün içinde yazdığın kısa notları kişilere, konumlara ve zamana kendiliğinden bağlayan; görevleri ve hedefleri de aynı yerde tutan, verisi düz Markdown olan kişisel günlük.

## Neden

Çevremde olup biteni daha net görmek istiyorum: kimlerle, nerede, ne yaşadım. Bunu Obsidian'da klasörler ve elle bağlantılarla yapmak mümkün ama zahmetli. Ayrıca aynı iş için birkaç ayrı uygulamaya bağımlıyım; ihtiyaçlarımı tek uygulamada toplamak istiyorum.

## Yerini alacağı uygulamalar

| Şu an | Ne için kullanılıyor | Karşılığı | Aşama |
|---|---|---|---|
| Alışkanlık uygulaması | Zincir widget'ı | Hedefler ve ana ekran widget'ı | 3 |
| Lockday | Kilit ekranında takvim etkinlikleri | Kilit ekranı widget'ı | 3 |
| Notion | Kanban, zaman çizelgesi | Görev görünümleri | 5 |
| Obsidian | Notlar | Aynı formatta kasa; Obsidian Mac'te yedek editör olarak kalabilir | - |

## İlkeler

1. **Giriş 10 saniyeden kısa sürer.** Widget, hızlı giriş ve otomatik bağlama süs değil, uygulamanın yaşama şartıdır.
2. **Yaz, gerisi bağlansın.** Klasörleme ve etiketleme elle yapılmaz.
3. **Veri kullanıcınındır.** Düz Markdown, yerel, taşınabilir. Uygulama silinse de veri okunur kalır.
4. **Tek çekirdek, çok görünüm.** Her yeni özellik aynı dosyaların üzerinde yeni bir görünümdür; yeni veri deposu açılmaz.
5. **Geri bir şey verir.** Sadece kayıt tutmaz; kişi geçmişi, zincirler ve özetlerle yazmaya devam etmek için sebep üretir.
6. **Belirsizse sor.** Yanlış otomatik bağlama, sormaktan kötüdür.

## Modüller

- **Günlük:** Saat damgalı kısa olaylar ve aynı güne ait serbest uzun yazı.
- **Kişiler ve konumlar:** Düzenlenebilir şablonlu varlık sayfaları, serbest ek alanlar, o varlığın geçtiği her şeyin zaman akışı.
- **Görevler:** Bugüne ya da ileri tarihe atanan, kişi ve konumlara bağlanabilen görevler.
- **Hedefler:** Günlük, haftalık ve yıllık hedefler; zincir ve ilerleme takibi. Alışkanlıklar bunun günlük halidir.
- **Widget'lar:** Zincir, günün görevleri, takvim etkinlikleri, hızlı giriş. (Henüz yok; kimlik kararını bekliyor.)
- **Proje görünümleri:** Kanban ve zaman çizelgesi.
- **Özetler:** Haftalık ve aylık örüntüler. İleride isteğe bağlı olarak yapay zekanın dönemi inceleyip yazılı geri bildirim vermesi.

## Farkı

Görev ya da alışkanlık uygulamalarıyla tek tek yarışmaz. Farkı bağlamdır: bir kişinin sayfasında onunla yaşananlar ve onunla ilgili açık işler birlikte görünür; bir konuma girmek bir hedefi işaretleyebilir; her şey tek veri üzerinde olduğu için örüntüler görünür olur.

## Konumlanma

Ekim 2026 sektör taramasının sonucu. Tarama benzer ürünlerin bugünkü halini karşılaştırdı; aşağıdakiler karar değil, yön bilgisidir.

- **Ayırt eden:** yazarken kişi ve konumu kendiliğinden tanıyıp emin değilse soran bir ticari ürün bulunmadı; benzer ürünlerde bağlantı elle kurulur ya da buluttaki bir yapay zekaya bırakılır. İkinci ayırt eden, dosyanın gerçek kaynak olmasıdır: dışa aktarmaya gerek yoktur, kasa Obsidian ile aynıdır. Markdown dışa aktarması tek başına fark değildir.
- **Vaat cümlesi (öneri):** "Yaz; kim, nerede ve ne zaman kendiliğinden bağlansın. Dosyalar hep senin."
- **Geride kalınan yerler:** fotoğraf, "bu gün geçmişte", widget ve kilit ekranı girişleri, paylaşım uzantısı, sesle giriş, cihazlar arası eşitleme, başka günlük uygulamalarından içe aktarma, görsel kimlik.
- **Kaçınılacaklar:** veriyi ya da var olan özelliği sonradan kilitlemek, zorunlu hesap ve sunucu denetimi, suçlayan zincirler, sormadan kişi oluşturmak, kullanıcının yazdığını sessizce yeniden yorumlamak, uygulamaya özgü sözdizimi, kasayı uygulama düzeyinde şifrelemek (Obsidian uyumunu bozar).

## Kapsam dışı

- Genel amaçlı veritabanı oluşturucu (Notion benzeri)
- Tam özellikli Markdown editörü (ilk aşamalarda)
- Kullanıcının mevcut Obsidian kasasını yeniden düzenlemek ya da dosyalarını taşımak (var olan kasa yerinde açılıp hazırlanabilir; bkz. `vault-format.md`)
- Ekip kullanımı, hesap sistemi, kendi senkronizasyon sunucusu
- Android ve Windows (proje tutarsa ayrıca ele alınır)

## Ertelenenler

- Yapay zeka özellikleri (karar açık; uygulama onsuz tam çalışır)
- Şirket şema paketi (şirket yapısı, çalışanlar, sorumluluklar)
- İsim

## Dağıtım

Önce yalnızca kişisel kullanım, sonrasında mağaza yayını. Repo herkese açıktır. Gelir modeli olarak reklam ve üyelik düşünülüyor; ayrıntısı ve lisans seçimi sonraya bırakıldı.

Arayüz kullanıcının dilinde görünür (başlangıçta Türkçe ve İngilizce).

## En büyük riskler

- **Kapsam:** Beş ayrı uygulamalık iş. Aşamalar sırayla ve her biri gerçekten kullanılarak ilerler.
- **Yazmayı bırakmak:** Veri girilmezse uygulama boş kalır. İlke 1 ve 5 bunun için var.
- **Hatalı tanıma:** Aynı adlı kişiler, yanlış bağlantılar. İlke 6.
- **Başkalarına ait kişisel veri:** Yerel depolama esastır.
