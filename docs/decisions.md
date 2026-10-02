# Kararlar

Verilen her karar tek satır olarak eklenir. Açık sorular kapandığında alttaki listeden silinip tabloya taşınır.

## Karar günlüğü

| Tarih | Karar | Gerekçe |
|---|---|---|
| 2026-10-02 | Öncelik kişisel günlük; şirket paketi sonraya | Önce çekirdek kullanım kanıtlanmalı |
| 2026-10-02 | Mobil en önemli platform | Günlük gün içinde telefondan yazılır |
| 2026-10-02 | Markdown gerçek kaynak, SQLite yalnızca indeks | Veri sahipliği, taşınabilirlik, Obsidian uyumu |
| 2026-10-02 | SwiftUI ile iPhone ve Mac | Widget'lar ürünün merkezinde ve yalnızca Swift ile yazılır; tek kod tabanı iki platform; iCloud ile senkronizasyon hazır |
| 2026-10-02 | Android ve Windows şimdilik yok | Tutarsa ayrı istemci yazılır; format açık olduğu için kilitlenme yok |
| 2026-10-02 | Kendi kasası, Obsidian uyumlu format (orta yol) | Widget ve senkronizasyon güvenilirliği; başkasının dağınık kasasında çalışma yükü alınmaz; Mac'te Obsidian ile açılabilir |
| 2026-10-02 | Gün dosyasında hızlı olaylar ve serbest günlük birlikte | Hem hızlı giriş hem uzun yazı ihtiyacı |
| 2026-10-02 | Kişi sayfası: düzenlenebilir şablon ve serbest ek alanlar | Basit başlangıç, esneklik |
| 2026-10-02 | Alışkanlık ve hedef tek mekanizma: dönem (gün, hafta, yıl) ve miktar | Kod ve kavram tekrarını önler |
| 2026-10-02 | Görevler Obsidian Tasks biçiminde | Mevcut araçlarla uyum |
| 2026-10-02 | Takvim yeniden yazılmaz, cihaz takvimi okunur | Mevcut takvimler ek iş olmadan gelir |
| 2026-10-02 | Yapay zeka ertelendi, uygulama onsuz tam çalışır | Maliyet; karar aşama 6'da |
| 2026-10-02 | Uygulama kilidi ertelendi | iOS'un kendi Face ID kilidi yeterli |
| 2026-10-02 | Dağıtım: önce kişisel, sonra App Store | Metinler baştan yerelleştirilebilir yazılır |
| 2026-10-02 | Belgeler `docs/` altında; önce mevcut belgeye eklenir, ihtiyaç varsa yeni belge açılıp README tablosuna yazılır | Dağınıklığı ve tekrarı önlemek, ama esnek kalmak |
| 2026-10-02 | Repo klasör adı `journal` | Çalışma adı; ürün ismi ayrıca belirlenecek |
| 2026-10-02 | Dosyadaki yapı (klasör, anahtar, `type`, bölüm başlıkları) İngilizce ve sabit; arayüz kullanıcının dilinde | Kasa her dilde aynı okunur; sonradan göç gerekmez |
| 2026-10-02 | Aynı adlı varlıklar: görünen ad `name` alanında, dosya adını uygulama ayırt ediciyle üretir; yazarken bağlama göre sıralama, emin değilse sorma | Kullanıcı dosya adı düşünmez; yanlış bağlama önlenir |
| 2026-10-02 | Tarihsiz görev yalnızca oluşturulduğu gün bugün ekranında, sonra "tarihsiz" listesinde | Bugün ekranı birikmesin |
| 2026-10-02 | Geçmiş güne olay eklenebilir, olayda saat isteğe bağlı | Sonradan yazma ihtiyacı |
| 2026-10-02 | Varlık adı değişince tüm bağlantılar otomatik güncellenir | Bağlantılar kırılmamalı |
| 2026-10-02 | Senkronizasyon çakışmasında satırlar blok kimliğine göre birleştirilir, birleştirilemeyen içerik kopya olarak saklanır | Hiçbir giriş kaybolmamalı |
| 2026-10-02 | Telefon sekmeleri: Bugün, Günlük, Görevler, Kişiler ve Konumlar, Hedefler; arama üstte simge | Görevler ayrı görünüm ister; beş sekme üst sınır |
| 2026-10-02 | Uygulama Bugün ekranında açılır; en hızlı giriş widget ve kilit ekranı kısayolundan | İlk kelimeye kadar geçen süre kalıcılığı belirliyor |
| 2026-10-02 | Tek giriş kutusu, olay / görev geçiş düğmesi, tarih cümleden çıkarılır | Mobil klavyede işaret yazmak zahmetli; doğal dil girişi en hızlısı |
| 2026-10-02 | Serbest notlar telefonda okuma ve basit düzenleme; zengin düzenleme Mac'te | Benzer uygulamaların mobilde en zayıf olduğu yer |
| 2026-10-02 | Geçmiş günlerin hedef kaydı düzeltilebilir; widget yapılmamışı vurgular | Alışkanlık uygulamalarında en çok şikayet edilen eksikler |
| 2026-10-02 | Mac'te sistem genelinde hızlı giriş penceresi | Masaüstünde hızlı girişin karşılığı |
| 2026-10-02 | Dallar: `main` (sürümler) ve `dev` (geliştirme, varsayılan); iş dalları `dev`'den, PR ile | Ajanlarla çalışırken kontrol noktası; `main` her zaman yayınlanmış durumu gösterir |
| 2026-10-02 | `dev`'den `main`'e birleşme sürüm keser: etiket ve GitHub Release otomatik | Sürüm geçmişi net; numara `0.<aşama>.<yama>`, mağaza yayını `1.0.0` |
| 2026-10-02 | CI aşama 0'da kod oluşunca kurulur; CD aşama 7'ye bırakıldı | Boş projeye CI anlamsız; kişisel kullanımda dağıtım Xcode'dan |
| 2026-10-02 | Ajan kuralları: yalnızca ürün vaatlerini koruyan değişmez kurallar; uygulama, arayüz ayrıntısı ve kütüphane seçimi ajanın kararı | Gereksiz kısıt daha iyi çözümleri engeller |
| 2026-10-02 | Repo herkese açık | Kullanılmak istenen GitHub özellikleri açık repoda ücretsiz |
| 2026-10-02 | Gelir modeli (reklam, üyelik) sonraya | Önce ürün |

