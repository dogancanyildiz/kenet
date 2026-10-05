# Tasarım dili

**Durum:** heyet önerisi (2026-10-05); kullanıcı onayı bekliyor. Onaylanınca karar `decisions.md` tablosuna yazılır. Uygulama `roadmap.md` Aşama 9'dadır. Bu belge yönü, kuralları ve belirteçleri tutar; ekranların içeriği `screens.md` belgesindedir.

## Girdiler

Proje sahibinin beğendiği üç görsel (repoda yok): tek renkli gri bir soft UI panosu; koyu zeminde tek turuncu vurgulu, bento kartlı bir görev planlayıcı; krem kâğıt üstünde mercan ve kömür renkli, dev rakamlı bir baskı düzeni. Yüzeyleri farklı, ortak özellikleri aynı:

1. Biri vurgulu bir rakam dizisi (gün şeridi ya da rakam karuseli)
2. Tarih ve rakamın ekrandaki en büyük öğe olması
3. Dar palet ve tek sıcak vurgu; mavi, mor ve pastel yok
4. Yuvarlak modüller
5. Ekranda bir ters renkli blok
6. Varsayılan liste görünümünden uzak, tasarlanmış bir nesne hissi

Kısıtlar: iOS 26 ve macOS 26'dan beri sekme çubuğu, araç çubuğu ve sheet'ler sistemin Liquid Glass kromudur; HIG camı içerik katmanında istemez. Ürün metin ağırlıklıdır ve her gün açılır.

## Adaylar ve oylama

Yedi aday yön aynı içerikle Bugün ekranı için çizildi ve beş bakış açısından (erişilebilirlik, platform mühendisliği, marka, sahibin zevki, günlük kullanım) bağımsız oylandı. Sıra puanında her oyda birinci 6, sonuncu 0 alır.

| Aday | Tek cümle | Sıra puanı | Ortalama (10) | Veto |
|---|---|---|---|---|
| A7 Sayfa ve Cam | İçerikte kâğıt ve serif, kromda sistem camı | 26 | 7,6 | 0 |
| A6 Matbaa | Krem kâğıt, mercan ve kömür, dev rakam, ince çizgi | 24 | 7,4 | 0 |
| A5 Kor | Koyu zemin, tek turuncu, bento kartlar, hafta şeridi | 18 | 6,0 | 0 |
| A1 Yalın Cam | Sistem bileşenleri ve tek sıcak ton | 16 | 5,8 | 1 |
| A4 Kabartma | Tek renk taş yüzey, kabartma ve oyma | 9 | 4,0 | 2 |
| A2 Vitray | Gradyan zemin üstünde buzlu cam kartlar | 7 | 3,4 | 2 |
| A3 Hamur | Pastel, şişkin kil yüzeyler | 5 | 3,2 | 3 |

A7 beş oyun üçünde birinci ve bire bir karşılaştırmada her adayı yeniyor; A6 her oyda ilk üçte. A7'yi birinci koymayan iki üye marka ve sahibin zevki bakış açılarıydı: gerekçeleri imzasının olmaması ve açık ile koyu modun iki ayrı uygulama gibi durmasıydı. Bu yüzden öneri A7'nin kendisi değil, jürinin şartlarıyla düzeltilmiş halidir.

## Öneri: Günün Sayfası

A7'nin yapısı ve yazı disiplini, A6'nın imzası (gün rakamı, çizgi, kömür panel) ve tek kor tonu. Tek cümle: kâğıt üstünde günün rakamı, çizgi ve metin; renk yalnız bugünü, kalanı ve bağlantıyı gösterir.

Neden:

- Erişilebilirlik ve platform bakış açılarının birincisi olan A7'nin tabanını korur: sistem bileşenleri, opak içerik, sistem yazı tipleri. Liquid Glass, Dynamic Type ve erişilebilirlik ayarları kendiliğinden çalışır.
- Marka ve zevk bakış açılarının itirazını karşılar: gün rakamı ekranın ilk ve en büyük öğesidir, iki modda yerleşim aynıdır, tek bir sıcak ton vardır.
- İlk ekran yoğunluğu en iyi adaylarla aynıdır: makette ilk görev 322 pikselde başlar, beş görevin beşi kaydırmadan görünür.

Jüri bu yönü çizilmiş haliyle oylamadı; oylamadan sonra şartlardan türetildi ve ardından çizildi. Kesin karardan önce sahibin gözüyle ve gerçek cihazda bir SwiftUI prototipiyle doğrulanır.

Sahibin karar vereceği açık noktalar:

- **İçerik yazısı serif mi?** Öneri New York; üç görselin hiçbirinde serif yok ve sahibin zevkini temsil eden üye sorulmadan girmesine karşı çıktı. Serif ile sans arasında bir ayar da önerildi.
- **Gün rakamının boyutu.** Makette 72 pt. Marka bakışı 96 pt istedi; günlük kullanım bakışı tarih bloğunun yaklaşık 50 pt yüksekliği geçmemesini istedi. Makette rakam gezinme satırının yanında durduğu için ilk görevin konumu A7 ile aynı kaldı.
- **Komşu günler.** Rakamın yanındaki soluk günlere dokununca o güne gitmek, Bugün ekranına küçük bir ek olur. Günlük kullanım bakışı bunları süs sayıp istemedi; marka ve zevk bakışları imza saydı.

## Sıradaki seçenekler

Öneri beğenilmezse oy sırasıyla:

1. **A6 Matbaa.** Aynı ailenin daha cesur hali: daha büyük rakam, baskı etiketleri, çizgili giriş alanı. Günün Sayfası'ndan geçiş ucuzdur. Riskleri küçük büyük harfli etiketler ve iki ek yazı ailesi.
2. **A5 Kor ya da Takvim Yaprağı.** Sahibin iki kez paylaştığı görselin dili. Takvim Yaprağı, A5'in bento iskeletini sıcak kâğıt ve dev gün rakamıyla birleştiren, serifsiz bir melezdir (sahibin zevkini temsil eden üyenin önerisi; çizildi, oylanmadı). Riski Bugün ekranının pano gibi okunması: makette ilk görev 409 pikselde başlar, beş görevin dördü görünür.
3. **A1 Yalın Cam.** En ucuz ve en güvenli; bir dil değil, dilin yokluğu. Her yolun ilk adımıdır.
4. **A4 Kabartma.** Gri panonun en sadık çevirisi; iki veto aldı. Kabartma koyu modda ve güneş altında kayboluyor, erişilebilir hali stili seyreltiyor.
5. **A2 Vitray ve A3 Hamur.** Önerilmez: üç görselde karşılıkları yok, özel çizim ve bakım yükleri yüksek, vetoludurlar.

Geri dönüş maliyeti: A1, Günün Sayfası ve A6 aynı merdivenin basamaklarıdır (belirteçler, kâğıt ve yazı, baskı motifleri); A5'in paleti bu merdivene eklenebilir. Bu dördü arasında karar sonradan ucuza değişir. A2, A3 ve A4 başka hiçbir yönde yeniden kullanılmayan özel çizim ister.

## Her yönde geçerli kurallar

1. Gezinme sistemde kalır: iPhone'da `TabView`, Mac'te `NavigationSplitView`. Özel sekme çubuğu yazılmaz.
2. İçerik katmanında cam etkisi kullanılmaz; cam yalnız sistem kromunda ve hızlı giriş çubuğundadır.
3. Açık ve koyu modda yerleşim aynıdır; uygulamaya özel görünüm anahtarı yoktur.
4. Her renk belirteci dört varyantla tanımlanır: açık, koyu ve ikisinin Kontrastı Artır karşılığı. Gövde ve ikincil metin en az 4,5:1 (hedef 7:1), iri metin ve denetim sınırları en az 3:1 kontrast taşır.
5. Durum yalnız renkle ya da gölgeyle anlatılmaz: bağlantı renk ve alt çizgi, geciken görev simge ve tarih, tamamlanan görev üstü çizili metin taşır.
6. Geciken tarih kırmızı değildir; uyarı rengiyle ve simgeyle gösterilir. Kırmızı yalnız gerçek hatalara ayrılır.
7. Vurgu kalanı gösterir: yapılmamış hedefin halkası vurgu rengindedir, yapılmış hedef ve tamamlanan görev gridir.
8. Vurgu iki belirteçtir: metin ve simge için bir ton, dolgu için ayrı bir ton ve üstündeki metin rengi. Ekranda aynı anda en çok bir dolu vurgu yüzeyi bulunur.
9. Metin semantik stillerle yazılır (Dynamic Type); hiçbir metin 12 pt'nin altında değildir. Büyük harfli etiket yalnız bölüm başlığında ve tarih satırında kullanılır.
10. Dokunma hedefleri en az 44 pt'dir.
11. Mac'te kenar çubuğu simgeleri kullanıcının sistem vurgu rengini izler; marka rengi içerikte yaşar.
12. Hareket sistem varsayılanlarıyla sınırlıdır ve Hareketi Azalt ayarına uyar.

## Belirteçler (Günün Sayfası)

Renkler (parantez içinde zemin üstündeki hesaplanmış kontrast):

