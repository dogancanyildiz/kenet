# Ekranlar

Hangi ekranlar var, her birinde ne görünür ve aralarında nasıl geçilir. Her bölümün yanındaki sayı, o parçanın geldiği aşamadır (bkz. `roadmap.md`).

## Tasarım ilkeleri

1. **Kilit ekranından ilk kelimeye en kısa yol.** Giriş her zaman bir dokunuş uzaklıkta.
2. **Bugün ekranı sade kalır.** Uygulama çok şey yapar ama her gün bakılan ekran kalabalıklaşmaz; ayrıntı diğer sekmelerdedir.
3. **Telefon giriş ve hızlı bakış, Mac düzenleme ve geniş görünümler içindir.**
4. **Kalanı vurgula.** Listeler ve widget'lar yapılmışı değil yapılacak olanı öne çıkarır.
5. **Cezalandırma.** Kaçan gün, geciken görev ya da boş günlük suçlayıcı bir dille gösterilmez.

## iPhone

Alt sekmeler: **Bugün, Günlük, Görevler, Kişiler ve Konumlar, Hedefler.** Arama sekme değildir; her kök ekranda manşet satırının en sağında simge olarak durur. Sayfa üstü, seçiciler, sıralama ve sheet'ler için ortak kalıp `design.md` içindeki "Denetim kalıpları" bölümündedir; aşağıdaki ekran tarifleri o kalıbı kullanır.

### Bugün (1, 2, 3)

Uygulama bu ekranda açılır. Yukarıdan aşağıya:

1. **Manşet ve künye (9):** Günün tarihi sayfada New York Semibold manşettir; altında tek satırlık künye durur: olayla başlar, kalanla biter ("3 olay · 4 görev ve 2 hedef kaldı"); sıfır olan parça yazılmaz, hiçbir şey yoksa satır yoktur. Bugün sekmesinde gezinme çubuğu gizlenir; arama ve Ayarlar manşet satırının sağındadır (Ayarlar yalnız telefonda, `button.settings`); erişilebilirlik yazı boyutlarında düğmeler manşetin üstünde sağa yaslı ayrı bir satırdadır. Dar genişlikte manşet önce tam biçimi, gerekirse kısaltılmış ay biçimini ve en çok %75 ölçeği dener; VoiceOver her zaman tam biçimi okur. Geçmiş gün sayfasında geri düğmesi için gezinme çubuğu kalır. VoiceOver ve geçmiş için `navigationTitle` yine tarih metnidir.
2. **Hedefler (3):** Günün (günlük dönemli) hedefleri; bölüm sayacı yalnız bunları sayar (`countedGoalIDs` ile aynı küme). Altında haftalık/yıllık hedefler aynı satır bileşeniyle listelenir; meta satırında dönem ilerleme metni vardır (sayaç dışı). Tek dokunuşluk artı ile işaretlenir veya sayısal değerde bir artar; sayısal hedefte değer metnine dokununca (veya basılı tutunca / menüden) miktar girilir. Yapılmamışlar belirgin, yapılmışlar soluk.
3. **Görevler (2):** Devreden görevler, bugünün görevleri ve bugün oluşturulan tarihsiz görevler. Kutuya (veya bağlantısız satıra) dokununca tamamlanır, basılı tutunca düzenlenir. Devreden görevin altında geldiği tarih yazar ("30 Eyl'den"); en çok üçü gösterilir, kalanı "N devreden daha" satırında toplanır ve dokununca açılır. Tamamlanan görev listenin sonuna iner; birden çok tamamlanan tek satıra katlanır ("N görev tamamlandı") ve dokununca açılır.
4. **Takvim (2):** Cihaz takvimindeki bugünkü etkinlikler, salt okunur (sans satır).
5. **Olaylar (1):** Bugün yazılan olaylar, dosyadaki sırayla (uygulama saatli olayı saat sırasındaki yerine yazar). Kenarda saat; kişi ve konum adları dokunulabilir bağlantıdır.
6. **Günlük yazısı (1):** Varsa serbest yazının ilk dört satırı ve "Devamını yaz"; dokununca tam ekran yazma alanı açılır.

Bölüm başlıklarının sağında sayaç durur: hedeflerde yapılan ve toplam (`m/n`), görevlerde kalan, olaylarda sayı. Varsayılan yazı boyutunda (390×844, alt güvenli alan ≈84 pt) hızlı giriş tek satırlı kapsüldür; manşet, hedefler, görevler ve ilk olay satırı kaydırmadan görünür. Geçmiş bir günün sayfası aynı düzeni kullanır.

En altta sabit **hızlı giriş kapsülü** (opak; içeriğin üstüne binmez).

### Hızlı giriş (1, 2)

