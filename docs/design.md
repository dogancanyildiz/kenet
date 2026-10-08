# Tasarım dili

**Durum:** yön seçildi (2026-10-05): Mürekkep, proje sahibinin iki değişikliğiyle. Karar `decisions.md` tablosundadır; uygulama `roadmap.md` Aşama 9'dadır. Bu belge yönü, kuralları ve belirteçleri tutar; ekranların içeriği `screens.md` belgesindedir.

## Kısıtlar

iOS 26 ve macOS 26'dan beri sekme çubuğu, araç çubuğu ve sheet'ler sistemin Liquid Glass kromudur; HIG camı içerik katmanında istemez. Adaylar bu yüzden içerik katmanında ayrışır. Ürün metin ağırlıklıdır ve her gün, günde birçok kez açılır. Uygulamayı ekranı göremeyen kodlama ajanları yazar: bir dil, kurala bağlanabildiği ölçüde uygulanabilir.

## Nasıl seçildi

**İlk tur.** Proje sahibi beğendiği üç görseli paylaştı (repoda yok): tek renkli gri bir soft UI panosu; koyu zeminde tek turuncu vurgulu, bento kartlı bir görev planlayıcı; krem kâğıt üstünde mercan ve kömür renkli, dev rakamlı bir baskı düzeni. Yedi aday bu görsellerden ve sahibin andığı iki stilden (cam, kil) türetildi; oylamanın şartlarından "Günün Sayfası" çıktı. Aday listesi sahibin girdisine bağlı olduğu için bu sonuç bağımsız bir araştırmanın sonucu sayılmadı.

**Kör tur.** Sahibin görsellerini ve ilk turun sonucunu görmeyen altı tasarımcı (dört ayrı yapay zeka model ailesinden) aynı ürün için sıfırdan ikişer yön önerdi. Altısının da birinci tercihi aynı çıktı: kâğıt tonunda opak bir sayfa (krem, kırık beyaz ya da yeşilimsi), ince çizgiler ve kullanıcının kendi sözleri için serif yazı. Hiçbiri dev gün rakamı ya da ters renkli panel kullanmadı; sıcak turuncu bir vurguyu yalnız biri seçti. İkinci yönler sans ya da eş aralıklı yazılı ve yapı ağırlıklıydı: pano, karo, zaman rayı ya da cihaz paneli.

On iki yeni yön ve ilk turun dört finalisti aynı içerik ve aynı çerçeveyle Bugün ekranı için çizildi. Adları ve kökenleri gizlenerek beş bakış açısından (erişilebilirlik, platform mühendisliği, marka, günlük kullanım, ürün ruhu) bağımsız oylandı. Sahibin zevki bu turda bir üyeyle temsil edilmedi; o oy sahibindir.

## Oylama

Sıra puanında her oyda birinci 15, sonuncu 0 alır (en çok 75). "İkili" sütunu, adayın bire bir karşılaştırmada yendiği aday sayısıdır (15 üzerinden).

| Sıra | Aday | Tur | Tek cümle | Sıra puanı | İkili | Veto |
|---|---|---|---|---|---|---|
| 1 | Mürekkep | kör | Kenar boşluklu kitap sayfası: kullanıcının sözü serif, uygulamanın sözü sans, tek eylem rengi | 67 | 14 | 0 |
| 2 | Derkenar | kör | Aynı iskelet; kırmızımsı kenar çizgisi ve tanınan adların üstünde fosforlu kalem izi | 61 | 15 | 0 |
| 3 | Defter | kör | Krem kâğıt ve koyu yeşil; görev sans, düzyazı serif; hedefler üç sütun | 55 | 11 | 0 |
| 4 | Seyir Defteri (zaman rayı) | kör | Soğuk kayıt dökümü: saat sütunu, zaman rayı, tipine göre renkli bağlantılar | 52 | 13 | 0 |
| 5 | Seyir Defteri (çivit) | kör | Kullanıcının sözü serif, uygulamanın sözü eş aralıklı; ilerleme çeteleyle | 52 | 11 | 0 |
| 6 | Günün Sayfası | ilk | Krem kâğıt, dev gün rakamı, kor vurgu, kömür günlük paneli | 48 | 10 | 0 |
| 7 | Açık Defter | kör | Sakin kâğıt ve orman yeşili; çerçeveli hedef kutuları | 48 | 9 | 0 |
| 8 | Koordinat | kör | Sans; renk yalnız anlam taşır, bekleyen hedefler renkli karo | 44 | 9 | 0 |
| 9 | Gün Işığı | kör | Vurgu günün saatine göre değişir; üstte gün şeridi | 35 | 7 | 0 |
| 10 | Sessiz Kâğıt | kör | Sıkı dizilmiş kâğıt sayfa, 15 pt gövde, kiremit vurgu | 35 | 6 | 0 |
| 11 | Gün İşaretleri | kör | Sans ve mavi, kenarlıklı kartlar | 34 | 5 | 1 |
| 12 | A6 Matbaa | ilk | Krem kâğıt, mercan ve kömür, dev rakam, büyük harfli baskı etiketleri | 18 | 4 | 2 |
| 13 | Modern Monolit | kör | Yoğun pano, çip biçiminde bağlantılar, küçük büyük harfli etiketler | 16 | 2 | 2 |
| 14 | A5 Kor | ilk | Koyu zemin, tek turuncu, bento kartlar, hafta şeridi | 13 | 3 | 2 |
| 15 | Takvim Yaprağı | ilk | Bento iskeleti, sıcak kâğıt ve dev gün rakamı | 11 | 1 | 1 |
| 16 | Gösterge | kör | Cihaz paneli: tuşlar, lambalar, eş aralıklı ve dar yazılar | 11 | 0 | 3 |

