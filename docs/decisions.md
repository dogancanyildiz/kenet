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
| 2026-10-02 | CI, `Core` paketini macOS ve Linux'ta derleyip sınar; dal korumasının zorunlu tuttuğu tek denetim `ci` işidir | Linux derlemesi `Core`'un Apple çerçevelerinden bağımsız kalmasını zorlar; tek kapı işi yol filtresi olmadan her PR'da sonuç verir |
| 2026-10-02 | `dev` ve `main` ruleset ile korunur: PR ve yeşil `ci` zorunlu, force push ve dal silme kapalı; `dev`'e squash ya da merge, `main`'e yalnız merge commit; onay incelemesi aranmaz | Tek geliştirici kendi PR'ını onaylayamaz; kontrol noktası CI'dır. Kimse için istisna tanımlı değil |
| 2026-10-02 | GitHub'ın açık repo hizmetleri kullanılır: gizli anahtar taraması ve push koruması, Dependabot (güvenlik ve haftalık sürüm güncellemeleri), iş akışları için CodeQL; Swift için CodeQL uygulama kodu gelince açılır | Açık repoda ücretsiz; yanlışlıkla commit'lenen anahtarı push anında durdurur. Swift analizi her koşuda tam derleme ister, şimdilik karşılığı yok |
| 2026-10-02 | Ajan kuralları: yalnızca ürün vaatlerini koruyan değişmez kurallar; uygulama, arayüz ayrıntısı ve kütüphane seçimi ajanın kararı | Gereksiz kısıt daha iyi çözümleri engeller |
| 2026-10-02 | Repo herkese açık | Kullanılmak istenen GitHub özellikleri açık repoda ücretsiz |
| 2026-10-02 | Gelir modeli (reklam, üyelik) sonraya | Önce ürün |
| 2026-10-02 | "Tanımadığına dokunma" işlemin hedefine göre tanımlandı: yalnızca hedef satır ya da alan değişir; dışarıda yazılmış metin kendiliğinden yeniden yazılmaz | Eski ifade ("yalnızca kendi ürettiği satırlar") kimlik ekleme, bağlama ve yeniden adlandırmayla çelişiyordu |
| 2026-10-02 | Okurken CRLF, BOM ve sonlanmamış son satır korunur; frontmatter için desteklenen YAML alt kümesi tanımlı, değerler yeniden üretilmez | Genel YAML ve Markdown kütüphaneleri dosyayı yeniden üretir, bayt düzeyinde korumayı bozar |
| 2026-10-02 | Ad karşılaştırması NFC ve yerelden bağımsız küçük harf eşlemesiyle yapılır; Türkçeye özel eşleme yok | iPhone dosya sistemi harfe duyarlı, Mac ve Obsidian duyarsız; sonuç cihazın diline göre değişmemeli |
| 2026-10-02 | Gün dosyasının kimliği yoludur (`journal/YYYY-MM-DD.md`); iCloud'un ayırdığı kopya (`… 2.md`) ana dosyayla birleştirilir | İki cihaz aynı günü çevrimdışı oluşturabilir; widget ve kısayol dosyayı indeks olmadan bulabilmeli |
| 2026-10-02 | Saatli olay saat sırasındaki yerine, saatsiz olay sona eklenir; gösterim sırası dosya sırasıdır | Dosya Obsidian'da da kronolojik okunur; sıranın tek kaynağı dosyadır |
| 2026-10-02 | Blok kimliği opak ve isteğe bağlı; indekste bloğun anahtarı dosya ve sıra | Dışarıda kopyalanan satır kimliği çoğaltır; kimliksiz satırlar ve paragraflar da indekslenir |
| 2026-10-02 | Görev satırı aşama 0'da asgari düzeyde tanınır (durum, metin, kimlik); diğer alanlar kendi aşamasında ayrıştırılır, o zamana dek metin olarak korunur | Aşama 0'daki birleştirme görev satırlarını da kapsıyor |
| 2026-10-02 | Çakışma birleştirme yalnızca iki sürüme bağlı saf işlev; kapalı görev, `true` ve büyük sayı kazanır; diğer farkta yeni sürüm kazanır ve kaybeden `conflicts/` altında saklanır | Değişiklik zamanı satırın değil dosyanın; "son değiştiren kazanır" düzenlemeyi sessizce kaybediyordu |
| 2026-10-02 | Varlık tipleri şimdilik Core içinde veri tanımı; kasadaki şema dosyası aşama 7'de | Tipler koda dağılmaz ama özel tip özelliği erken yazılmaz |
| 2026-10-02 | Kasa konumu kaydedilir ve kendiliğinden değişmez; tüm dosyalar cihaza indirilir | Sessiz konum değişimi veriyi kaybolmuş gösterir; metin dosyaları küçük |
| 2026-10-02 | Kasa format sürümünü `.app/vault.json` içinde taşır; daha yeni sürümü gören istemci yazmaz | Cihazlarda farklı uygulama sürümleri aynı kasayı paylaşır |
| 2026-10-02 | İndeks şeması değişikliği onay gerektirmez: şema sürümü artar, indeks yeniden kurulur | İndeks dosyalardan yeniden üretilebilir; geriye uyum kaygısı yok |
| 2026-10-02 | Hotfix sonrası `main`, `dev`'e merge commit ile geri birleştirilir | Squash iki dalın ortak geçmişini koparır |
| 2026-10-02 | Commit ve PR'larda yapay zeka imzası yok (`Co-Authored-By`, "Generated with" ve benzerleri) | Proje sahibinin tercihi |
| 2026-10-02 | Core paketinde ayrıştırma katmanı (`VaultFormat` hedefi) paket bağımlılığı taşımaz; indeks ayrı hedefte kurulacak | GRDB ve indeks hedefi, bağımlılık olarak bildirilmeden ayrıştırıcıdan kullanılamaz; ayrıştırıcı indeks olmadan tek başına derlenir ve sınanır |
| 2026-10-02 | Test için Swift Testing, biçim ve lint için `swift format` | İkisi de araç zinciriyle gelir; ek bağımlılık gerekmez |
| 2026-10-02 | Belge modeli satır tabanlı ve kayıpsız: her satır ham baytlarını ve satır sonunu saklar, metin isteğe bağlı olarak baytlardan çözülür, serileştirme baytları birleştirir | Gidiş dönüş tasarımdan gelir; ayrıştırıp yeniden üretme yaklaşımı bayt korumayı garanti edemez |
| 2026-10-02 | Ardından LF gelmeyen tek CR de satır sonu sayılır | Obsidian ve CommonMark ile uyum; yalnız CR kullanan dosyada satırlar, görevler ve başlıklar doğru tanınır. Bayt koruması değişmez |
| 2026-10-02 | Belge tek bir ilkelle değişir: bir satır aralığı yeni satırlarla değiştirilir. Yeniden yazılan satır kendi satır sonunu korur; sonuç her zaman, baytları yeniden okunduğunda çıkacak belgedir | Değişmezler (satır sonu, BOM, salt okunurluk) tek yerde korunur ve sınanır; dokunulmayan satırlar bayt düzeyinde aynı kalır |
| 2026-10-02 | Frontmatter genel bir YAML ayrıştırıcısıyla değil, alt kümeyi satır satır tanıyan ve her alanın satırlarını bilen bir okuyucuyla işlenir. Emin olunmayan yapı ham alan olur ya da bloğu çözülemez kılar; düzenleme yalnızca hedef satırları yeniden yazar, yorum ve boş satır silmez | Genel ayrıştırıcı yorumları, tırnakları ve yazımı korumaz; yanlış yorumlamak tanımamaktan kötüdür |
| 2026-10-02 | Obsidian'ın reddettiği frontmatter bloğu bütünüyle çözülemezdir: geçersiz YAML ve yinelenen anahtar bloğu çözülemez kılar, ham alan yalnızca geçerli ama desteklenmeyen yapılar içindir | İki uygulama aynı dosyayı aynı görür; okunamayan bloğa yazılmaz |
| 2026-10-03 | Satır yazma işlemleri (olay ve görev ekleme, metin, durum, saat, silme) sonucu seri hale getirip yeniden okur; hedef blok istenen değerlerle aynen okunmuyorsa ya da başka bir blok, bölüm, frontmatter veya çit sınırı değişmişse işlem reddedilir ve dosyaya dokunulmaz | Yazıcı ile okuyucunun aynı kuralları paylaştığı tek yerde kanıtlanır; metnin saat, kutu ya da kimlik gibi okunması gibi durumlar tek tek yasak listesi yerine genel denetimle yakalanır |
| 2026-10-03 | Yazma işleminin hedefi, aynı belgenin okunmasından alınan bloktur; belgede o konumda aynı tür, aynı ilk satır baytları, aynı kimlik ve metin yoksa işlem reddedilir | Eski bir okumadan kalan hedef başka bir satırı silememeli; staleness denetimi üst katmana bırakılmaz |
| 2026-10-03 | Alt satır olan bir görev silinebilir: yalnızca kendi satırları silinir, üst blok o kadar kısalır | Alt görev silme sıradan kullanıcı işlemidir; "yalnızca hedeflenen satır değişir" kuralıyla uyumludur |
| 2026-10-03 | Blok kimliği üretimi Core'da, rastgelelik ve "kimlik alınmış mı" sorusu dışarıdan verilir | Core Foundation'sız kalır; kasa genelinde benzersizlik indeksin bilgisidir |
| 2026-10-03 | Sürüm numarası kök dizindeki `VERSION` dosyasında tutulur; `main`'e push'ta iş akışı bu numarayla etiket ve Release oluşturur, etiket varsa atlar | Numara tek yerde durur ve Xcode projesi gelmeden önce de sürüm kesilebilir; iş akışı yeniden çalışsa da ikinci etiket üretmez |
| 2026-10-03 | Xcode projesi XcodeGen ile `project.yml` dosyasından üretilir, `Journal.xcodeproj` takip edilmez; bundle kimliği geçici `com.dravcore.journal.dev`, en düşük sürüm iOS 26 ve macOS 26 (ikisi de değiştirilebilir) | Proje dosyası çakışması olmaz ve ajanlar projeyi metinle düzenler; kalıcı kimlik kullanıcı kararını bekler, geçici kimlik yalnız simülatörde kullanılır |
| 2026-10-03 | İndeks `VaultIndex` hedefinde, GRDB 7 ve FTS5 (`unicode61`, aksanlar korunur) ile; tam yeniden üretim tek işlemde, şema sürümü uyuşmazsa ya da dosya bozuksa veritabanı silinip sıfırdan kurulur | Göç yazılmaz; indeks her zaman dosyalardan yeniden üretilebilir |
| 2026-10-03 | Taramada sembolik bağlantılar izlenmez, aynı NFC yola dönüşen dosyalardan bayt sırasında ilki alınır; atlanan dosyalar bildirilir, indeksleme durmaz | Tek bozuk dosya kullanıcıyı indekssiz bırakmamalı; kasa dışına çıkan bağlantı güvenlik riski |
| 2026-10-03 | Tanınan bölüm başlıkları (`## Tasks`, `## Events`, `## Journal`) blok üretmez; diğer başlıklar `heading` türünde bloktur; paragraf, olay ve görev dışındaki ardışık boş olmayan satırlardır | Aramada "Events" her gün dosyasını döndürmesin; bölüm bilgisi zaten sütunda |
| 2026-10-03 | Kullanıcı araması FTS5 ifadesine güvenli çevrilir: boşlukta bölünür, her parça tırnaklı deyim, son parçaya önek eşleşmesi | Kesme işareti ve `AND` gibi girdiler sorgu hatası vermesin |
| 2026-10-03 | Linux CI kabına `libsqlite3-dev` kurulur; indeks Linux'ta da derlenir ve test edilir | GRDB sistem SQLite'ına bağlanır; Core'un Apple'dan bağımsızlığı indeks dahil Linux'ta kanıtlanır |
| 2026-10-03 | Artımlı indeks: `refresh` tüm kasayı tarar, yalnızca değişiklik zamanı ya da boyutu farklı dosyaların özetini hesaplar, özeti değişenleri yeniden yazar; silinen ya da adı değişen dosyaların ve etkilenen anahtarların bağlantıları ile kimlik sahipliği yeniden hesaplanır. Ölçü: artımlı sonuç sıfırdan üretimle birebir aynı | Doğruluk tek bir ölçüye bağlanır; tarama ucuz (dosya başına ~20 µs), ayrıştırma pahalı |
| 2026-10-03 | Dosya izleyici artımlı indekse yol bildirir; yeniden adlandırmada eski ve yeni yolu bildirir, bildirim kapsamı harfe duyarsız ve NFC'dir; eksik bildirimi sonraki `refresh` düzeltir | APFS harfe duyarsız; izleyici kaçırırsa indeks yine toparlanır |
| 2026-10-04 | Birleştirme saf işlevdir: iki sürümün baytları ve değişiklik zamanları girer, birleşmiş baytlar, saklanacak sürümler ve `fellBack` çıkar; gövde birinci ve ikinci düzey başlıklarla bölgelere ayrılır, bloklar kimlikle (bir sürümde çoğulsa içerikle) eşleşir, serbest yazı bölge başına sayımlı karşılaştırılır | Sıradan bağımsızlık ve yeniden birleştirme kararlılığı bölge modeliyle kanıtlanabilir |
| 2026-10-04 | Kayıp yok değişmezi: bir sürümdeki blok, serbest yazı satırı, frontmatter alanı ya da yorum satırı sonuçta yoksa o sürüm saklanır. Tek istisnalar: kapalı görevin açık görevi yenmesi (aynı metin), iki kapalı görevde yalnız `✅` tarihi farkı, `goals` ilerlemesi, yalnız yazım ve satır sonu farkı | Ürün vaadi "hiçbir içerik sessizce kaybolmaz"; fazladan kopya zararsız, eksik kopya veri kaybı |
| 2026-10-04 | Son güvence: sonuç yeniden okunup kayıp yok değişmezi tutmazsa birleştirme yapılmamış sayılır (yeni sürüm alınır, eski saklanır, `fellBack` doğru). Yarı birleşmiş sonuç döndürülmez | Yarı sonuç yeniden birleştirmede kararsızdı; geri dönüş yapısı gereği kararlı. Kapanmayan kod çiti gibi yapı bozan durumlarda birleşme yapılmaz |