| Belirteç | Açık | Koyu |
|---|---|---|
| Zemin (kâğıt) | `#F4EDE1` | `#1E1C1A` |
| Yüzey | `#FBF7EF` | `#2A2724` |
| Metin | `#22201D` (13,96) | `#F0E9DD` (14,08) |
| İkincil metin | `#564E45` (7,02) | `#B8AE9F` (7,76) |
| Vurgu: metin, simge, halka, bağlantı | `#AE3A10` (5,29) | `#FF8456` (7,03) |
| İri rakam ve grafik (yalnız 34 pt ve üstü) | `#D24A1E` (3,81) | `#FF8456` (7,03) |
| Uyarı | `#7F5200` (5,80) | `#F2C15A` (10,15) |
| Kontrol çizgisi | `#857B6E` (3,57) | `#8F8678` (4,73) |
| Günlük paneli | `#2F2D2A`, üstünde `#FBF7EF` metin (12,85) | `#2A2724` ve ince çizgi, üstünde `#F0E9DD` metin (12,31) |

Değerler maket üzerinde hesaplandı; belirteç PR'ında palet denetimiyle yeniden doğrulanır. Koyu modda ikincil metin yüzey üstünde 6,78:1'de kalır; hedef tutturulana kadar yüzey üstünde ikincil metin kullanılmaz. Veri görselleştirme (ısı haritası, graph, zaman çizelgesi) için ayrı bir palet ve renk dışı ipucu gerekir; tek vurgunun ara basamakları zemine karşı yeterli kontrast vermez.

Yazı:

| Rol | Aile | Not |
|---|---|---|
| İçerik: olay, görev, günlük yazısı, hedef adı | New York | Sahibin onayına bağlı; onaylanmazsa SF Pro |
| Arayüz, meta, saat, etiket | SF Pro | Meta ve alt grup başlıkları cümle düzeninde |
| Kahraman rakamlar (28 pt ve üstü): gün, özet, zincir | Avenir Next | Kalın Metin ayarı elle uygulanır; istenmezse New York |

Biçim: kart yok; bölümleri 1 pt, satırları 0,5 pt çizgi ayırır. Tek büyük biçim, üst köşeleri 28 pt yuvarlak günlük panelidir. Halka ve disk motifi gün ve hedef durumu için ortaktır. Gölge ve doku yoktur.

## Bugün ekranı

Yukarıdan aşağı: gün rakamı ve tarih satırı; hedefler (halka, ad, tek satır meta); görevler; takvim; olaylar (saat sütunu ve ince zaman çizgisi); günlük yazısı paneli. Altta hızlı giriş çubuğu ve sistem sekme çubuğu. Bölüm başlığının sağ ucunda küçük bir özet durur ("1/3", "4 kaldı").

`screens.md` taslağına ekler (sahibin onayına bağlı): tarih başlığı, bölüm özetleri, geciken görevlerin üç satır ve "N tane daha" ile sınırlanması.

## Bileşenler

Tarih başlığı, bölüm başlığı, hedef halkası, görev satırı ve onay stili, olay satırı, günlük paneli, hızlı giriş çubuğu, etiket çipi, boş durum, ilerleme göstergesi, ısı haritası hücresi, bilgi ve hata bandı. Bütün ekranlar bu parçalardan kurulur; görev satırı, kart ve tarih biçiminin bugünkü farklı varyantları tek parçaya iner.

## Doğrulama

- Karar öncesi prototip: Bugün ve bir ikinci ekran; açık ve koyu mod, büyük yazı (AX3 ve AX5), Kontrastı Artır, Mac'te üç sütun.
- CI'da palet kontrast denetimi, erişilebilirlik denetimi ve ekran görüntüsü testleri. Ajanlar ekranı göremediği için ekran görüntüsü testleri bu projede zorunludur.

## Bilinen sınırlar

- Maketler HTML ile çizildi: cam ve simgeler yaklaşıktır; yalnız iPhone boyutu çizildi. Mac, Dynamic Type ve Kontrastı Artır görünümleri çizilmedi; koyu modun günlük paneli hiçbir makette yok.
- Hedef sütunları üç kısa adla denendi; uzun ad ya da dördüncü hedef bu genişliğe sığmaz, hedef şeridinin taşma davranışı prototipte çözülmelidir.
- Araştırma, maket ve jüri aynı yapay zeka model ailesiyle yürütüldü. Krem zemin, serif yazı ve kiremit vurgu bu modellerin sık ürettiği bir görünümdür; önerinin bu yöne çıkmasında payı olabilir. Sahibin üçüncü görseli aynı paleti bağımsız olarak destekliyor, ama son söz sahibin gözündedir.
