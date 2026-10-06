# Yol haritası

**Aktif aşama:** 9 (Aşama 8'in açık kalan iki maddesi sahibin elindedir: kilidin gerçek cihazda doğrulanması ve eşitlenen klasör uyarısının metni)

**Durum (2026-10-05).** Aşama 0–7'nin kullanıcı kararı gerektirmeyen teknik maddeleri `dev` dalındadır. Bu belgede `[x]`, "kodda var, testlerden ve CI'dan geçti" demektir. Aşamaların gerçek kullanım ölçütleri henüz ölçülmedi ve aşağıda ayrıca izlenir.

Ekim 2026'da proje çok modelli bir heyete inceletildi (kod ve mimari denetimi, ekran görüntülü kullanım gezisi, sektör taraması, tasarım dili araştırması). İnceleme gerçek hatalar, ölçek sorunları ve vaatle uyuşmayan yerler buldu. Bu yüzden sıradaki iş yeni özellik değil, sağlamlaştırmadır. Aşama 8 ve sonrası heyetin önerdiği sıradır; kapsam ve sıra kullanıcı onayıyla kesinleşir.

Kural: Her modül gerçek kullanımda sınanır. Aşama 0–7 çıkış ölçütleri beklenmeden art arda yazıldı; ölçütler geçerliliğini korur ve gerçek kullanımla kapanır. Kullanımda bir ölçüt tutmazsa sonraki işler yeniden sıralanır.

## Gerçek kullanım ölçütleri

| Aşama | Teknik kapsam | Çıkış ölçütü | Durum |
|---|---|---|---|
| 0 Temel | iCloud kasa konumu dışında tamam | Örnek kasa okunuyor, indeksleniyor, değişiklikler yansıyor, testler geçiyor | Sağlandı |
| 1 Günlük | Tamam | İki hafta boyunca her gün bununla günlük tutuluyor | Başlamadı |
| 2 Görevler | Tamam | Günlük işler yalnızca buradan takip ediliyor | Başlamadı |
| 3 Hedefler ve widget'lar | Hedefler tamam, widget'lar yok | Alışkanlık uygulaması ve Lockday telefondan silindi | Widget'lar kimlik kararını bekliyor |
| 4 Otomasyon | Tamam | İki hafta boyunca hatırlatmalar kaçmadan geliyor; konuma bağlı hedefler elle işaretlemeden kaydediliyor | Başlamadı |
| 5 Proje görünümleri | Tamam | Notion kanban ve zaman çizelgesi için açılmıyor | Başlamadı |
| 6 Geri bildirim | Sayılara dayalı kısım tamam | Haftalık özet dört hafta üst üste okunuyor | Başlamadı |
| 7 Genişleme | İlk kullanım, kasa hazırlama, kilit ve özel tipler tamam | Yok | - |

Gerçek kullanım, gerçek cihazda kalıcı kurulum ister; bu da aşağıdaki ilk karara bağlıdır.

## Kullanıcı kararı bekleyenler

| Karar | Neyi açar | Not |
|---|---|---|
| Apple Developer Program üyeliği; kalıcı bundle kimliği, iCloud kapsayıcısı, App Group ve alan adı | Gerçek cihazda kalıcı kurulum, iCloud kasası, widget'lar, kilit ekranı ve Denetim Merkezi girişleri, paylaşım uzantısı, TestFlight | Tek pakette verilmesi önerilir. Kimlik değişince uygulamanın kapsayıcısı da değişir; o zamana kadar gerçek veri, klasör seçiciyle seçilen ve kapsayıcının dışında duran bir klasörde tutulmalıdır. |
| Erişilemeyen kasada davranış | Aşama 8'deki madde | Bugün uygulama sessizce yerel kasaya geçiyor; durup sorması önerilir. |
| Zincirde esneklik | Aşama 10'daki zincir affı | Sektör taraması affeden zinciri destekliyor (`decisions.md`, açık sorular). |
| iPad desteği | Mağaza hazırlığı | Hedef cihaz listesinde var, düzeni ve belgesi yok: ya kapatılır ya tamamlanır. |
| Kilitliyken görünenler | Aşama 8'deki gizlilik maddeleri | Bildirim içeriği ve Siri'nin hedef adlarını listelemesi için varsayılan. |
| Gelir modeli ve lisans | Aşama 12 | Sektör taraması bu kategoride reklamı önermiyor. |
| Yapay zeka | Sonraki fikirler | Cihaz üstü model maliyetsiz bir seçenek; varsayılan kapalı önerilir. |
| İsim | Mağaza adı | Kimlikten bağımsız verilebilir. |

## Aşama 8: Sağlamlaştırma

Heyet incelemesinin bulguları. Her hata düzeltmesi onu yakalayan bir test ya da fixture ile gelir. Ölçümler 5 yıllık sentetik kasalarda (2.300 ile 2.400 dosya arası), Mac üzerinde yapıldı; iPhone'da ölçülmedi.

Doğruluk ve veri güvenliği:

- [x] Olay saati, cihazın saat dilimi farkı kadar kayık gösteriliyor; saat dosyadaki değerle gösterilir ve UTC dışı saat diliminde sınanır
- [x] Liste satırındaki birden çok düğme tek dokunuşta birlikte tetikleniyor (takma ad satırında "Kaydet" takma adı siliyor, günlük takviminde ay okları çalışmıyor); satır içi düğmeler ayrılır
- [x] Tekrarlayan görev düzenleme: uygulamanın kendi yazdığı görevde tekrar değiştirilemiyor, kimlik onarımıyla birlikte çöküyor, kuraldan sonraki kullanıcı metni siliniyor
- [x] Aynı dosya adı başka klasörde de varsa otomatik bağlantı yanlış dosyaya gidiyor; yazılacak hedefi indeks belirler (önce `vault-format.md`)
- [x] Doğal dil tarih: ondalık ve kesirli sayılar tarih sanılıp metinden siliniyor ("2.5 kg un al"), "haftaya salı" yanlış güne çözülüyor, Kısayollar yolu varsayımlı tarihi sormadan uyguluyor
- [x] Silmede onay ya da geri alma (olay, görev, alan, hedef kaydı); günlük yazısında kaydedilmemiş metin sormadan atılmaz
- [ ] Kayıtlı kasaya erişilemeyince durum ana ekranda görünür; yazılar sessizce başka kasaya gitmez (davranış kullanıcı kararı)
- [x] Uygulama meşgulken gelen yazma sıraya alınır; yutulan Enter ve yanlış "dosya dışarıdan değişti" hatası biter
- [ ] Uygulama kilidi "Hemen" ayarında başarılı doğrulamadan sonra yeniden kilitlenmez (gerçek cihazda doğrulanır) (kod ve test birleşti; kalan: gerçek cihazda doğrulama)
- [x] Kasa format sürümü her yazmada denetlenir; harf farkı olan klasör adı (`Journal/`) kasa hazırlamada bildirilir; ön bilgideki boş liste öğesi yeniden adlandırmayı durdurmaz
- [ ] iCloud Drive gibi eşitlenen bir klasör kasa seçildiğinde uyarı gösterilir (koordinasyon ve çakışma yönetimi Aşama 11'e kadar yok)

Ölçek:

- [x] Varlık yeniden adlandırma bağlantı sayısıyla karesel büyüyor (ölçüm: 139 sn ve yaklaşık 5 GB bellek); doğrusal hale getirilir
- [x] İlk indeksleme ve tip ekleme: boş indekste tam kurulum yolu kullanılır, kimlik sahipliği sorgusu indekslenir (şema sürümü artar)
- [x] Dosya değişmemişse yenileme hiçbir şey yayınlamaz; bildirimler her turda silinip kurulmaz
- [x] Yazma sonrası okuma modeli ana iş parçacığı dışında kurulur (ölçüm: olay eklerken 0,45 sn donma)
- [ ] Hedef işaretleme bütün kasayı okumaz; yazma başına tam dizin taraması kalkar (hedef işaretleme düzeltildi; kalan: yazma sırasında indeks güncellemesinin tam dizin taraması)
- [x] Sentetik kasa ile ölçek bütçe testleri: yenileme, yazma, yeniden adlandırma, ilk açılış
- [x] Okuma modeli dosya başına artımlı kurulur (5 yıllık kasada yazma sonrası 1,65 sn → 0,09 sn; ekranların kendi sorgusunu çalıştırması Aşama 11'e taşındı)

Veri sahipliği ve gizlilik:

- [x] Varsayılan kasa iPhone'da Dosyalar'da, Mac'te Finder'da görünür; ilk açılış ekranı kasanın nerede durduğunu söyler
- [ ] Bildirimlerde içeriği gizleme seçeneği; kilitliyken Siri'nin hedef adlarını listelemesi ve bildirim eylemiyle yazma için karar
- [x] İndeks yedekten hariç tutulur, veri koruma sınıfı kararı yazılır; arama geçmişi temizlenebilir ve kasaya bağlıdır

Erişilebilirlik ve dil:

- [x] Dokunma hedefleri en az 44 pt; hızlı giriş çubuğu büyük yazıda kırılmaz
- [x] Geciken tarih kırmızı ile, tamamlanan görev opaklıkla gösterilmez (kontrast ve "cezalandırma yok")
- [x] VoiceOver: graph tuvalinin erişilebilir karşılığı, öncelik değeri, günlük önizlemesi, kanban ve zaman çizelgesi eylemleri
- [x] Yerelleştirme: katalogda olmayan anahtarlar, ölü anahtarlar, "Her 1 hafta", Türkçe ek uyumu (`Ev'te`)

Kapılar:

- [x] Uygulama testleri iOS simülatöründe de koşar; fixture kasasıyla arayüz duman testi ve erişilebilirlik denetimi
- [x] Belge biçim denetimi (karar tablosu, README belge tablosu, String Catalog tamlığı); `Tests/` biçim denetimine girer
- [x] Kasa hazırlama yazıcıları fixture ile sınanır
- [x] Sürüm akışının kuru koşusu: `VERSION` yükseltme yolu ve etiket varken sessiz atlama

**Çıkış ölçütü:** Bu aşamadaki her hata bir test ya da fixture ile korunuyor; 5 yıllık sentetik kasada olay eklemek arayüzü dondurmuyor; iki hafta gerçek kullanımda veri kaybı ya da yanlış gösterim görülmüyor.

## Aşama 9: Tasarım dili

Yön seçildi: Mürekkep, sahibin iki değişikliğiyle. Yön, belirteçler ve kurallar `design.md` belgesindedir.

- [ ] Seçilen yönün Bugün ekranı için SwiftUI prototipi (gerçek cihazda gözle doğrulanır: ünlemli görev kutusu, büyük yazı, Kontrastı Artır; istenirse Derkenar'ın imzası)
- [ ] Tasarım belirteçleri (renk, tipografi, biçim, boşluk) ve asset catalog; uygulama simgesi
- [ ] Bileşen kitaplığı: tarih başlığı, hedef çipi, görev satırı, olay satırı, bölüm başlığı, hızlı giriş çubuğu, yüzey, çip, boş durum, ilerleme göstergesi, ısı haritası hücresi, bilgi bandı
- [ ] Bugün ve hızlı giriş: tarih başlığı, olayların ilk ekranda görünmesi, geciken görevlerin sınırlanması (taslak değişikliği önce `screens.md`'de)
- [ ] Günlük ve gün sayfası; varlık sayfalarında okuma ve düzenlemenin ayrılması; ham bağlantı sözdizimi ve teknik anahtarların gizlenmesi
- [ ] Görevler, kanban ve zaman çizelgesi; görünüm değiştirmenin tek kalıba bağlanması
- [ ] Hedefler, ısı haritası ve özetler; graph ve harita renkleri (renge ek olarak biçim)
- [ ] Mac geçişi; Ayarlar'ın bölünmesi (Gizlilik, Bildirimler, Takvim ve Konum, Kasa, Tanılama); ilk kullanım ve kilit ekranı
- [ ] Ekran görüntüsü testleri: açık ve koyu mod, büyük yazı, Kontrastı Artır

**Çıkış ölçütü:** Bütün ekranlar aynı bileşen kitaplığından kuruluyor; erişilebilirlik denetimi ve ekran görüntüsü testleri CI'da geçiyor.

## Aşama 10: Bağlam ve geri dönüş

Sektör taramasından çıkan, kimlik kararı gerektirmeyen ve ürünün farkını büyüten ilk dalga. Biçime dokunan maddeler önce `vault-format.md`'de tanımlanır.

- [ ] Bu gün geçmişte: Bugün'de kişi ve konumlu tek satır; yalnız veri varsa görünür
- [ ] Takvim etkinliğinden olay taslağı; katılımcı adları kişi adayı olur, emin değilse sorulur
- [ ] Varlık sayfasında bağlanmamış anmalar; satır satır, kullanıcı onayıyla bağlama
- [ ] Önemli tarihler: kişi ve özel tip dosyalarındaki tarih alanlarından doğum günü ve yıl dönümü satırı
- [ ] Kişi başına görüşme ritmi, erteleme ve duraklatma; isteğe bağlı, günlük tavanı olan hatırlatma
- [ ] Var olan giriş yollarının ilk kullanımda ve Ayarlar'da gösterilmesi (Eylem düğmesi, Siri cümleleri)
- [ ] Hızlı girişte tanınan tarih, öncelik, tekrar ve adların kutuda vurgulanması; dokununca ayrıştırma geri alınır
- [ ] Zincir affı: tek başına kalan kaçırma zinciri kırmaz, dinlenme günü, yumuşak ilerleme skoru (kullanıcı kararı)
- [ ] Suçlamasız taşıma (bugüne, yarına, haftaya) ve iki dakikalık "günü kapat"
- [ ] İsteğe bağlı ve atlanabilir haftalık inceleme; çıktısı günlük yazısına düşer
- [ ] Rehberden seçilen kişilerin tek yönlü, bir kez içe aktarılması
- [ ] Gün sayfasında "bu güne bağlananlar"; günlük takviminde yoğunluk noktaları

**Çıkış ölçütü:** Haftalık inceleme dört hafta üst üste tamamlanıyor; "bir süredir görüşmediklerin" listesinden ayda en az bir görüşme çıkıyor.

## Aşama 11: Kimlik, eşitleme ve widget'lar

Kimlik kararından sonra başlar.

- [ ] Kasa konumu: iCloud kapsayıcısı, yerel yedek seçenek (Aşama 0'dan devreden; yerel kasa ve klasör seçimi hazır)
- [ ] Eşitlenen kasada güvenli yazma: dosya koordinasyonu, indirilmemiş dosyalar, çakışan sürümlerin tespiti, birleştirme işlevinin bağlanması, kopya dosya kuralı, eşitleme durumu göstergesi
- [ ] Ana ekran widget'ı: zincir ve tek dokunuşla işaretleme; yapılmamışlar vurgulu (Aşama 3'ten devreden)
- [ ] Ekranlar ve widget kendi sorgusunu çalıştırır: küresel okuma modeli yerine Core sorguları (Aşama 8'den devreden; widget bellek sınırı için)
- [ ] Widget yenilenmesinin güvenilirlik testi (Aşama 3'ten devreden)
- [ ] Kilit ekranı widget'ı: takvim etkinlikleri ve günün görevleri (Aşama 3'ten devreden)
- [ ] Hızlı giriş widget'ı ile kilit ekranı, Denetim Merkezi ve Eylem düğmesi girişi (Aşama 3'ten devreden)
- [ ] Mac widget'ları (Aşama 3'ten devreden)
- [ ] Paylaşım uzantısı: "olay olarak ekle"
- [ ] Sistemin günlük önerileri (Journaling Suggestions) seçicisi

**Çıkış ölçütü:** İki cihazda iki hafta kullanımda kayıp ya da kopya dosya yok; alışkanlık uygulaması ve Lockday telefondan silindi.

## Aşama 12: Yayın

- [ ] Mağaza teknik hazırlığı: gizlilik bildirimi dosyası, ihracat bildirimi, uygulama simgesi, gizlilik politikası, üçüncü taraf lisans bildirimi, derleme numarası, platforma göre ayrılmış yetki dosyaları, iPad kararı, yer tutucu bölümlerin kaldırılması
- [ ] CD: TestFlight'a otomatik gönderim (Xcode Cloud ya da fastlane; Aşama 7'den devreden)
- [ ] Lisans, isim, gelir modeli; yazılı "veri kilidi yok" taahhüdü
- [ ] Mağaza sayfası: metinler, ekran görüntüleri, yaş derecelendirmesi

**Çıkış ölçütü:** İlk dış kullanıcı TestFlight'tan kurup kendi kasasını açabiliyor.

## Sonraki fikirler

Sırası ve kapsamı kesin değil; her biri ayrı karar ister.

- Fotoğraf ekleri (Obsidian uyumlu gömme; biçim önce belgede)
- Cihaz üstü sesle giriş
- Day One ve Apple Journal'dan içe aktarma
- İsteğe bağlı yapay zeka: haftalık ve aylık yazılı değerlendirme, yeni varlık önerisi, notlara soru (Aşama 6'dan devreden; karar açık)
- Apple Watch: hızlı giriş ve hedef işaretleme
- Yıl özeti, paylaşım kartı ve PDF
- Kişi ve konumların Spotlight'a açılması; Siri için okuma eylemleri
- Ziyaret önerileri ("dün şurada mıydın?"); sürekli konum izi kasaya yazılmaz
- Şirket şema paketi (Aşama 7'den devreden)
- Talep olursa Android ve Windows (Aşama 7'den devreden)

## Tamamlanan teknik kapsam

### Aşama 0: Temel

Kullanıcıya görünen bir şey yok; her şey bunun üstüne kurulur.

- [x] Xcode projesi: iOS ve macOS hedefleri, `Core` Swift paketi
- [x] CI (GitHub Actions): her PR'da derleme, `Core` testleri, biçim ve lint denetimi
- [x] Sürüm otomasyonu: `main`'e birleşince etiket ve GitHub Release
- [x] Dal koruması: `main` ve `dev` için PR ve geçen test zorunluluğu
- [x] Ayrıştırıcı ve yazıcı: frontmatter, bölümler, olay satırı, görev satırı (durum, metin, kimlik), wikilink, blok kimliği
- [x] Gidiş dönüş testi ve `Fixtures/` örnek kasası
- [x] SQLite indeksi (GRDB, FTS5) ve dosyalardan yeniden üretme
- [x] Dosya değişikliklerini izleme ve artımlı yeniden indeksleme
- [x] Senkronizasyon çakışmalarını birleştirme işlevi (uygulamaya bağlanması Aşama 11'de)

Kasa konumunun iCloud kısmı Aşama 11'e devretti.

### Aşama 1: Günlük

- [x] Bugün sayfası ve hızlı giriş kutusu
- [x] Olay ekleme (saat damgalı satır) ve serbest günlük yazısı
- [x] `@` ile kişi, konum için öneri listesi; yeni varlık oluşturma
- [x] Bilinen adların ve takma adların otomatik tanınması
- [x] Belirsiz eşleşmede bağlama göre sıralama; emin değilse kullanıcıya sorma
- [x] Aynı adlı varlık oluştururken ayırt edici sorma, dosya adını otomatik üretme
- [x] Varlık adını değiştirme ve tüm bağlantıları güncelleme
- [x] Geçmiş güne olay ekleme, saatsiz olay
- [x] Kişi ve konum sayfaları: şablon alanları, serbest ek alanlar, zaman akışı
- [x] Günler arasında gezinme
- [x] Tam metin arama ve hızlı geçiş
- [x] Mac'te kenar çubuklu, telefonda sekmeli düzen
- [x] Mac'te sistem genelinde kısayolla açılan hızlı giriş penceresi

### Aşama 2: Görevler

- [x] Görev ekleme, tarih verme, tamamlama; hızlı girişte olay / görev geçişi
- [x] Görevler sekmesi: yaklaşan, tarihsiz, tamamlanan
- [x] Doğal dille tarih ("yarın", "cuma", "5 ekim")
- [x] Bugün ekranında günün ve geciken görevler
- [x] Görevlerin kişi ve konumlara bağlanması; varlık sayfasında açık işler
- [x] Cihaz takvimindeki etkinliklerin bugün ekranında görünmesi (EventKit, salt okunur)
- [x] İleri tarihli ajanda listesi

### Aşama 3: Hedefler ve widget'lar

- [x] Hedef tanımlama: dönem (gün, hafta, yıl), tür (evet/hayır, sayı), miktar
- [x] Zincir, en uzun seri, ısı haritası; yıllık hedefte ilerleme çubuğu
- [x] Geçmiş günlerin hedef kaydını düzeltme

Widget maddeleri Aşama 11'e devretti.

### Aşama 4: Otomasyon

- [x] Görev ve hedef bildirimleri, akşam günlük hatırlatması; bildirimlerin güvenilirlik testi
- [x] Olay yazarken GPS ile konum önerisi
- [x] Konuma girince hedefi otomatik işaretleme ya da tek dokunuşluk bildirim
- [x] Kısayollar ve Siri ile giriş (App Intents)

### Aşama 5: Proje görünümleri

- [x] Kanban: duruma, projeye ya da kişiye göre
- [x] Zaman çizelgesi: başlangıç ve bitiş tarihli görevler (ağırlıklı Mac)
- [x] Proje etiketi ve proje sayfaları; sayılamayan yıllık hedefler
- [x] Tekrarlayan görevler, öncelikler

### Aşama 6: Geri bildirim

- [x] Haftalık ve aylık özetler (sayılara dayalı, yapay zekasız): kimlerle, nerelerde, hedef ve görev durumu
- [x] Kişi sayfasında son görüşme özeti; uzun süredir görüşülmeyenler
- [x] Graph ve harita görünümleri

İsteğe bağlı yapay zeka maddeleri "Sonraki fikirler"e devretti.

### Aşama 7: Genişleme

- [x] Yayın öncesi kullanıcı akışları
  - [x] İlk kullanım akışı
  - [x] Var olan Obsidian kasasını yerinde açma ve hazırlama
  - [x] Uygulama kilidi
- [x] Özel varlık tipleri (kitap, proje, vb.)

Mağaza teknik hazırlığı ve CD Aşama 12'ye; şirket şema paketi ile Android ve Windows "Sonraki fikirler"e devretti.