- Tek metin kutusu. Başında kip iki sözcükle durur: **Olay** ve **Görev**; seçili olan yarı kalındır ve altında vurgu çizgisi taşır, varsayılan olay.
- Görev modunda `#project/` yazınca mevcut proje adları önerilir; seçim etiketi tamamlar, yeni ad serbesttir.
- `@` yazınca kişi ve konum önerileri açılır. `@` kullanılmasa da bilinen adlar yazarken tanınır ve vurgulanır.
- Birden fazla aday varsa en olası olan önerilir; uygulama emin değilse seçim ister.
- Tanınmayan bir ad `@` ile yazıldıysa "kişi olarak ekle" ya da "konum olarak ekle" seçeneği çıkar. Aynı adda varlık varsa kısa bir ayırt edici sorulur.
- Görev modunda baş/son bağımsız `!` orta, `!!` yüksek önceliktir; `her hafta`/`every week` gibi tekrar ifadesi önceden gösterilir ve gönderimde alanlara çevrilir.
- Görev modunda tarih cümleden çıkarılır ("yarın Ahmet'i ara") ve kutunun üstünde onay için gösterilir; yanlışsa dokunup düzeltilir.
- Olay varsayılan olarak şu anki saatle kaydedilir; saat kaldırılabilir ya da değiştirilebilir.
- Gönderince kutu boşalır, klavye açık kalır; art arda giriş yapılabilir.
- Konum izni Ayarlar → Takvim ve Konum düğmesiyle verilir. Odaklanma ve gönderim en çok dakikada bir tek seferlik GPS isteği başlatır. Kutunun üstündeki en yakın konum çipi dokunulunca sabit `@Konum` anması ekler; kapatma mevcut taslak oturumunda kalıcıdır, kayıt sonrası sıfırlanır. Olay ve görev için aynı davranış kullanılır. Konum önerisi anahtarı ve sistem ayarları bağlantısı Ayarlar → Takvim ve Konum’dadır.

### Günlük (1)

- Sayfa adı serif manşet olarak listenin içinde durur; gezinme çubuğunda büyük başlık yoktur.
- Günlerin ters kronolojik listesi; her günde olay sayısı ve günlük yazısının ilk satırı.
- Üstte Özetler girişi ve takvim ile güne atlama; bugünün günü halkayla işaretlenir (rakam ile halka arasında boşluk kalır).
- Bir güne girince: o günün olayları, görevleri, hedef kayıtları ve serbest yazısı. Bugün ekranıyla aynı düzen, herhangi bir gün için.
- Geçmiş bir güne olay eklenebilir ve o günün hedef kayıtları düzeltilebilir.

### Özetler (6)

Günlük içinden ve Mac kenar çubuğundan açılır. Hafta | Ay sekmesi (pazartesi–pazar haftası ya da takvim ayı), önceki/sonraki dönem ve Bu hafta / Bu ay düğmesi vardır. Günlük, Kişiler, Konumlar, Hedefler ve Görevler bölümleri sayıları ve önceki eş dönem farklarını nötr ok ve işaretli metinle gösterir (kart yok). Kişi/konumların ilk beşi kendi sayfasına bağlanır; sıralama geçiş sayısı azalan, eşitlerde ad ve yol sırasıdır. Boş dönemde “Bu dönemde kayıt yok.” gösterilir; taşınan açık işler yine görülebilir.

- Olay sayısı olay bloklarını; yazılan gün sayısı en az bir olay veya boş olmayan Journal paragrafı/başlığı bulunan farklı gün tarihlerini sayar. Yalnız görev veya hedef kaydı yazılan gün sayılmaz.
- Kişi/konum geçişi, gün dosyalarının gövdesindeki çözülen her bağlantıdır; tekrarlar ayrı sayılır, frontmatter bağlantıları sayılmaz. Bölüm toplamı ilk beş dışındakileri de içerir. Oluşturulma tarihi kasada bulunmadığından **İlk kez geçenler**, bütün günlük geçmişinde ilk gövde bağlantısı bu döneme düşen varlıkları sayar; dosya oluşturulma sayısı değildir.
- Görev oluşturulma günü kaynak gün dosyasının tarihidir (tekrarlayan görev de kaynak gününe sayılır). Tamamlanan, mevcut durumu tamamlanmış ve `✅` tarihi dönemde olan görevdir. Dönem sonu açık envanteri, o güne kadar kaynak gün dosyasında bulunan ve henüz tamamlanmamış görevlerden üretilir; sonraki tarihli tamamlanma geçmişte açık sayılır. Bitiş tarihi dönem sonundan önceyse geciken, bitiş tarihi yoksa tarihsiz açıktır. İptaller ve tamamlanma tarihi olmayan tamamlanmış görevler envantere katılmaz. Kaynak gün tarihi olmayan görev oluşturulma/açık sayısına girmez; geçerli tamamlanma tarihiyle tamamlanan sayısına girebilir. Dosyalar durum/değişiklik geçmişi tutmadığından yeniden açma, iptal tarihi veya eski bitiş tarihi geri kurulamaz.
- Günlük hedefte dönem katkısı ve hedef × gün sayısı; haftalık hedefte katkı ve hedef × dönemin değdiği pazartesi haftalarının sayısı (ay kenarlarındaki kısmi haftalar dahil) gösterilir. Yıllık hedefte dönem sonundaki yıl başından ilerleme, farkta yalnız seçilen dönemin katkısı gösterilir. Zincir bütün geçmişten dönem sonu itibarıyla hesaplanır. Kilometre taşında yıl içindeki ilk tamamlanma ve tarihi gösterilir; aynı yıl tekrarlanan kayıt katkıyı artırmaz, zincir gösterilmez. Önceki dönem ilerleme farkı iki dönemin katkı farkıdır; zincir farkı dönem sonlarının farkıdır.

