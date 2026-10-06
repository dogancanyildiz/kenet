# Ekranlar

Hangi ekranlar var, her birinde ne görünür ve aralarında nasıl geçilir. Her bölümün yanındaki sayı, o parçanın geldiği aşamadır (bkz. `roadmap.md`).

## Tasarım ilkeleri

1. **Kilit ekranından ilk kelimeye en kısa yol.** Giriş her zaman bir dokunuş uzaklıkta.
2. **Bugün ekranı sade kalır.** Uygulama çok şey yapar ama her gün bakılan ekran kalabalıklaşmaz; ayrıntı diğer sekmelerdedir.
3. **Telefon giriş ve hızlı bakış, Mac düzenleme ve geniş görünümler içindir.**
4. **Kalanı vurgula.** Listeler ve widget'lar yapılmışı değil yapılacak olanı öne çıkarır.
5. **Cezalandırma.** Kaçan gün, geciken görev ya da boş günlük suçlayıcı bir dille gösterilmez.

## iPhone

Alt sekmeler: **Bugün, Günlük, Görevler, Kişiler ve Konumlar, Hedefler.** Arama sekme değildir; her ekranın üstünde simge olarak durur.

### Bugün (1, 2, 3)

Uygulama bu ekranda açılır. Yukarıdan aşağıya:

1. **Manşet ve künye (9):** Günün tarihi sayfa adıdır (gezinme başlığı). Altında tek satırlık künye durur: olayla başlar, kalanla biter ("3 olay · 4 görev ve 2 hedef kaldı"); sıfır olan parça yazılmaz, hiçbir şey yoksa satır yoktur.
2. **Hedefler (3):** Günün (günlük dönemli) hedefleri; bölüm sayacı yalnız bunları sayar (`countedGoalIDs` ile aynı küme). Tek dokunuşluk artı ile işaretlenir veya sayısal değerde bir artar; sayısal hedefte basılı tutunca miktar girilir. Haftalık hedefler Hedefler sekmesindedir. Yapılmamışlar belirgin, yapılmışlar soluk.
3. **Görevler (2):** Devreden görevler, bugünün görevleri ve bugün oluşturulan tarihsiz görevler. Kutuya (veya bağlantısız satıra) dokununca tamamlanır, basılı tutunca düzenlenir. Devreden görevin altında geldiği tarih yazar ("30 Eyl'den"); en çok üçü gösterilir, kalanı "N devreden daha" satırında toplanır ve dokununca açılır. Tamamlanan görev listenin sonuna iner; birden çok tamamlanan tek satıra katlanır ("N görev tamamlandı") ve dokununca açılır.
4. **Takvim (2):** Cihaz takvimindeki bugünkü etkinlikler, salt okunur (sans satır).
5. **Olaylar (1):** Bugün yazılan olaylar, dosyadaki sırayla (uygulama saatli olayı saat sırasındaki yerine yazar). Kenarda saat; kişi ve konum adları dokunulabilir bağlantıdır.
6. **Günlük yazısı (1):** Varsa serbest yazının ilk dört satırı ve "Devamını yaz"; dokununca tam ekran yazma alanı açılır.

Bölüm başlıklarının sağında sayaç durur: hedeflerde yapılan ve toplam (`m/n`), görevlerde kalan, olaylarda sayı. Manşet bloğu, varsayılan yazı boyutunda ilk olay kaydırmadan görünecek kadar dardır. Geçmiş bir günün sayfası aynı düzeni kullanır.

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
- Konum izni Ayarlar → Konum düğmesiyle verilir. Odaklanma ve gönderim en çok dakikada bir tek seferlik GPS isteği başlatır. Kutunun üstündeki en yakın konum çipi dokunulunca sabit `@Konum` anması ekler; kapatma mevcut taslak oturumunda kalıcıdır, kayıt sonrası sıfırlanır. Olay ve görev için aynı davranış kullanılır. Konum önerisi anahtarı ve sistem ayarları bağlantısı kasa ayarlarında bulunur.

### Günlük (1)