## Açık sorular

1. **İsim.** İçinde "core" geçecek. Adaylar: Zincore, Ancore, Corenda. Karar ertelendi. Bundle ve iCloud kimliklerinde isim yerine nötr bir kimlik kullanılacak.
2. **Lisans.** Repo açık ama lisans seçilmedi. Lisans dosyası yokken kod görünür olur, başkası yasal olarak kullanamaz. Gelir modeli netleşince seçilecek.
3. **Gelir modeli.** Reklam ve üyelik düşünülüyor; hangi özelliklerin ücretli olacağı belirsiz.
4. **Yapay zeka.** Cihaz üzerinde model, API ya da hiç. Planlanan kullanım: haftalık ve aylık değerlendirme, varlık önerisi, notlara soru sorma. API seçilirse günlük içeriği cihaz dışına çıkar; açık onay gerekir. Üyelik için ücretli özellik adayı.
5. **Hedef türleri.** Sayılamayan yıllık hedeflerin proje olarak modellenmesi (aşama 5).
6. **Zincirde esneklik.** Günlük hedeflerde tek kaçırmada zincirin sıfırlanmaması için telafi hakkı (örneğin ayda bir gün) olsun mu?
7. **Widget veri erişimi.** iCloud kasasına doğrudan erişim ya da App Group anlık görüntüsü.