## Açık sorular

1. **İsim.** İçinde "core" geçecek. Adaylar: Zincore, Ancore, Corenda. Karar ertelendi. Bundle ve iCloud kimliklerinde isim yerine nötr bir kimlik kullanılacak.
2. **Lisans.** Repo açık ama lisans seçilmedi. Lisans dosyası yokken kod görünür olur, başkası yasal olarak kullanamaz. Gelir modeli netleşince seçilecek.
3. **Gelir modeli.** Reklam ve üyelik düşünülüyor; hangi özelliklerin ücretli olacağı belirsiz.
4. **Yapay zeka.** Cihaz üzerinde model, API ya da hiç. Planlanan kullanım: haftalık ve aylık değerlendirme, varlık önerisi, notlara soru sorma. API seçilirse günlük içeriği cihaz dışına çıkar; açık onay gerekir. Üyelik için ücretli özellik adayı.
5. **Hedef türleri.** Sayılamayan yıllık hedeflerin proje olarak modellenmesi (aşama 5).
6. **Zincirde esneklik.** Günlük hedeflerde tek kaçırmada zincirin sıfırlanmaması için telafi hakkı (örneğin ayda bir gün) olsun mu?
7. **Widget veri erişimi.** iCloud kasasına doğrudan erişim ya da App Group anlık görüntüsü.
8. **Hedef kaydının yazımı.** İşaret kaldırılınca `false` mı yazılır, anahtar mı silinir? İç içe `goals` eşlemini Obsidian'ın özellik arayüzü düzenleyemiyor; düz anahtar seçeneği değerlendirilecek (aşama 3).
9. **Haftanın başlangıcı.** Haftalık hedefte hafta hangi gün başlar; cihazın bölge ayarından mı gelir, kasada mı tutulur (aşama 3)?
10. **Türkçe ad tanıma ve arama.** Kesme işaretsiz ekler ("ofiste"), İ/ı eşlemesi, sık geçen sözcüklerin takma ad olması (aşama 1).
11. **Yarıda kalan yeniden adlandırma.** Çok dosyaya dokunan işlem çökme ya da kısmi eşitlemeyle yarım kalırsa nasıl tamamlanır (aşama 1)?
12. **Varlık dosyası kopyaları.** iCloud'un ayırdığı `Elif 2.md` gibi kopyalar ne zaman aynı varlık sayılıp birleştirilir (aşama 1)?