- Günlerin ters kronolojik listesi; her günde olay sayısı ve günlük yazısının ilk satırı.
- Üstte Özetler girişi ve takvim ile güne atlama.
- Bir güne girince: o günün olayları, görevleri, hedef kayıtları ve serbest yazısı. Bugün ekranıyla aynı düzen, herhangi bir gün için.
- Geçmiş bir güne olay eklenebilir ve o günün hedef kayıtları düzeltilebilir.

### Özetler (6)

Günlük içinden ve Mac kenar çubuğundan açılır. Hafta (pazartesi–pazar) / takvim ayı seçicisi, önceki/sonraki dönem ve Bu hafta / Bu ay düğmesi vardır. Günlük, Kişiler, Konumlar, Hedefler ve Görevler kartları sayıları ve önceki eş dönem farklarını nötr oklarla gösterir. Kişi/konumların ilk beşi kendi sayfasına bağlanır; sıralama geçiş sayısı azalan, eşitlerde ad ve yol sırasıdır. Boş dönemde “Bu dönemde kayıt yok.” gösterilir; taşınan açık işler yine görülebilir.

- Olay sayısı olay bloklarını; yazılan gün sayısı en az bir olay veya boş olmayan Journal paragrafı/başlığı bulunan farklı gün tarihlerini sayar. Yalnız görev veya hedef kaydı yazılan gün sayılmaz.
- Kişi/konum geçişi, gün dosyalarının gövdesindeki çözülen her bağlantıdır; tekrarlar ayrı sayılır, frontmatter bağlantıları sayılmaz. Kart toplamı ilk beş dışındakileri de içerir. Oluşturulma tarihi kasada bulunmadığından **İlk kez geçenler**, bütün günlük geçmişinde ilk gövde bağlantısı bu döneme düşen varlıkları sayar; dosya oluşturulma sayısı değildir.
- Görev oluşturulma günü kaynak gün dosyasının tarihidir (tekrarlayan görev de kaynak gününe sayılır). Tamamlanan, mevcut durumu tamamlanmış ve `✅` tarihi dönemde olan görevdir. Dönem sonu açık envanteri, o güne kadar kaynak gün dosyasında bulunan ve henüz tamamlanmamış görevlerden üretilir; sonraki tarihli tamamlanma geçmişte açık sayılır. Bitiş tarihi dönem sonundan önceyse geciken, bitiş tarihi yoksa tarihsiz açıktır. İptaller ve tamamlanma tarihi olmayan tamamlanmış görevler envantere katılmaz. Kaynak gün tarihi olmayan görev oluşturulma/açık sayısına girmez; geçerli tamamlanma tarihiyle tamamlanan sayısına girebilir. Dosyalar durum/değişiklik geçmişi tutmadığından yeniden açma, iptal tarihi veya eski bitiş tarihi geri kurulamaz.
- Günlük hedefte dönem katkısı ve hedef × gün sayısı; haftalık hedefte katkı ve hedef × dönemin değdiği pazartesi haftalarının sayısı (ay kenarlarındaki kısmi haftalar dahil) gösterilir. Yıllık hedefte dönem sonundaki yıl başından ilerleme, farkta yalnız seçilen dönemin katkısı gösterilir. Zincir bütün geçmişten dönem sonu itibarıyla hesaplanır. Kilometre taşında yıl içindeki ilk tamamlanma ve tarihi gösterilir; aynı yıl tekrarlanan kayıt katkıyı artırmaz, zincir gösterilmez. Önceki dönem ilerleme farkı iki dönemin katkı farkıdır; zincir farkı dönem sonlarının farkıdır.

### Görevler (2, 5)

Bölümler:

- **Yaklaşan:** Tarihli görevler, güne göre gruplu ajanda listesi.
- **Tarihsiz:** Bitiş tarihi olmayan açık görevler.
- **Tamamlanan:** Son tamamlananlar.
- **Projeler (5):** Etiketlerden türetilen liste ve açık görev sayısı. Proje sayfasında açık görevler bitiş gününe göre gruplu, tarihsizler ayrı; tamamlananlar, görevlerdeki kişi/konumlar ve son etkinlik (gün dosyası veya tamamlanma tarihinin en yenisi) bulunur. Planlanan başlangıç/bitiş tarihi etkinlik sayılmaz.
- **Kanban (5):** Durum, proje veya kişi sütunları. İptal edilenler seçenekle açılır; tamamlanan görevler son 30 takvim günüyle sınırlıdır (bugün dahil, tarihsiz/future tamamlanmalar dışarıda). Kişi/konum/proje filtreleri ortak kullanılır. Birden çok çözülen kişiye bağlı görev her kişi sütununda görünür; kişisiz ve projesiz sütunlar vardır. Kartlar bitiş tarihi (tarihsiz en son), öncelik, metin ve eşitlerde kimlik sırasındadır; dosya sırası değişmez. Bilinmeyen açık durumlar Yapılacak sütununda korunur. Telefonda yatay kaydırmalı sütunlar, kart menüsünden taşıma ve ayrıntı sheet'i; Mac'te sürükle bırak ve sağ ayrıntı paneli. Durum/proje taşıması mevcut dosya yazıcılarını kullanır; kişi sütunları bağlantı metnini değiştirmez ve taşıma kabul etmez. Tarih kart menüsündeki seçiciden değişir.
- **Zaman çizelgesi (5):** Ortak kişi/konum/proje filtreleriyle tarihli görevler; Mac'te proje (varsayılan), kişi veya gruplamasız satırlar, açılır/kapanır gruplar ve hafta/ay/çeyrek ölçeği. Çok kişili görev kişi gruplarında tekrarlanır. Başlangıç-bitiş çubuk, yalnız bitiş tek günlük elmas, yalnız başlangıç bugüne kadar açık uçlu (gelecekteki başlangıç tek noktadan başlar); tarihsizler ayrı listededir. Tamamlananlar soluk, iptaller gizli, geciken bitişler vurguludur. Dışarıda yazılmış ters aralık kaynakta korunur, uyarıyla gösterilir; yeni değişiklikler ters aralık üretmez. Varsayılan aralık bugün -4 hafta / +12 hafta; eksen ±365 gün, Bugün düğmesi ve hafta sonu gölgesi vardır. Telefonda hafta/ay başlıkları ve küçük çubuklu dikey liste, dönem düğmeleri ve tarih menüsü bulunur; sürükleme yoktur.

Filtre: kişi, konum, proje. Aynı gündeki görevler yüksek, orta, normal, düşük öncelik sırasındadır; eşitlerde dosya/satır sırası korunur. Görev satırında öncelik ve tekrar rozeti vardır; düzenleme menüsünden Tekrar ve Öncelik seçilir. Tekrar seçicisinde aralık, haftanın günü ve tamamlanma gününden hesaplama bulunur.

### Kişiler ve Konumlar (1)

- Üstte kişi / konum geçişi. Liste ada göre ya da son geçtiği tarihe göre sıralanır.
- Aynı adlı varlıklarda adın altında ayırt edici görünür.

**Varlık sayfası:**

1. Ad, ayırt edici, takma adlar
2. Şablon alanları ve kullanıcının eklediği alanlar; yerinde düzenlenir, "alan ekle" ile yeni alan eklenir
3. Açık görevler (2): bu varlığa bağlı tamamlanmamış işler
4. Zaman akışı: bu varlığın geçtiği olaylar ve günlük paragrafları, yeniden eskiye; her satır ait olduğu güne götürür
5. Serbest notlar
6. Konumda ek olarak harita ve koordinat (4)

Kişiler ve Konumlar ekranının üstteki tip seçicisi kişi/konuma ek olarak kasanın özel tiplerini gösterir. Sekme adı ve Mac kenar çubuğu değişmez. Özel varlık sayfası tanımın text/date/number/boolean/link alanlarına uygun düzenleyiciler, bilinmeyen alanlar, görevler, günlük zaman akışı ve serbest notları sunar; kişi/konum Graph ve görüşme kartı yalnız yerleşik tiplerde kalır. @ önerileri özel tipleri de içerir; bilinmeyen adın oluşturma menüsünde tanımlı tipler bulunur.