### Görevler (2, 5)

Sayfa adı serif manşet olarak listenin içinde durur; gezinme çubuğunda büyük başlık yoktur. Proje ve görev ayrıntısı sayfaları aynı kalıbı kullanır. Kanban ve zaman çizelgesi geniş yüzeydir (680 pt sütun sınırına girmez).

Görünüm iki katmanda seçilir. Manşetin altında sekme: Liste | Kanban | Zaman çizelgesi. Sekmenin altında görünüme göre değişen tek menü: Liste'de "Bölüm" (Yaklaşan, Tarihsiz, Tamamlanan, Projeler), Kanban'da "Grupla" (durum, proje, kişi), Zaman çizelgesi'nde "Ölçek". Filtre ve arama manşet satırında simgedir. Son sekme ve her sekmenin son menü seçimi iPhone'da hatırlanır. Mac kenar çubuğundaki Kanban, Zaman çizelgesi ve proje girişleri gezinme düzenidir ve değişmez.

- **Yaklaşan:** Tarihli görevler, güne göre gruplu ajanda listesi. Grup başlığı bölüm başlığı + sayaçtır; "Devreden" (eski "Geciken") grubu vardır.
- **Tarihsiz:** Bitiş tarihi olmayan açık görevler.
- **Tamamlanan:** Son tamamlananlar; satır soluk, üstü çizilmez.
- **Projeler (5):** Etiketlerden türetilen liste ve açık görev sayısı. Proje sayfasında açık görevler bitiş gününe göre gruplu, tarihsizler ayrı; tamamlananlar, görevlerdeki kişi/konumlar ve son etkinlik (gün dosyası veya tamamlanma tarihinin en yenisi) bulunur. Planlanan başlangıç/bitiş tarihi etkinlik sayılmaz. Satırlar Görevler ile aynı görev satırı bileşenini kullanır.
- **Kanban (5):** Durum, proje veya kişi sütunları. Sütun başlığı sayaçlı bölüm başlığıdır; kart çerçeveli gölgesiz kâğıt karttır (öncelik kutunun içinde). İptal edilenler seçenekle açılır; tamamlanan görevler son 30 takvim günüyle sınırlıdır (bugün dahil, tarihsiz/future tamamlanmalar dışarıda). Kişi/konum/proje filtreleri ortak kullanılır. Birden çok çözülen kişiye bağlı görev her kişi sütununda görünür; kişisiz ve projesiz sütunlar vardır. Kartlar bitiş tarihi (tarihsiz en son), öncelik, metin ve eşitlerde kimlik sırasındadır; dosya sırası değişmez. Bilinmeyen açık durumlar Yapılacak sütununda korunur. Telefonda yatay kaydırmalı sütunlar, kart menüsünden taşıma ve ayrıntı sheet'i; Mac'te sürükle bırak ve sağ ayrıntı paneli. Durum/proje taşıması mevcut dosya yazıcılarını kullanır; kişi sütunları bağlantı metnini değiştirmez ve taşıma kabul etmez. Tarih kart menüsündeki seçiciden değişir.
- **Zaman çizelgesi (5):** Ortak kişi/konum/proje filtreleriyle tarihli görevler; Mac'te proje (varsayılan), kişi veya gruplamasız satırlar, açılır/kapanır gruplar ve hafta/ay/çeyrek ölçeği. Çok kişili görev kişi gruplarında tekrarlanır. Başlangıç-bitiş çubuk, yalnız bitiş tek günlük elmas, yalnız başlangıç bugüne kadar açık uçlu (gelecekteki başlangıç tek noktadan başlar); tarihsizler ayrı listededir. Tabular saat/tarih sütunu ve "bugün" çizgisi (vurgu rengi + etiket) vardır. Tamamlananlar soluk + dolu uç, iptaller gizli, devreden bitişler uyarı rengi + işaretle vurgulanır; hafta sonu sütunu çukur renktedir. Dışarıda yazılmış ters aralık kaynakta korunur, uyarıyla gösterilir; yeni değişiklikler ters aralık üretmez. Varsayılan aralık bugün -4 hafta / +12 hafta; eksen ±365 gün, Bugün düğmesi vardır. Telefonda hafta/ay başlıkları ve küçük çubuklu dikey liste, dönem düğmeleri ve tarih menüsü bulunur; sürükleme yoktur.

Filtre: kişi, konum, proje. Aynı gündeki görevler yüksek, orta, normal, düşük öncelik sırasındadır; eşitlerde dosya/satır sırası korunur. Görev satırında öncelik kutunun içindedir; tekrar rozeti vardır; düzenleme menüsünden Tekrar ve Öncelik seçilir. Tekrar seçicisi ve tarih seçici yüzey üstündedir. Görev ayrıntısında alanlar etiket-değer satırlarıdır.

### Kişiler ve Konumlar (1)