Tablonun söyledikleri:

- **Aile.** Üyeler adayları kendi gözleriyle ailelere ayırdı; beşi de ürüne uygun aile olarak kartsız, serif içerikli sayfayı gösterdi (platform bakışı sisteme en yakın, yalnız belirteçle kurulan aileyi de aynı derecede uygun buldu). Bento, pano ve cihaz paneli aileleri ürünü planlayıcı ya da takipçi kategorisine taşıdığı ve olayları ilk ekranın dışına ittiği için sonda kaldı.
- **İki lider aynı iskelet.** Üç üye, birbirinden bağımsız, Derkenar'ı "Mürekkep ve üstüne iki imza" diye tarif etti. Derkenar bire bir karşılaştırmada her adayı yeniyor (Mürekkep'i 3–2); Mürekkep toplam puanda önde ve hiçbir üyenin sıralamasında dördüncüden aşağı düşmüyor. Derkenar'ı marka, günlük kullanım ve ürün ruhu bakışları birinci, erişilebilirlik ve platform bakışları sekizinci koydu.
- **İlk turun adayları.** Günün Sayfası 6., A6 Matbaa 12., A5 Kor 14., Takvim Yaprağı 15. sırada. İtirazlar ortaktı: ters renkli büyük yüzey altından geçen sistem camını açık ile koyu arasında çeviriyor ve bir sheet'e benziyor; sistem dışı yazı ailesi Kalın Metin ayarına uymuyor; küçük, büyük harfli etiketler okunmuyor; bento ve hafta şeridi ilk ekranın üst yarısını alıyor. Günün Sayfası bu grubun en ölçülü üyesi sayıldı ve veto almadı.
- **Model yakınlığı.** Jüri üyeleri üç modeldendi; aynı üç model kör turun on iki yönünden sekizini tasarlamıştı. Beş üyenin dördü, kökenini bilmeden, kendi modelinin tasarımını birinci koydu. Her üyenin kendi modelinden gelen adaylar sayımdan çıkarılınca Mürekkep'in sıraları 2, 4, 2; Derkenar'ın 8, 8, 1 oluyor. Heyet bu yüzden bire bir karşılaştırmanın galibini değil, bu düzeltmeden etkilenmeyen adayı önerdi.

## Seçilen yön: Mürekkep

Tek cümle: kasadan gelen her söz serifle (New York), uygulamanın her sözü sans ile (SF Pro) yazılır; gün, kenar boşluğunda saatleri ve işaretleri duran tek bir sayfadır.

### Sahibin değişiklikleri

Sahip, heyetin önerdiği Mürekkep'i iki değişiklikle seçti; ikisi de makete çizildi.