Ayarlar → Varlık tipleri listesinde yerleşik tipler salt okunur, özel tipler oluşturulabilir/düzenlenebilir/silinebilir. Form id, tr/en tekil/çoğul ad, klasör, SF Symbol, alanlar ve isteğe bağlı şablon yolunu içerir. Tip id'si düzenlemede sabittir. Bozuk types.json uyarı verir ve üzerine yazılmaz; dışarıda onarılması gerekir. Silme onayı yalnız tanımı kaldırır, varlık dosyalarını korur.

### Kişi ve konum içgörüleri (6)

Varlık sayfasının üstünde Son görüşme / Son ziyaret kartı bulunur. Hesap mevcut zaman akışıyla aynı kapsamı kullanır: gün dosyalarındaki olaylar ve Journal paragraflarının çözülen bağlantıları. Görev, frontmatter, serbest not ve gelecek tarihli geçişler görüşme sayılmaz. Kart, günlük kaydının görüşme kanıtı olmadığını nötr biçimde belirtir. Son ve ilk geçiş tarihleri, son günün varlığa bağlı metinleri (dokunulabilir bağlantıları korunarak), o gün bütün olay/Journal yazılarında geçen diğer kişi ve konumlar gösterilir; aynı olayda karşılaşma çıkarımı yapılmaz.

Sıklık bugün dahil son 90 takvim gününde (`bugün -89` … bugün) geçilen farklı gün sayısıdır; tekrarlar tek gün sayılır. Ortalama aralık bu penceredeki son ve ilk gün farkının `gün sayısı -1` değerine bölünmesidir; iki günden azsa hesap gösterilmez. İlk geçiş bütün geçmişten alınır.

Kişiler listesinin üstünde katlanabilir Bir süredir görüşmediklerin bölümü vardır (Mac ve telefon). Son geçişten bu yana gün sayısı eşik dahil aşılmışsa listelenir; eski kayıt önce, eşitlerde yol sırası kullanılır. Henüz hiç geçmemişler ayrı gruptadır; gelecekteki kayıt tek başına geçmiş görüşme sayılmaz. Arama filtresi bu bölüme de uygulanır. Satır adı ve geçen tam hafta/gün sayısını nötr gösterir; kişiye açılır. Hızlı girişte an düğmesi Bugün'e geçer ve taslağın sonuna `@Ad ` ekler; mevcut taslak korunur, aynı adlı kişinin yolu sabitlenir. İstek yalnız Bugün girişinde bir kez ve aynı kasada tüketilir; menü çubuğundaki giriş isteği almaz.

Ayarlar'da Kişi hatırlatmaları bölümünden eşik 1–365 gün arasında seçilir; varsayılan 30 gündür ve cihaz tercihi olarak saklanır, kasa alanı değildir. Değişiklik listeye hemen yansır; tarih gece yarısından sonra periyodik yenilenir. Bildirim yoktur.

### Graph ve harita (6)

Mac kenar çubuğunda Graph ve Harita; telefonda Kişiler ve Konumlar araç çubuğunda iki giriş bulunur. Telefonda aynı gezinme yığınında tam sayfa açılır, yeni sekme eklenmez. Varlık sayfasındaki Graph'ta göster o düğümü seçip merkezler.

Graph varsayılan olarak bütün kişi/konumları gösterir; bağlanmamış varlıklar da düğümdür. Gün düğümleri isteğe bağlıdır, bağlantı içeren günler için bir düğüm oluşturulur. Kenar ağırlığı aynı takvim gününün dosyalarında birlikte geçen farklı gün sayısıdır; yinelenen bağlantılar ve aynı tarihli dosyalar ortak günü artırmaz. Gövde/frontmatter ayrımı yapılmaz; çözülen kişi/konum bağlantıları kullanılır, bilinmeyen hedefler dışlanır. Gün–varlık kenarı bir gündür. Filtreler kişi/konum/gün, son 30/90/365 gün veya tümü ve en az ortak gün ağırlığıdır. Son N gün bugün dahil `bugün -(N-1)` … bugün aralığıdır; tümü gelecek günleri ve tarihsiz kaynak bağlantılarını da içerir. Düğüm boyutu tümü seçiliyken bütün kasadaki geçiş sayısına, tarih filtresinde seçilen günlerin geçiş sayısına bağlıdır. Eşik kenarları kaldırır, izole düğümleri silmez.