- Sayfa adı serif manşet olarak listenin içinde durur; gezinme çubuğunda büyük başlık yoktur.
- Manşetin altında tür seçici: yalnız Kişiler ve Konumlar varken sekme; kasada özel tip tanımlıysa (seçenek sayısı dördü bulunca) "Tür" menüsü. Sıralama (ada göre ya da son geçtiği tarihe göre) manşet satırında simgedir. Sayfa içi süzgeç alanı Ara sayfasındaki alanla aynı bileşendir. Graph ve Harita listenin en üstünde iki satırdır.
- Aynı adlı varlıklarda adın altında ayırt edici görünür.

**Varlık sayfası:**

1. Varsayılan görünüm okuma sayfasıdır: manşet (ad) sayfa içinde, künye (tip, takma adlar, son görülme), ayırt edici ve gelen bağlantı sayısı; gezinme çubuğunda büyük başlık yoktur
2. Düzenleme sheet'i ortak sheet kalıbını kullanır (serif manşet, kâğıt zemin, tek "Kapat": her alan kendi "Kaydet" düğmesiyle yazar, "Kapat" kaydetmez); kaydedilmemiş alan "Alanı kaldır" ile silinince taslak kirli sayılmaz
3. Şablon alanları etiket-değer satırları olarak; tanınmayan ön bilgi anahtarları "Diğer alanlar" altında ham adıyla, ikincil
4. Açık görevler (2): bu varlığa bağlı tamamlanmamış işler
5. Zaman akışı: bu varlığın geçtiği olaylar ve günlük paragrafları, yeniden eskiye; her satır ait olduğu güne götürür
6. Serbest notlar (okumada ham wikilink ve blok kimliği gizlenir)
7. Konumda ek olarak harita ve koordinat (4)
8. Düzenleme, "Düzenle" ile açılan ayrı kiptir (sheet); alan ve takma ad düzenleyicileri orada kalır. Ad değiştirme, düzenleme sheet'inin içinden ikinci bir sheet olarak açılır. Kaydedilmemiş alan metni varken sheet kapatılamaz; JournalView ile aynı UnsavedDraftDecision kalıbı "At" / "Vazgeç" sorar (alanlar Kaydet ile yazılır, "Kapat" kaydetmez).

Kişiler ve Konumlar ekranının üstteki tip seçicisi kişi/konuma ek olarak kasanın özel tiplerini gösterir. Sekme adı ve Mac kenar çubuğu değişmez. Özel varlık sayfası tanımın text/date/number/boolean/link alanlarına uygun düzenleyiciler, bilinmeyen alanlar, görevler, günlük zaman akışı ve serbest notları sunar; kişi/konum Graph ve görüşme kartı yalnız yerleşik tiplerde kalır. @ önerileri özel tipleri de içerir; bilinmeyen adın oluşturma menüsünde tanımlı tipler bulunur.

Ayarlar → Varlık tipleri listesinde yerleşik tipler salt okunur, özel tipler oluşturulabilir/düzenlenebilir/silinebilir. Form id, tr/en tekil/çoğul ad, klasör, SF Symbol, alanlar ve isteğe bağlı şablon yolunu içerir. Tip id'si düzenlemede sabittir. Bozuk types.json uyarı verir ve üzerine yazılmaz; dışarıda onarılması gerekir. Silme onayı yalnız tanımı kaldırır, varlık dosyalarını korur.

### Kişi ve konum içgörüleri (6)

Varlık sayfasının üstünde Son görüşme / Son ziyaret kartı bulunur. Hesap mevcut zaman akışıyla aynı kapsamı kullanır: gün dosyalarındaki olaylar ve Journal paragraflarının çözülen bağlantıları. Görev, frontmatter, serbest not ve gelecek tarihli geçişler görüşme sayılmaz. Kart, günlük kaydının görüşme kanıtı olmadığını nötr biçimde belirtir. Son ve ilk geçiş tarihleri, son günün varlığa bağlı metinleri (dokunulabilir bağlantıları korunarak), o gün bütün olay/Journal yazılarında geçen diğer kişi ve konumlar gösterilir; aynı olayda karşılaşma çıkarımı yapılmaz.

Sıklık bugün dahil son 90 takvim gününde (`bugün -89` … bugün) geçilen farklı gün sayısıdır; tekrarlar tek gün sayılır. Ortalama aralık bu penceredeki son ve ilk gün farkının `gün sayısı -1` değerine bölünmesidir; iki günden azsa hesap gösterilmez. İlk geçiş bütün geçmişten alınır.

Kişiler listesinin üstünde katlanabilir Bir süredir görüşmediklerin bölümü vardır (Mac ve telefon). Son geçişten bu yana gün sayısı eşik dahil aşılmışsa listelenir; eski kayıt önce, eşitlerde yol sırası kullanılır. Henüz hiç geçmemişler ayrı gruptadır; gelecekteki kayıt tek başına geçmiş görüşme sayılmaz. Arama filtresi bu bölüme de uygulanır. Satır adı ve geçen tam hafta/gün sayısını nötr gösterir; kişiye açılır. Hızlı girişte an düğmesi Bugün'e geçer ve taslağın sonuna `@Ad ` ekler; mevcut taslak korunur, aynı adlı kişinin yolu sabitlenir. İstek yalnız Bugün girişinde bir kez ve aynı kasada tüketilir; menü çubuğundaki giriş isteği almaz.