1. **Görev işareti köşeli kutudur, öncelik kutunun içindedir** (Derkenar'dan). Kutu 22 pt kare, köşe 5 pt. Boş kutu 1,5 pt kontrol çizgisi taşır; orta öncelikte içinde "!" durur; yüksek öncelikte çerçeve 2 pt ve metin rengindedir, içinde "!!" durur. Tamamlanan görevde kutu ikincil metin rengiyle dolar, içinde zemin renginde onay işareti durur. Kenar sütununda ayrı öncelik işareti kalmaz. Hedef işareti halka olarak kalır; böylece görev ile hedef biçimle de ayrışır.
2. **Hızlı girişte kip iki sözcüktür** (Defter'den). "Olay" ve "Görev" yan yana durur; seçili olan yarı kalındır ve altında 2 pt vurgu çizgisi taşır. Ardından "Gününden bir an…" yer tutucusu ve gönder düğmesi gelir. Kapsül Mürekkep'teki gibi kalır.

Derkenar'ın imzası (kenar çizgisi ve fosfor izi) eklenmedi; aşağıda ayrı başlıkta durur.

Jürinin notu: üç üye (platform, günlük kullanım, marka) önceliğin onay kutusunun içine yazılmasına itiraz etmişti: tek denetime iki durum yüklenir ve kutu uyarı rozeti gibi okunabilir. Sahibin kararı geçerlidir; prototipte dokunma davranışıyla birlikte sınanır. Açık ayrıntı: devam eden görevde (kutu yarı dolu) öncelik işaretinin yeri.

Neden:

- Hiçbir bakış açısı onu dördüncüden aşağı koymadı, veto almadı, toplam puanda birinci ve model yakınlığı düzeltmesinden sonra açık ara önde.
- Platform bakışının birincisi: Bugün tek bir `List`, tek bir satır bileşeni ve yalnız sistem yazı tipleriyle kurulur; özel çizim yalnız hedef halkasındadır. Platform bakışının kaba emek tahmini temel için 5–7 gün, bütün uygulama için 3–4 haftadır.
- İki ses kuralı ürünün vaadini görünür kılar: dosyada duran söz serif, uygulamanın eklediği ya da hesapladığı her şey sans. Kural verinin kökenine bağlı olduğu için ekranı görmeyen ajan uygulayabilir, inceleyen denetleyebilir.
- Derkenar aynı iskeletin üstüne iki imza ekler; Mürekkep'le başlamak o yolu kapatmaz.

Zayıf yanları:

- İmzası yok. Marka bakışı ekran görüntüsünü "zevkli ama anonim" buldu; ürün ruhu bakışına göre 1 piksellik alt çizgi tanımayı fısıldıyor ve yanlış bağlanan ad gözden kaçar.
- Büyük manşet ve bölüm aralıkları olayları ilk ekranın dışına itiyor (günlük kullanım bakışı).
- Hiyerarşi sessiz: bölüm etiketleri ve kenardaki öncelik işaretleri küçük (erişilebilirlik bakışı).
- Sayı ve bakışta durum bu dilin güçlü olmadığı yerdir (hedef ilerlemesi, widget, özetler, zaman çizelgesi); veri görünümleri için ikinci, sınırlı bir kural seti gerekir.

Jürinin şartları:

1. Bugün tek liste ve tek satır bileşenidir. Kenar sütununun genişliği yazı boyutuyla ölçeklenir; erişilebilirlik boyutlarında saat ve öncelik metnin üstüne iner.
2. Bağlantı yalnız standart metin öznitelikleriyle çizilir ve okuma metninde, hızlı girişte yazarken ve Mac'te aynı görünür. Kontrastı Artır'da alt çizgi kalınlaşır. Kişi ve konum renkleri Graph ve Harita ile aynı belirteçten gelir.
3. Hızlı girişte olay ve görev kipi görünür olur (sahibin ikinci değişikliğiyle karşılandı); artı ve gönder düğmelerinin ve kip sözcüklerinin dokunma alanı 44 pt'dir.
4. Manşet bloğu daraltılır; hedef, ilk olayın da kaydırmadan görünmesidir.
5. Görev kutusunun çizgisi koyulaştırılır: makette 3,48:1; erişilebilirlik bakışı denetim çizgilerinde 4,5:1 arıyor.
6. Mac kanbanı için çerçeveli, gölgesiz kâğıt kart; tablo ve zaman çizelgesi için tabular saat sütunu ve "şimdi" çizgisi tanımlanır.

### İmza (eklenmedi)

Derkenar, Mürekkep'in iskeletine iki şey ekler: kenar sütunu ile metin sütunu arasında 1 pt'lik gül kurusu bir kenar çizgisi ve uygulamanın tanıdığı kişi ve konum adlarının üstünde fosforlu kalem izi. Başlığı da araç çubuğu satırına alır; böylece 17 pt metinle görevler, takvim ve ilk olay kaydırmadan görünür.

- **İsteyenler (marka, günlük kullanım, ürün ruhu).** Ürünün farkı olan kendiliğinden tanımayı ekranda görünür kılan tek aday. Kimlik kartta ya da başlıkta değil metnin işaretlenme biçiminde durur, yani metin olan her ekranda vardır. Kenar çizgisi "solu uygulamanın, sağı kullanıcının" ayrımını yerleşimle verir.
- **İtiraz edenler (erişilebilirlik, platform).** Fosfor zeminin kâğıda kontrastı 1,11:1'dir; ayrımı gerçekte yarı kalın yazı taşır ve Kalın Metin açılınca fark daralır. Sarı zemin, sistemin bul ve ara eşleşme vurgusuyla aynı görünür. Önceliğin onay kutusunun içine yazılması tek denetime iki durum yükler. Yoğun günlük yazısında her adın sarı blok olması gürültü yapar.
- **Benimsenirse şartlar.** İz hiçbir zaman tek ipucu olmaz; altında Mürekkep'in tipli alt çizgisi durur. Sarı yalnız "uygulama bunu tanıdı" anlamına gelir; arama eşleşmesi, seçim ve uyarı başka biçim alır. İz yalnız akan metindeki adlarda kullanılır; varlığın kendi sayfasında kendi adında kullanılmaz. Kenar çizgisinin rengi hata ya da gecikme için kullanılmaz ve çizgi yalnız sayfa görünümlerinde durur (kanban ve zaman çizelgesine taşınmaz). Kâğıt dokusu, satır çizgisi ve el yazısı eklenmez.

Sahip imzayı istemedi; tanınan adlar alt çizgili kalır. İmza, Mürekkep'in üstüne eklenen ve geri alınabilen ince bir katmandır; istenirse Aşama 9'un prototipinde açılıp kapatılarak denenir.

Mürekkep'le birlikte kabul edilen ayrıntılar (istenirse değişir):

- **Vurgu rengi.** Mürdüm; yalnız eylemde (artı, gönder, seçili sekme, kip çizgisi) görünür. Sayfa ailesinin öteki üyeleri koyu yeşil, çivit ve çini mavisi kullandı; renk yapıyı değiştirmeden değişir.
- **Kişi ile konumun ayrımı.** Mürekkep'te kişi düz, konum noktalı alt çizgi taşır. Ürün ruhu bakışı noktalı ve kesik biçimin tipe değil "emin değilim, soruyorum" durumuna ayrılmasını, tipin yalnız renkle ayrılmasını önerdi.
- **Geciken görevin dili.** "Geciken" sözü ve kırmızı yoktur; görevin altında uyarı rengiyle "30 Eyl'den" yazar, üçten fazlası "N devreden daha" satırında toplanır.

## Sıradaki seçenekler

Seçim değişirse, oy sırası ve nedenleriyle:

1. **Derkenar.** Aynı iskelet, imza açık. Bire bir karşılaştırmanın galibi; "Mürekkep fazla sessiz" denirse ilk seçenek.
2. **Defter ya da Seyir Defteri (çivit).** Sayfa ailesinin iki başka üyesi. Defter erişilebilirlik bakışının birincisi: görev sans, düzyazı serif, koyu yeşil vurgu; hedefleri üç sütuna dizdiği için büyük yazıda ikinci bir yerleşim ister. Seyir Defteri (çivit) uygulamanın sözünü eş aralıklı yazıyla verir ve ilerlemeyi çeteleyle gösterir; "dosyalar senin" vaadini en görünür kılan aday, ama küçük, eş aralıklı etiketleri okumayı zorlaştırıyor.
3. **Seyir Defteri (zaman rayı).** Kâğıt ve serif istenmezse: aynı kenar sütunu yapısının soğuk, alet hali ve marka bakışının yedeği. Varlık tipini en iyi gösteren adaylardan; riskleri bağlantının yalnız renk ve kalınlıkla ayrılması ve ürünü ölçüm paneline yaklaştırması.
4. **Günün Sayfası.** Sahibin görsellerindeki dev gün rakamı ve kor vurgu isteniyorsa: ilk turun en iyi adayı, on altı aday içinde altıncı, vetosuz. Benimsenirse ters renkli günlük paneli ve sistem dışı yazı ailesi bırakılır.
5. **Açık Defter ya da Koordinat.** En ucuz ve geri dönüşü en kolay olanlar (platform bakışının üçüncüsü ve ikincisi); kimliği en az olanlar.

Önerilmeyenler: Gösterge (üç veto); A5 Kor, A6 Matbaa ve Modern Monolit (ikişer veto); Takvim Yaprağı ve Gün İşaretleri (birer veto).

Geri dönüş maliyeti: sayfa ailesinin üyeleri aynı belirteç rollerini, aynı iki sesli yazı kuralını ve aynı satır bileşenini paylaşır; aralarında geçiş, belirteç ve birkaç bileşen değişikliğidir.

## Her yönde geçerli kurallar

1. Gezinme sistemde kalır: iPhone'da `TabView`, Mac'te `NavigationSplitView`. Özel sekme çubuğu yazılmaz.
2. İçerik katmanında cam etkisi kullanılmaz; cam yalnız sistem kromunda ve hızlı giriş çubuğundadır.
3. Açık ve koyu modda yerleşim aynıdır; uygulamaya özel görünüm anahtarı yoktur.
4. Her renk belirteci dört varyantla tanımlanır: açık, koyu ve ikisinin Kontrastı Artır karşılığı. Gövde ve ikincil metin en az 4,5:1 (hedef 7:1), iri metin ve denetim sınırları en az 3:1 kontrast taşır.
5. Durum yalnız renkle, gölgeyle ya da opaklıkla anlatılmaz: bağlantı renkten başka bir ipucu daha taşır, devreden görev işaret ve tarih taşır, tamamlanan görev dolu onay işareti taşır ve metni okunur kalır.
6. Geciken tarih kırmızı değildir; uyarı rengiyle ve işaretle gösterilir. Kırmızı yalnız gerçek hatalara ve yıkıcı eylemlere ayrılır.
7. Vurgu kalanı gösterir: yapılmış hedef ve tamamlanan görev geri çekilir.
8. Yalnız sistem yazı tipleri kullanılır (New York ve SF Pro). Metin semantik stillerle yazılır (Dynamic Type); sabit punto kullanılmaz.
9. iOS'ta hiçbir metin 12 pt'nin altında değildir. Etiketler cümle düzeninde yazılır; büyük harfli, geniş aralıklı etiket kullanılmaz.
10. Dokunma hedefleri en az 44 pt'dir.
11. İçerikte büyük ters renkli yüzey bulunmaz: altından geçtiği sistem camını açık ile koyu arasında çevirir.
12. Mac'te kenar çubuğu simgeleri kullanıcının sistem vurgu rengini izler; marka rengi içerikte yaşar.
13. Hareket sistem varsayılanlarıyla sınırlıdır ve Hareketi Azalt ayarına uyar. Tek istisna Graph'tır: düğümler kuvvet benzetimiyle hareket eder (içerik hareketin kendisidir); Hareketi Azalt açıkken o da canlı oynamaz, düzen oturmuş hâliyle tek seferde gösterilir.

## Mürekkep'in kuralları

1. Yazı tipini veri türü seçer: kasadan gelen metin (olay, görev, günlük yazısı, not, alan değeri) ve sayfa adları New York, geri kalan her şey SF Pro. Yazı tipi ekranda elle seçilmez.
2. İçerikte kart yoktur. Bölüm, 1 piksellik süs çizgisi, başlık ve sağdaki sayaçtan oluşur.
3. Her satırın işareti (görev kutusu, hedef halkası, saat) kenar sütununda durur; öncelik görev kutusunun içindedir; metin tek sütunda akar.
4. Bağlantı metni metin rengindedir; anlamı alt çizgi taşır: kişi düz mavi, konum noktalı yeşil, çözülmemiş bağlantı kesik ve ikincil. Türkçe ek çizginin dışında kalır.
5. Eylem tek renktir (vurgu). Dikkat yalnız uyarı rengiyle ve yalnız devreden tarihinde gösterilir.
6. Yapılan soluklaşır (ikincil metin, dolu işaret) ve listenin sonuna iner; üstü çizilmez.

## Denetim kalıpları

Ekim 2026 denetimi (84 gerçek ekran görüntüsü ve kod envanteri) aynı işin ekrandan ekrana farklı kurulduğunu gösterdi: arama iki biçimde, "birini seç" beş biçimde, sheet başlığı üç yazıda, sheet zemini dört çeşitte. Aşağıdaki kalıplar tek tanımdır; her ekran bunları ortak bileşenlerle kurar, elle yeniden yazmaz. Referans Bugün ekranıdır.

1. **Sayfa üstü.** Sayfa adı solda serif manşettir; sayfanın eylem simgeleri aynı satırın sağında durur. Kök ekranlarda sistem gezinme çubuğu ve cam kapsül kullanılmaz. Bu madde iPhone içindir; Mac'te arama şimdilik pencere araç çubuğundadır ve Mac'in kalıbı ayrıca karara bağlanacaktır. Alt sayfalarda sistem çubuğunda yalnız geri düğmesi kalır; sayfanın eylemleri yine manşet satırındadır. Manşet satırı içerikle birlikte kayar. İstisna: Ara sayfasında manşet ve arama alanı sabittir; sonuçlar altında kayar.
2. **Manşet satırı simgeleri.** Çerçevesiz ve kapsülsüz simge; dokunma alanı 44 pt. Yardımcı eylemler (ara, sırala, filtrele, Ayarlar) ikincil metin rengindedir. Kayıt açan ya da içeriği değiştiren eylem (ekle, düzenle) vurgu rengindedir; "eylem tek renktir" kuralı bunlar içindir. Bir satırda en çok üç simge bulunur; fazlası sayfanın en üstünde satır olur (Günlük'teki Özetler satırı gibi). Sıra sabittir: en sağda ara, solunda ekrana özgü simgeler. Erişilebilirlik yazı boyutlarında simgeler manşetin üstünde ayrı satıra çıkar.
3. **Arama.** Genel arama her kök ekranda aynı yerde (manşet satırının en sağı) ve aynı simgeyle durur. Sayfa içi süzgeç alanı gereken ekranda Ara sayfasındaki alanla aynı bileşendir: çukur zemin, kontrol çizgisi, odakta vurgu çizgisi, yer tutucu italik.
4. **Birini seç.** İki biçim vardır ve hangisinin kullanılacağını seçenek sayısı belirler.
   - İki ya da üç seçenek: **sekme.** Sola yaslı sözcükler; seçili olan metin renginde ve altı vurgu rengiyle çizili, ötekiler ikincil renkte. Hızlı girişteki Olay | Görev ile aynı bileşendir. Yer: manşetin hemen altı.
   - Dört ve üstü seçenek: **menü.** Sola yaslı; solda ikincil renkte etiket ("Dönem", "Bölüm", "Grupla", "Ölçek"), sağında vurgu renginde seçili değer ve ok. Dokununca sistem menüsü açılır.
   - Sistem segmenti, onay kutucuğu dizisi, etiketsiz ya da ortalı menü ve gezinme çubuğuna konan seçici kullanılmaz.
5. **Sırala ve filtrele.** Manşet satırında simgedir; dokununca menü açılır. Sayfada ayrı satır tutmaz. Varsayılan dışında bir seçim etkinse simge vurgu rengine döner.
6. **Sheet.** Zemin kâğıttır; başlık serif manşettir; içerik sayfalarla aynı kalıptadır (bölüm başlığı, kâğıt zeminli satır, kart yok). Düzenleyen sheet'te solda "Vazgeç" (ikincil renk, düz yazı), sağda tek onay vardır: "Kaydet", yeni kayıt açan sheet'te "Oluştur" (vurgu rengi, yarı kalın düz yazı). Yalnız okunan sheet'te tek düğme vardır: sağda "Kapat". "Bitti" kullanılmaz. Eylemi taslak kaydetmek olmayan sheet'te (kasa hazırlığı gibi kasaya toplu yazan akışlar) çubukta yalnız "Vazgeç" durur; eylem kendi adıyla sayfada birincil düğmedir ve Return tuşuna bağlanmaz. Yazma sürerken "Vazgeç" devre dışı çizilir. Düğmeler düz yazıdır; dolu kapsül kullanılmaz. Mac'te sistem pencere başlığı çizilmez (tek serif manşet); araç çubuğu ve alt eylem çubuğu kâğıt zemindedir; "Vazgeç" solda, onay/"Kapat" sağda alt çubuktadır. Sheet gövdesi sıfır yükseklikte açılmaz (ortak ideal boyut).
7. **Sistem denetimleri.** Açma kapama anahtarı vurgu rengindedir. Kâğıt üstünde beyaz ya da gri kutu bulunmaz: alan zemini çukur, liste satırı kâğıttır. Yüzey rengi yalnız belirteç tablosunda sayılan yerlerde kullanılır.

Koruma: uygulama ekranlarında stil verilmemiş `Picker`, `.pickerStyle(.segmented)`, `.textFieldStyle(.roundedBorder)`, kök ekranda gezinme çubuğu araması ve ortak bileşen dışında kurulan sheet araç çubuğu kaynak denetimiyle yasaklanır. Her kök ekranın ve her sheet türünün ekran görüntüsü testi vardır.

## Belirteçler (Mürekkep)

Renkler (parantez içinde zemin üstündeki kontrast; KA: Kontrastı Artır):

| Belirteç | Açık | Koyu | KA açık | KA koyu | Kullanım |
|---|---|---|---|---|---|
| Zemin (kâğıt) | `#FAF8F3` | `#181614` | `#FAF8F3` | `#141210` | Sayfa, kaydırma alanı |
| Yüzey | `#FFFFFF` | `#23201C` | `#FFFFFF` | `#1E1B18` | Sheet içi, popover, Mac kanban kartı |
| Çukur | `#F1EDE4` | `#110F0E` | `#ECE7DC` | `#0C0B0A` | Isı haritasının boş hücresi, Mac'te hafta sonu |
| Süs çizgisi | `#E2DCCF` | `#302C27` | `#C4BBAB` | `#4C463E` | Bölüm çizgisi; bilgi taşımaz |
| Metin | `#1E1B17` (16,16) | `#EEE9DF` (14,91) | `#0E0C0A` (18,39) | `#FFFDF8` (18,38) | İçerik, başlık |
| İkincil metin | `#57514A` (7,38) | `#B5AD9F` (8,11) | `#403B35` (10,44) | `#D6CFC2` (12,07) | Meta, saat, yapılmış |
| Vurgu: metin ve simge | `#7A2C6E` (8,20) | `#E3A3D6` (9,00) | `#5E1F55` (10,97) | `#EDC3E5` (12,05) | Metin düğmesi, artı, seçili sekme |
| Vurgu dolgusunun üstündeki metin | `#FFFFFF` (8,70) | `#1A1022` (9,18) | `#FFFFFF` (11,65) | `#12091A` (12,54) | Gönder, birincil düğme |
| Uyarı | `#7A4E00` (6,78) | `#E2B865` (9,69) | `#5C3B00` (9,51) | `#F0CF8E` (12,48) | Yalnız devreden tarihi ve işareti |
| Tehlike | `#A11E1E` (7,27) | `#F07178` (6,31) | `#7A1010` (10,36) | `#FFB4B4` (11,07) | Yalnız yıkıcı eylem (silme) ve hata metni |
| Kontrol çizgisi | `#8C8478` (3,48) | `#7E776C` (4,08) | `#655E54` (6,03) | `#A39B8F` (6,80) | Görev kutusu, halka izi, artı konturu |
| Kişi | `#2D5BA6` (6,26) | `#8FB3F0` (8,49) | `#1D4689` (8,64) | `#B3CDF8` (11,57) | Düz alt çizgi, simge |
| Konum | `#386E43` (5,69) | `#8FCB9C` (9,62) | `#24562E` (8,09) | `#AEDDB8` (12,31) | Noktalı alt çizgi, simge |

Değerler tasarımcının hesabıdır; belirteç PR'ında palet denetimiyle yeniden doğrulanır. Vurgu, renk körlüğü benzetiminde kişi mavisinden ayrışsın diye mor yerine mürdüm seçildi. Veri görselleştirme (ısı haritası, graph, zaman çizelgesi) renge ek olarak biçim ipucu taşır.

Kod adları (`App/Design/`, asset catalog): Zemin → `Color.ink.paper` / `InkPaper`; Yüzey → `Color.ink.surface` / `InkSurface`; Çukur → `Color.ink.well` / `InkWell`; Süs çizgisi → `Color.ink.rule` / `InkRule`; Metin → `Color.ink.text` / `InkText`; İkincil metin → `Color.ink.secondaryText` / `InkSecondaryText`; Vurgu → `Color.ink.accent` / `InkAccent` (`AccentColor`); Vurgu dolgusunun üstündeki metin → `Color.ink.onAccent` / `InkOnAccent`; Uyarı → `Color.ink.warning` / `InkWarning`; Tehlike → `Color.ink.danger` / `InkDanger`; Kontrol çizgisi → `Color.ink.control` / `InkControl`; Kişi → `Color.ink.person` / `InkPerson`; Konum → `Color.ink.place` / `InkPlace`. Yazı: manşet → `Font.ink.display`; içerik → `Font.ink.content`; yer tutucu → `Font.ink.placeholder`; künye → `Font.ink.byline`; bölüm başlığı → `Font.ink.section`; meta → `Font.ink.meta`; değer → `Font.ink.value`; saat → `Font.ink.time`; büyük rakam → `Font.ink.largeNumber`. Biçim/boşluk: `InkSpacing`, `InkSize`, `InkStroke`; sayfa zemini → `.inkPage()`.

İmza benimsenirse eklenecek belirteçler (Derkenar'ın kendi zemininde ölçüldü; Mürekkep zemininde yeniden hesaplanır): fosfor izi `#FFEE99` (açık) ve `#4F4410` (koyu); kenar çizgisi `#D9796B` (açık) ve `#A85A50` (koyu).

Yazı:

| Rol | Aile ve ağırlık | iOS | Mac |
|---|---|---|---|
| Sayfa adı (manşet) | New York Semibold | 34 | 26 |
| İçerik | New York Regular | 17; günlük paragrafında satır yüksekliği 26 | 15 |
| Yer tutucu | New York Italic | 17 | 15 |
| Künye satırı | SF Pro Regular | 15 | 13 |
| Bölüm başlığı | SF Pro Semibold | 13 | 11 |
| Meta | SF Pro Regular | 13 | 11 |
| Değer ve saat | SF Pro, tabular rakam | 17 ve 15 | 13 |
| Büyük rakam (hedef detayı, özet) | SF Pro Light, tabular rakam | 48 | 34 |

Biçim: görev kutusu 22 pt kare (köşe 5 pt), hedef halkası 22 pt daire, artı 30 pt ve gönder 36 pt daire, hızlı giriş kapsüldür. Kenar boşluğu 16 pt, kenar sütunu 44 pt'dir. Mac'te sayfa en çok 680 pt genişliğinde ortalanır. İçerik opaktır; gölge, doku ve gradyan yoktur.

## Uygulama simgesi

Simgenin adı "Geçme"dir: iki şerit dik açıyla birbirinin içinden geçer. Mürekkep şerit yazıdır, mürdüm şerit bağdır (metnin kişi ve konumla kurduğu bağ). Renkler belirteç tablosundandır; gölge ve gradyan yoktur.

| Görünüm | Zemin | Mürekkep şerit | Mürdüm şerit | Dosya biçimi |
|---|---|---|---|---|
| Açık (varsayılan) | Kâğıt `#FAF8F3` | `#1E1B17` | `#7A2C6E` | Opak, alfa kanalı yok (mağaza şartı) |
| Koyu | Yok: sistemin koyu zemini görünür | `#EEE9DF` | `#E3A3D6` | Saydam zeminli |
| Tonlu | Siyah | Gri 0,52 | Gri 0,95 | Opak, gri tonlamalı; rengi sistem verir |
| Mac | Kâğıt renkli gövde | `#1E1B17` | `#7A2C6E` | Saydam kenar paylı |

- **Biçim.** 1024 birimlik tuvalde şerit kalınlığı 86, geçiş boşluğu 30 birimdir. Alttan geçen şerit, üstten geçenin iki yanından gerçekten kesilmiştir: boşluk zemin rengiyle boyanmaz, bu yüzden zemin değişince (koyu, tonlu, saydam) doğru kalır.
- **Mac gövdesi.** Mac simgesi yuvarlak köşeli kare gövdesini ve kenar payını kendi içinde taşır (1024 tuvalde 824 gövde, köşe yarıçapı gövdenin 0,225'i). Gövdenin altında sistem simge şablonundaki hafif gölge vardır: Dock ve Finder'da açık renkli gövdeyi açık zeminden ayırır. Bu gölge işaretin değil gövdenin parçasıdır; arayüzdeki "gölge yok" kuralı sürer. 16 ve 32 piksellik dosyalar ayrı çizimdir: şerit ve boşluk daha kalın, gölge yok.
- **Kaynak.** Vektör kaynak `App/Support/AppIcon/app-icon.svg` dosyasıdır (katmanlar: zemin, mürekkep şerit, mürdüm şerit); aynı klasörde koyu, tonlu ve Mac çizimleri durur. SVG ve PNG dosyaları elle düzenlenmez: hepsini `.github/scripts/render-app-icon.swift` aynı geometriden üretir. Yeniden üretme: `swift .github/scripts/render-app-icon.swift`. Betik belirlenimcidir; değişiklik yoksa dosyalar bayt düzeyinde aynı kalır.

## Bugün ekranı

Yukarıdan aşağı: manşet (tarih) ve künye satırı (olayla başlayıp "kaldı" ile biten özet: "3 olay · 4 görev ve 2 hedef kaldı"); hedefler (halka, ad, sağda değer ve tek dokunuşluk artı); görevler (köşeli kutu ve içinde öncelik, devreden görevde tarih); takvim (kasa dışı kaynak olduğu için sans); olaylar (kenarda saat); günlük yazısı (dört satır ve "Devamını yaz"). Altta hızlı giriş kapsülü ("Olay" ve "Görev" sözcükleri, yer tutucu, gönder) ve sistem sekme çubuğu.

`screens.md` taslağına işlenen ekler: manşet ve künye satırı; bölüm sayaçları; devreden görevlerin üç satır ve "N devreden daha" ile sınırlanması; birden çok tamamlanan görevin tek satıra katlanması. On geciken görevin nasıl görüneceğini adayların hiçbiri çizmedi; kural prototipte sınanır.

## Bileşenler

Manşet, bölüm başlığı, kenar sütunlu satır (görev, hedef, olay ve takvim için tek bileşen), görev kutusu, hedef halkası, bağlantılı metin, hızlı giriş kapsülü; bunlara ek olarak manşet satırı ve eylem simgeleri, sekme, etiketli menü, süzgeç alanı, sheet iskeleti (başlık ve iki düğme), etiket çipi, boş durum, ısı haritası hücresi, bilgi ve hata bandı, Mac kanban kartı. Bütün ekranlar bu parçalardan kurulur; görev satırı, kart ve tarih biçiminin bugünkü farklı varyantları tek parçaya iner.

## Doğrulama

- Prototip: Bugün ve kişi sayfası; seçilen yön (istenirse Derkenar'ın imzası açılıp kapatılarak); açık ve koyu mod, büyük yazı (AX3 ve AX5), Kontrastı Artır, Mac'te üç sütun. Ünlemli görev kutusunun dokunma davranışı ve devam eden görevdeki hali burada sınanır.
- İlk teknik doğrulama: renkli ve desenli alt çizginin bağlantı parçasında, okuma metninde ve hızlı giriş alanında çizildiği. Çizilmezse yedek yol, bağlantı metnini kişi ya da konum renginde yazmaktır (kontrastlar yeterli).
- **Doğrulama (2026-10-06):** `Text` ve `TextEditor` (`AttributedString`) içinde renkli desenli alt çizgi çiziliyor (`InkLinkStyle.mode == .underline`); `TextField` hâlâ `String` bağlar — yedek yol `InkLinkStyle` içinde durur.
- CI'da palet kontrast testi (her belirteç çifti için), erişilebilirlik denetimi ve ekran görüntüsü testleri. Ajanlar ekranı göremediği için ekran görüntüsü testleri bu projede zorunludur.

## Bilinen sınırlar

- Maketler HTML ile çizildi: cam ve simgeler yaklaşıktır; yalnız iPhone'da Bugün ekranı çizildi. Mac, Dynamic Type ve Kontrastı Artır görünümleri ve öteki ekranlar çizilmedi.
- Sahibin iki değişikliği oylamadan sonra eklendi; değişiklikli hali çizildi ama jüri oylamadı.
- Tasarımcıların ve jüri üyelerinin hepsi yapay zeka modeliydi; jüri tek model ailesindendi ve üyelerin çoğu kendi modelinin tasarımını seçti. Dört ayrı model ailesinin kâğıt ve serifte birleşmesi bağımsız bir doğrulama olabileceği gibi, bu modellerin ortak bir alışkanlığı da olabilir. Son söz sahibin gözündedir.
- Serif görev listesinin sans listeye göre daha yavaş tarandığına dair ölçüm yok; risk prototipte gözlenir.
- Sıcak özel zemin, HIG'in sistem zemin renklerini tercih etme önerisinden bilinçli bir sapmadır.