Canvas üzerinde sürükleyerek kaydırma, pinch (Mac'te tekerlek/trackpad kaydırması) ve yakınlaştırma düğmeleri bulunur. Seçili düğümün adı ve komşuları vurgulanır; Sayfayı aç varlık/gün sayfasına gider. Düğüm seç menüsü klavye ve erişilebilirlik için aynı seçimi sunar. Renkler kişi mavi, konum yeşil, gün gri; açıklama birlikte geçmeyi gerçek karşılaşma diye yorumlamaz. Yerleşim sabit tohumlu, sınırlı adımlı kuvvet hesabıdır; arka planda çalışır, son aşamada daireler arası en az 8 nokta boşluk bırakılır. Kasa/filtre değişiminde eski sonuç uygulanmaz.

Harita geçerli koordinatı olan konumları pin olarak gösterir. Pin boyutu ve renk yoğunluğu bütün kasadaki çözülen geçiş sayısına bağlıdır; sayı pin içinde görünür, pin dokununca konum sayfası açılır. Konum önerisi yarıçapı pin için gerekli değildir. Koordinat yoksa nötr boş görünüm vardır. Beni göster yalnız mevcut konum izni ve etkin konum tercihiyle tek konum ölçümü ister; yeni izin istemez, son geçerli konumu gösterip merkezler. GPS verisi kasaya yazılmaz. Harita döşemeleri MapKit tarafından sağlanır; günlük metni MapKit'e aktarılmaz.

### Hedefler (3)

- Her hedef için kart: ad, dönem, güncel zincir ya da dönem ilerlemesi.
- Karta girince: ısı haritası, en uzun seri, geçmiş kayıtlar. Geçmiş günlerin kaydı düzeltilebilir.
- Kilometre taşı (5): yıllık, miktarsız kart; yapıldı/yapılmadı ve tarih. Dokununca bugün işaretlenir veya bugünkü kayıt kaldırılır; önceki gün tamamlanmış kart salt okunurdur. Zincir/ısı haritası bulunmaz. Yeni hedefte tür seçilir.
- Haftalık hedefte "bu hafta 2/3", yıllık hedefte ilerleme çubuğu.

### Arama (1)

Her ekranın üstündeki simgeden açılır. Tek kutu; sonuçlar türe göre gruplu: kişiler, konumlar, olaylar, görevler, notlar. Aynı zamanda hızlı geçiş işlevi görür.

### Serbest notlar

Telefonda okuma ve basit düzenleme. Aramadan ve bağlantılardan ulaşılır; ayrı sekmesi yoktur. Zengin düzenleme Mac'tedir.

## Mac

- Görevler altında Kanban, Zaman çizelgesi ve proje adları yer alır. Kanban liste sütununu kullanmadan kenar çubuğunun yanına açılır; seçili kart sağ ayrıntı panelinde gösterilir.
- **Kenar çubuğu:** Bugün, Günlük, Görevler, Kişiler, Konumlar, Hedefler, Özetler, Graph, Harita, Notlar.
- **Çok sütunlu düzen:** Solda liste, ortada seçili öğe. Örneğin kişi listesi ve seçili kişinin sayfası yan yana.
- **Kanban (5)** tam genişlikte; sürükle bırak ile durum ve proje değişir, tarih kart menüsünden değiştirilir. **Zaman çizelgesi (5)** aynı geniş alanda tarih taşımayı ve uç sürükleyerek uzatma/kısaltmayı destekler. Gün ızgarasına yapışır; çubukta tarih alanları aynı farkla kayar, uç yalnız ilgili alanı değiştirir. Sürükleme başlangıcındaki görev ve kasa doğrulanır. İki tarih mevcut yazıcıyla iki kez yazılır; ikinci yazma ilkinden dönen görev hedefini kullanır. Yazma sırasında geçici çubuk konumu, hata/başarı sonrası dosya yenilemesi vardır; kısmi yazma bildirimi otomatik tekrar göndermez. Ayrıntı sağ panelde açılır.
- **Hızlı giriş penceresi (1):** Sistem genelinde klavye kısayoluyla açılan küçük pencere; telefondaki hızlı giriş kutusuyla aynı davranış. Uygulama öne gelmeden kayıt yapılır.
- **Notlar:** Serbest notlar için düzenleme alanı. (Henüz yok; kenar çubuğu öğesi yer tutucudur.)
- Klavye kısayolları: arama (⌘F) ve hızlı geçiş (⌘K), bugüne git (⌘T). Yeni olay ve yeni görev kısayolları henüz yok.

## Ayarlar — Bildirimler (4)

- İzin yalnız kullanıcının izin düğmesiyle istenir; açılışta sistem diyaloğu gösterilmez. Görev, günlük hedef ve günlük yazısı hatırlatmaları ayrı açılıp kapanır; varsayılan saatleri 09:00, 20:00 ve 21:00'dır. Saatler cihazda saklanır. **Bildirimlerde içeriği gizle** (varsayılan kapalı) açıkken afiş, bildirim merkezi ve kilit ekranında görev metni ve hedef adları gösterilmez.
- Bugün dahil yedi gün, yerel takvim saatleriyle planlanır. Sabah tek görev özeti gelir: o gün biten açık görevler, tek görevde metni; aynı özette önceki günlerden açık görev sayısı da yer alır (yalnız bunlar varsa da tek sabah özeti, ayrı gecikme bildirimi yok). Tarihsiz, tamamlanan ve iptal edilen görevler bildirilmez.
- Akşam hedef bildirimi yalnız o gün tamamlanmamış günlük hedefler içindir; haftalık/yıllık hedefler dahil edilmez. Günlük yazısı hatırlatması olay ve günlük yazısı olmayan güne gelir; görev/hedef kaydı tek başına hatırlatmayı kapatmaz.
- Açılış, ön plana dönüş, indeks yenilemesi (2 saniye birleştirme) ve tercih değişimi planı yeniler; arka plana geçiş bekleyen planlamayı tamamlar, bugünün geçmiş saatleri atlanır. Uygulama kapalıyken planlı içerik yeniden hesaplanmaz; yeni değişiklikler sonraki açılış/yenilemede yansır. Yedi günlük pencere de ancak uygulama çalışırken ileri taşınır.
- Görev bildiriminden Görevler'in Bugün grubuna (yoksa önceki günlerden açık gruba), hedef bildiriminden Bugün'e, günlük hatırlatmasından hızlı giriş odaklı Bugün'e gidilir; ön planda da banner gösterilir.
- “Planlananlar” listesinde kimlik, tarih ve başlık; “Şimdi yeniden planla” ile teşhis ve yeniden deneme bulunur. Mac'te Bildirimler ayar sekmesi, iPhone'da Ayarlar içinden açılır.

## Ayarlar — Gizlilik (7)

Kasa ayarlarında **Uygulama kilidi** anahtarı bulunur. Açılması bir kez Face ID, Touch ID veya cihaz parolasıyla doğrulanır; iptal edilirse anahtar kapalı kalır. **Şu kadar sonra kilitle** seçimi hemen, 1 dk, 5 dk veya 15 dk olabilir; tercihler cihazda saklanır.

Kilit açıkken uygulama etkinliğini kaybettiğinde içerik opak bir örtüyle gizlenir; açık sayfalar ve taslaklar korunur. iOS'ta süre arka plana geçişten, Mac'te uygulamanın etkinliğini kaybetmesinden başlar. Süre dolmadan dönüşte örtü kalkar; süre dolduysa veya uygulama yeni açıldıysa doğrulama gerekir. İptal/hata durumunda kilit ekranındaki **Tekrar dene** düğmesi kullanılır. Mac menü çubuğu ve klavye kısayoluyla açılan hızlı giriş paneli de aynı kilidi denetler.

Kilitliyken (kilit etkin ve doğrulanmamış) Siri hedef adlarını listelemez; Kısayollar ve bildirimdeki İşaretle eylemi yazmaz. Bildirim içeriği gizleme seçeneği Bildirimler ayarındadır; uygulama kilidi kasayı şifrelemez.

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

Konum bölümünde açık düğmeyle Her zaman izni istenir; izin olmadan bölge izlenmez. Konum bağlantısı çözülmüş, koordinat ve açık yarıçap alanı olan boolean hedefler için kapalı / bildir / otomatik işaretle seçilir (varsayılan bildir). Bildirim izni ayrıca Bildirimler ayarından verilir. İzlenen bölgeler hedef, konum ve yarıçapla listelenir; 20 sınırını aşan hedef sayısı gösterilir. Hedef dosya yolu sırasındaki ilk 20 açık hedef izlenir.

Giriş bugünün hedef kaydı için günde bir kez işlenir; zaten true olan kayda dokunulmaz. Bildirimde İşaretle / Şimdi değil eylemleri bulunur; İşaretle uygulamayı öne getirmeden dosyaya yazar. Otomatik mod doğrudan işaretleyip kısa bildirim gönderir; uygulama kilitliyken de işaretler. Uygulama kilidi etkinken bildirimde eylem bulunmaz, bildirim yalnız uygulamayı açar. Eski güne ait eylemler, farklı kasa, kapanmış veya değişmiş bölge işlenmez. Yer imi erişimi başarısızsa başka kasaya düşülmez; sonraki girişte yeniden denenir. macOS'ta bu bölüm ve bölge izleme gizlidir.

## Kısayollar ve Siri (4)

Journal ile günlüğe olay ekle, görev ekle, hedefi işaretle ve bugünü aç cümleleri Türkçe/İngilizce App Shortcuts olarak sunulur. Olayın saati verilmezse şimdi; görev tarihi metinden çıkarılır, açık tarih parametresi önceliklidir; varsayımlı (yılsız) tarih Siri/Kısayollar’da onay sorulmadan uygulanmaz. Hedef seçiminde güncel tanımlar listelenir; boolean true, sayısal miktar bugünün toplam kaydı olarak yazılır (artırma değildir). Eksik/erişilemeyen kasada uygulamadan kasayı açma hatası verilir.

Yazma işlemleri uygulamayı öne getirmez, kısa onay metni döndürür. Kesin anmalar mevcut hızlı giriş gibi bağlanır; belirsiz/bilinmeyen @ anmalarında soru açılamadığından @ kaldırılır ve metin düz kalır, yeni varlık oluşturulmaz. Bugünü aç uygulamayı öne getirip Bugün sekmesini/bölümünü seçer; detay, arama ve telefondaki ayarlar kapanır. Ana gezinme değişmez.

### Var olan klasörü seçme

İlk açılışta ve Ayarlar’da aynı klasör seçici kullanılır. Kasa yapısı eksikse bulunan klasörler, Markdown dosya sayısı, gün dosyaları, kişi/konum/hedef sayıları, eksik `type` alanları ve atlanan dosyalar raporlanır. Kökteki ve `daily/` altındaki gün dosyaları bilgi olarak listelenir; taşınmaz. Standart klasör adının yalnız harf farkı olan biçimi (`Journal/` vb.) ayrıca bildirilir; kullanıcı Obsidian’da doğru ada çevirir, uygulama taşımaz veya yeniden adlandırmaz. Eksik klasör ve şablonları oluşturma, eksik kasa ayarını yazma ve kişi/konum türlerini ekleme teklifleri ayrı, varsayılan açık onay kutularıdır. Uygula sonrası oluşturulan/değiştirilen dosya sayıları ve atlanan/hatalı yollar gösterilir; Kasayı aç indeksi hazırlar. Atla dosyalara yazmadan indeksi açar. Desteklenmeyen veya okunamayan kasa sürümünde hazırlama kapalıdır, kasa salt okunur açılır.

İlk indeksleme boyunca toplam dosya sayısıyla ilerleme göstergesi gösterilir. Mevcut indeks API’si dosya başına bildirim üretmediğinden gösterge belirsizdir; bitince gerçek indeks sayıları Ayarlar’da görünür.