Ayarlar'da Kişi hatırlatmaları bölümünden eşik 1–365 gün arasında seçilir; varsayılan 30 gündür ve cihaz tercihi olarak saklanır, kasa alanı değildir. Değişiklik listeye hemen yansır; tarih gece yarısından sonra periyodik yenilenir. Bildirim yoktur.

### Graph ve harita (6)

Mac kenar çubuğunda Graph ve Harita; telefonda Kişiler ve Konumlar listesinin en üstünde iki satır bulunur. Telefonda aynı gezinme yığınında tam sayfa açılır, yeni sekme eklenmez. Varlık sayfasındaki Graph'ta göster o düğümü seçip merkezler.

Graph varsayılan olarak bütün kişi/konumları gösterir; bağlanmamış varlıklar da düğümdür. Gün düğümleri isteğe bağlıdır, bağlantı içeren günler için bir düğüm oluşturulur. Kenar ağırlığı aynı takvim gününün dosyalarında birlikte geçen farklı gün sayısıdır; yinelenen bağlantılar ve aynı tarihli dosyalar ortak günü artırmaz. Gövde/frontmatter ayrımı yapılmaz; çözülen kişi/konum bağlantıları kullanılır, bilinmeyen hedefler dışlanır. Gün–varlık kenarı bir gündür. Tür süzgeci (kişi, konum, gün; çoklu seçim) manşet satırındaki filtre menüsündedir ve varsayılan dışında vurgu rengine döner; dönem (son 30/90/365 gün ya da tümü) manşetin altında "Dönem" menüsüdür; en az ortak gün ağırlığı adımlayıcıyla seçilir. Son N gün bugün dahil `bugün -(N-1)` … bugün aralığıdır; tümü gelecek günleri ve tarihsiz kaynak bağlantılarını da içerir. Düğüm boyutu tümü seçiliyken bütün kasadaki geçiş sayısına, tarih filtresinde seçilen günlerin geçiş sayısına bağlıdır. Eşik kenarları kaldırır, izole düğümleri silmez.

Canvas üzerinde sürükleyerek kaydırma, pinch (Mac'te tekerlek/trackpad kaydırması) ve yakınlaştırma düğmeleri bulunur. Seçili düğümün adı ve komşuları vurgulanır; Sayfayı aç varlık/gün sayfasına gider. Düğüm seç menüsü klavye ve erişilebilirlik için aynı seçimi sunar. Kişi ve konum renkleri Bugün bağlantı alt çizgileriyle aynı belirteçten gelir; tip ayrıca biçimle ayrılır (kişi daire, konum elmas, gün köşeli kare). Açıklama birlikte geçmeyi gerçek karşılaşma diye yorumlamaz. Yerleşim sabit tohumlu, sınırlı adımlı kuvvet hesabıdır; arka planda çalışır, son aşamada daireler arası en az 8 nokta boşluk bırakılır. Kasa/filtre değişiminde eski sonuç uygulanmaz.

Harita geçerli koordinatı olan konumları pin olarak gösterir. Pin boyutu bütün kasadaki çözülen geçiş sayısına bağlıdır; işaretçi tam opak konum rengi ve elmas biçimindedir, seçili olan vurgu çerçevesi taşır; sayı pin içinde görünür, pin dokununca konum sayfası açılır. Konum önerisi yarıçapı pin için gerekli değildir. Koordinat yoksa nötr boş görünüm vardır. Beni göster yalnız mevcut konum izni ve etkin konum tercihiyle tek konum ölçümü ister; yeni izin istemez, son geçerli konumu gösterip merkezler. GPS verisi kasaya yazılmaz. Sayfa adı, "Beni göster" ve arama sabit manşet satırındadır; harita döşemeleri MapKit / sistem kromudur; günlük metni MapKit'e aktarılmaz.

### Hedefler (3)

- Her hedef için satır: halka, ad, sağda değer, altında zincir veya dönem ilerlemesi.
- Satıra girince: kaydırılan manşet, büyük rakam, ısı haritası (başlık döneme göre hafta sayısı söylemez; yoğunluk renge ek biçimle; bugün çerçeveli; gelecek çizilmez; sığmazsa en yeni hafta açık gelir), en uzun seri, geçmiş kayıtlar. Geçmiş günlerin kaydı düzeltilebilir. Tanım alanları kâğıt zeminli satırlardır; satıra dokununca düzenleme sheet'i açılır.
- Kilometre taşı (5): yıllık, miktarsız satır; yapıldı/yapılmadı ve tarih. Dokununca bugün işaretlenir veya bugünkü kayıt kaldırılır; önceki gün tamamlanmış satır salt okunurdur. Zincir/ısı haritası bulunmaz. Yeni hedefte tür seçilir.
- Haftalık hedefte "bu hafta 2/3", yıllık hedefte ilerleme çubuğu.
- Yeni hedef sheet'i Ayarlar ana sayfası gibi düz listede kâğıt zeminde (`SectionHeader`, `.inkListRow()`); kart yok. Hedef miktar etiketli alandır. Sheet ortak kalıptadır: solda "Vazgeç", sağda "Oluştur"; her yazı boyutunda üstte durur.

### Arama (1)

Her ekranın üstündeki simgeden açılır. Sayfa adı serif manşet olarak sayfanın içinde durur. Tek kutu (`ink.well` zemin); sonuçlar türe göre gruplu: kişiler, konumlar, olaylar, görevler, notlar. Not önizlemesi düz metindir (başlık işaretleri ve liste tireleri yok; sıra sayısı gibi içerik korunur). Kod çitinin içi olduğu gibi gösterilir. Aynı zamanda hızlı geçiş işlevi görür.

### Serbest notlar

Telefonda okuma ve basit düzenleme. Aramadan ve bağlantılardan ulaşılır; ayrı sekmesi yoktur. Zengin düzenleme Mac'tedir.

## Mac

- Görevler altında Kanban, Zaman çizelgesi ve proje adları yer alır. Kanban liste sütununu kullanmadan kenar çubuğunun yanına açılır; seçili kart sağ ayrıntı panelinde gösterilir.
- **Kenar çubuğu:** Bugün, Günlük, Görevler, Kişiler, Konumlar, Hedefler, Özetler, Graph, Harita, Notlar. Kenar çubuğu simgeleri sistem vurgu rengini izler; marka vurgu rengi içerikte kalır.
- **Çok sütunlu düzen:** Solda liste, ortada seçili öğe (üç sütun: kenar çubuğu + liste + ayrıntı). Örneğin kişi listesi ve seçili kişinin sayfası yan yana. Sayfa görünümleri en çok 680 pt genişlikte ortalanır. Ana pencerenin en küçük boyutu belirteçlerle sabitlenir.
- **Kanban (5)** tam genişlikte; sürükle bırak ile durum ve proje değişir, tarih kart menüsünden değiştirilir. **Zaman çizelgesi (5)** aynı geniş alanda tarih taşımayı ve uç sürükleyerek uzatma/kısaltmayı destekler. Gün ızgarasına yapışır; çubukta tarih alanları aynı farkla kayar, uç yalnız ilgili alanı değiştirir. Sürükleme başlangıcındaki görev ve kasa doğrulanır. İki tarih mevcut yazıcıyla iki kez yazılır; ikinci yazma ilkinden dönen görev hedefini kullanır. Yazma sırasında geçici çubuk konumu, hata/başarı sonrası dosya yenilemesi vardır; kısmi yazma bildirimi otomatik tekrar göndermez. Ayrıntı sağ panelde açılır.
- **Hızlı giriş penceresi (1):** Sistem genelinde klavye kısayoluyla açılan küçük pencere; telefondaki hızlı giriş kutusuyla aynı davranış. Uygulama öne gelmeden kayıt yapılır. Kısayol Settings → Hızlı giriş sekmesinde ayarlanır.
- **Notlar:** Serbest notlar için düzenleme alanı. (Henüz yok; kenar çubuğu öğesi yer tutucudur.)
- Klavye kısayolları: arama (⌘F) ve hızlı geçiş (⌘K), bugüne git (⌘T). Yeni olay ve yeni görev kısayolları henüz yok.
- **Ayarlar:** Mac'te sistem Settings sahnesinde sekmeler (sıra): Hızlı giriş, Gizlilik, Bildirimler, Takvim ve Konum, Kasa, Tanılama.

## Ayarlar

iPhone'da Bugün manşet satırındaki düğmeden açılan Ayarlar listesi beş bölüme ayrılır; sayfa adı ve alt sayfa adları serif manşet olarak listenin içindedir, satır zemini kâğıttır. Mac'te aynı beş bölüm Settings sekmeleridir; Hızlı giriş kısayolu ilk sekmedir. Hiçbir ayar kaybolmaz; yeni ayar eklenmez.

### Ayarlar — Gizlilik (7)

- **Uygulama kilidi** anahtarı. Açılması bir kez Face ID, Touch ID veya cihaz parolasıyla doğrulanır; iptal edilirse anahtar kapalı kalır. **Şu kadar sonra kilitle** seçimi hemen, 1 dk, 5 dk veya 15 dk olabilir; tercihler cihazda saklanır.
- **Bildirimlerde içeriği gizle** için Bildirimler ayarına bağlantı (yalnız iPhone; Mac'te Bildirimler sekmesi kullanılır). Anahtar ve açıklama Bildirimler'dedir.
- **Kişi hatırlatmaları:** görüşülmeyenler eşiği (1–365 gün, varsayılan 30); cihaz tercihi.

Kilit açıkken uygulama etkinliğini kaybettiğinde içerik opak bir örtüyle gizlenir; açık sayfalar ve taslaklar korunur. iOS'ta süre arka plana geçişten, Mac'te uygulamanın etkinliğini kaybetmesinden başlar. Süre dolmadan dönüşte örtü kalkar; süre dolduysa veya uygulama yeni açıldıysa doğrulama gerekir. İptal/hata durumunda kilit ekranındaki **Tekrar dene** düğmesi kullanılır. Mac menü çubuğu ve klavye kısayoluyla açılan hızlı giriş paneli de aynı kilidi denetler.

Kilitliyken (kilit etkin ve doğrulanmamış) Siri hedef adlarını listelemez; Kısayollar ve bildirimdeki İşaretle eylemi yazmaz. Uygulama kilidi kasayı şifrelemez.

### Ayarlar — Bildirimler (4)

- İzin yalnız kullanıcının izin düğmesiyle istenir; açılışta sistem diyaloğu gösterilmez. Görev, günlük hedef ve günlük yazısı hatırlatmaları ayrı açılıp kapanır; varsayılan saatleri 09:00, 20:00 ve 21:00'dır. Saatler cihazda saklanır. **Bildirimlerde içeriği gizle** (varsayılan kapalı) açıkken afiş, bildirim merkezi ve kilit ekranında görev metni ve hedef adları gösterilmez.
- Bugün dahil yedi gün, yerel takvim saatleriyle planlanır. Sabah tek görev özeti gelir: o gün biten açık görevler, tek görevde metni; aynı özette önceki günlerden açık görev sayısı da yer alır (yalnız bunlar varsa da tek sabah özeti, ayrı gecikme bildirimi yok). Tarihsiz, tamamlanan ve iptal edilen görevler bildirilmez.
- Akşam hedef bildirimi yalnız o gün tamamlanmamış günlük hedefler içindir; haftalık/yıllık hedefler dahil edilmez. Günlük yazısı hatırlatması olay ve günlük yazısı olmayan güne gelir; görev/hedef kaydı tek başına hatırlatmayı kapatmaz.
- Açılış, ön plana dönüş, indeks yenilemesi (2 saniye birleştirme) ve tercih değişimi planı yeniler; arka plana geçiş bekleyen planlamayı tamamlar, bugünün geçmiş saatleri atlanır. Uygulama kapalıyken planlı içerik yeniden hesaplanmaz; yeni değişiklikler sonraki açılış/yenilemede yansır. Yedi günlük pencere de ancak uygulama çalışırken ileri taşınır.
- Görev bildiriminden Görevler'in Bugün grubuna (yoksa önceki günlerden açık gruba), hedef bildiriminden Bugün'e, günlük hatırlatmasından hızlı giriş odaklı Bugün'e gidilir; ön planda da banner gösterilir.
- “Planlananlar” listesinde kimlik, tarih ve başlık; “Şimdi yeniden planla” ile teşhis ve yeniden deneme bulunur. Mac'te Bildirimler ayar sekmesi, iPhone'da Ayarlar listesinden açılır.

### Ayarlar — Takvim ve Konum

- Takvim izni (etkinlikler yalnız gösterilir; takvime ve günlük dosyalarına yazılmaz) ve sistem ayarları bağlantısı.
- Konum önerisi anahtarı, konum izni ve sistem ayarları bağlantısı.
- iOS'ta Konuma girince (bölge izleme) bu bölümün altındadır; macOS'ta gizlidir.

### Ayarlar — Kasa

- Kasa yolu (uzun yollar ortadan kırpılır, seçilip kopyalanabilir), Mac'te Finder'da göster, klasör seç / değiştir, içe aktarma (kasa hazırlığı), izlenmeyen dizin uyarısı, indeksleme ilerlemesi.
- Varlık tipleri listesine bağlantı (yerleşik salt okunur, özel oluşturulabilir/düzenlenebilir/silinebilir).

### Ayarlar — Tanılama

- İndeksi yeniden üret, arama geçmişini temizle.
- İndeks sayıları (dosya, gün, kişi, konum, hedef, not, olay, görev, varlık, bağlantı, çözülmemiş) ve son güncelleme; sayılar tabular.
- Atlanan yollar (sembolik bağlantı / yinelenen yol); uzun yollar kırpılır ve kopyalanabilir.

## Widget'lar (3)

Durum: henüz uygulanmadı (App Group kimliği kararını bekliyor). Tablo hedeflenen kapsamdır.

| Widget | Yer | İçerik |
|---|---|---|
| Hedefler | Ana ekran, Mac | Günün hedefleri; dokununca işaretlenir. Yapılmamışlar vurgulu. |
| Bugün | Ana ekran, Mac | Günün görevleri ve sıradaki etkinlik; görev dokununca tamamlanır. |
| Kilit ekranı | Kilit ekranı | Sıradaki etkinlik ve kalan görev sayısı ya da tek hedefin durumu. |
| Hızlı giriş | Ana ekran, kilit ekranı, Denetim Merkezi | Dokununca uygulama klavyesi açık halde yazma ekranında açılır. |

## Giriş noktaları

Uygulamaya yazmanın tüm yolları aynı hızlı giriş davranışına çıkar:

- Bugün ekranındaki kutu
- Hızlı giriş widget'ı ve kilit ekranı düğmesi (3)
- Mac hızlı giriş penceresi (1)
- Kısayollar ve Siri (4)
- Akşam hatırlatma bildirimi (4)

## Boş durumlar

- **İlk açılış:** Yer imi ve varsayılan kasa yoksa Markdown veri sahipliğini anlatan tek ekran, “Yeni kasa oluştur” ve “Var olan klasörü seç” düğmelerini sunar. Çok adımlı kurulum sihirbazı yoktur. Kasa açılınca boş Bugün ekranında “Gününden bir an yaz; @ ile kişi ekle” ipucu görünür; ilk kişi ve konum yazarken oluşturulur.
- **Kayıtlı kasaya erişilemiyor:** Yer imi var ama klasör açılamıyorsa (veya yer imi bozuksa) sekmelerin yerine durum ekranı; Yeniden dene ve Başka klasör seç. Yerel kasaya sessiz geçiş yok.
- **Boş gün:** Suçlayıcı olmayan kısa bir metin; giriş kutusu hazır.
- **Kasa eşitlenirken:** Eldeki içerik gösterilir, eşitleme durumu küçük bir göstergeyle belirtilir. (iCloud eşitlemesiyle birlikte gelecek; henüz yok.)

## Ayarlar — Konuma girince (4, iOS)

Ayarlar → Takvim ve Konum içinde, Konum bölümünün altında. Açık düğmeyle Her zaman izni istenir; izin olmadan bölge izlenmez. Konum bağlantısı çözülmüş, koordinat ve açık yarıçap alanı olan boolean hedefler için kapalı / bildir / otomatik işaretle seçilir (varsayılan bildir). Bildirim izni ayrıca Bildirimler ayarından verilir. İzlenen bölgeler hedef, konum ve yarıçapla listelenir; 20 sınırını aşan hedef sayısı gösterilir. Hedef dosya yolu sırasındaki ilk 20 açık hedef izlenir.

Giriş bugünün hedef kaydı için günde bir kez işlenir; zaten true olan kayda dokunulmaz. Bildirimde İşaretle / Şimdi değil eylemleri bulunur; İşaretle uygulamayı öne getirmeden dosyaya yazar. Otomatik mod doğrudan işaretleyip kısa bildirim gönderir; uygulama kilitliyken de işaretler. Uygulama kilidi etkinken bildirimde eylem bulunmaz, bildirim yalnız uygulamayı açar. Eski güne ait eylemler, farklı kasa, kapanmış veya değişmiş bölge işlenmez. Yer imi erişimi başarısızsa başka kasaya düşülmez; sonraki girişte yeniden denenir. macOS'ta bu bölüm ve bölge izleme gizlidir.

## Kısayollar ve Siri (4)

Journal ile günlüğe olay ekle, görev ekle, hedefi işaretle ve bugünü aç cümleleri Türkçe/İngilizce App Shortcuts olarak sunulur. Olayın saati verilmezse şimdi; görev tarihi metinden çıkarılır, açık tarih parametresi önceliklidir; varsayımlı (yılsız) tarih Siri/Kısayollar’da onay sorulmadan uygulanmaz. Hedef seçiminde güncel tanımlar listelenir; boolean true, sayısal miktar bugünün toplam kaydı olarak yazılır (artırma değildir). Eksik/erişilemeyen kasada uygulamadan kasayı açma hatası verilir.

Yazma işlemleri uygulamayı öne getirmez, kısa onay metni döndürür. Kesin anmalar mevcut hızlı giriş gibi bağlanır; belirsiz/bilinmeyen @ anmalarında soru açılamadığından @ kaldırılır ve metin düz kalır, yeni varlık oluşturulmaz. Bugünü aç uygulamayı öne getirip Bugün sekmesini/bölümünü seçer; detay, arama ve telefondaki ayarlar kapanır. Ana gezinme değişmez.

### Var olan klasörü seçme

İlk açılışta ve Ayarlar’da aynı klasör seçici kullanılır. Kasa yapısı eksikse bulunan klasörler, Markdown dosya sayısı, gün dosyaları, kişi/konum/hedef sayıları, eksik `type` alanları ve atlanan dosyalar raporlanır. Kökteki ve `daily/` altındaki gün dosyaları bilgi olarak listelenir; taşınmaz. Standart klasör adının yalnız harf farkı olan biçimi (`Journal/` vb.) ayrıca bildirilir; kullanıcı Obsidian’da doğru ada çevirir, uygulama taşımaz veya yeniden adlandırmaz. Eksik klasör ve şablonları oluşturma, eksik kasa ayarını yazma ve kişi/konum türlerini ekleme teklifleri ayrı, varsayılan açık onay kutularıdır. Uygula sonrası oluşturulan/değiştirilen dosya sayıları ve atlanan/hatalı yollar gösterilir; Kasayı aç indeksi hazırlar. Atla dosyalara yazmadan indeksi açar. Desteklenmeyen veya okunamayan kasa sürümünde hazırlama kapalıdır, kasa salt okunur açılır.

İlk indeksleme boyunca toplam dosya sayısıyla ilerleme göstergesi gösterilir. Mevcut indeks API’si dosya başına bildirim üretmediğinden gösterge belirsizdir; bitince gerçek indeks sayıları Ayarlar → Tanılama’da görünür.
