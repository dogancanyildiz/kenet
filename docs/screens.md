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

1. **Hedefler şeridi (3):** Günün hedefleri, tek dokunuşla işaretlenir. Sayısal hedefte dokununca miktar girilir. Yapılmamışlar belirgin, yapılmışlar soluk.
2. **Görevler (2):** Geciken görevler, bugünün görevleri ve bugün oluşturulan tarihsiz görevler. Dokununca tamamlanır, basılı tutunca düzenlenir.
3. **Takvim (2):** Cihaz takvimindeki bugünkü etkinlikler, salt okunur.
4. **Olaylar (1):** Bugün yazılan olaylar, dosyadaki sırayla (uygulama saatli olayı saat sırasındaki yerine yazar). Kişi ve konum adları dokunulabilir bağlantıdır.
5. **Günlük yazısı (1):** Varsa serbest yazının ilk satırları; dokununca tam ekran yazma alanı açılır.

En altta sabit **hızlı giriş kutusu**.

### Hızlı giriş (1, 2)

- Tek metin kutusu. Yanında **olay / görev** geçiş düğmesi; varsayılan olay.
- `@` yazınca kişi ve konum önerileri açılır. `@` kullanılmasa da bilinen adlar yazarken tanınır ve vurgulanır.
- Birden fazla aday varsa en olası olan önerilir; uygulama emin değilse seçim ister.
- Tanınmayan bir ad `@` ile yazıldıysa "kişi olarak ekle" ya da "konum olarak ekle" seçeneği çıkar. Aynı adda varlık varsa kısa bir ayırt edici sorulur.
- Görev modunda tarih cümleden çıkarılır ("yarın Ahmet'i ara") ve kutunun üstünde onay için gösterilir; yanlışsa dokunup düzeltilir.
- Olay varsayılan olarak şu anki saatle kaydedilir; saat kaldırılabilir ya da değiştirilebilir.
- Gönderince kutu boşalır, klavye açık kalır; art arda giriş yapılabilir.
- Konum izni Ayarlar → Konum düğmesiyle verilir. Odaklanma ve gönderim en çok dakikada bir tek seferlik GPS isteği başlatır. Kutunun üstündeki en yakın konum çipi dokunulunca sabit `@Konum` anması ekler; kapatma mevcut taslak oturumunda kalıcıdır, kayıt sonrası sıfırlanır. Olay ve görev için aynı davranış kullanılır. Konum önerisi anahtarı ve sistem ayarları bağlantısı kasa ayarlarında bulunur.

### Günlük (1)

- Günlerin ters kronolojik listesi; her günde olay sayısı ve günlük yazısının ilk satırı.
- Üstte takvim ile güne atlama.
- Bir güne girince: o günün olayları, görevleri, hedef kayıtları ve serbest yazısı. Bugün ekranıyla aynı düzen, herhangi bir gün için.
- Geçmiş bir güne olay eklenebilir ve o günün hedef kayıtları düzeltilebilir.

### Görevler (2, 5)

Bölümler:

- **Yaklaşan:** Tarihli görevler, güne göre gruplu ajanda listesi.
- **Tarihsiz:** Bitiş tarihi olmayan açık görevler.
- **Tamamlanan:** Son tamamlananlar.
- **Kanban ve zaman çizelgesi (5):** Telefonda sade sürüm; asıl kullanım Mac'te.

Filtre: kişi, konum, proje.

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

### Hedefler (3)

- Her hedef için kart: ad, dönem, güncel zincir ya da dönem ilerlemesi.
- Karta girince: ısı haritası, en uzun seri, geçmiş kayıtlar. Geçmiş günlerin kaydı düzeltilebilir.
- Haftalık hedefte "bu hafta 2/3", yıllık hedefte ilerleme çubuğu.

### Arama (1)

Her ekranın üstündeki simgeden açılır. Tek kutu; sonuçlar türe göre gruplu: kişiler, konumlar, olaylar, görevler, notlar. Aynı zamanda hızlı geçiş işlevi görür.

### Serbest notlar

Telefonda okuma ve basit düzenleme. Aramadan ve bağlantılardan ulaşılır; ayrı sekmesi yoktur. Zengin düzenleme Mac'tedir.

## Mac

- **Kenar çubuğu:** Bugün, Günlük, Görevler, Kişiler, Konumlar, Hedefler, Notlar.
- **Çok sütunlu düzen:** Solda liste, ortada seçili öğe. Örneğin kişi listesi ve seçili kişinin sayfası yan yana.
- **Kanban ve zaman çizelgesi (5)** tam genişlikte; sürükle bırak ile durum ve tarih değişir.
- **Hızlı giriş penceresi (1):** Sistem genelinde klavye kısayoluyla açılan küçük pencere; telefondaki hızlı giriş kutusuyla aynı davranış. Uygulama öne gelmeden kayıt yapılır.
- **Notlar:** Serbest notlar için düzenleme alanı.
- Klavye kısayolları: arama ve hızlı geçiş, yeni olay, yeni görev, bugüne git.

## Ayarlar — Bildirimler (4)

- İzin yalnız kullanıcının izin düğmesiyle istenir; açılışta sistem diyaloğu gösterilmez. Görev, günlük hedef ve günlük yazısı hatırlatmaları ayrı açılıp kapanır; varsayılan saatleri 09:00, 20:00 ve 21:00'dır. Saatler cihazda saklanır.
- Bugün dahil yedi gün, yerel takvim saatleriyle planlanır. Sabah tek görev özeti gelir: o gün biten açık görevler, tek görevde metni; aynı özette önceki günlerden açık görev sayısı da yer alır (yalnız bunlar varsa da tek sabah özeti, ayrı gecikme bildirimi yok). Tarihsiz, tamamlanan ve iptal edilen görevler bildirilmez.
- Akşam hedef bildirimi yalnız o gün tamamlanmamış günlük hedefler içindir; haftalık/yıllık hedefler dahil edilmez. Günlük yazısı hatırlatması olay ve günlük yazısı olmayan güne gelir; görev/hedef kaydı tek başına hatırlatmayı kapatmaz.
- Açılış, ön plana dönüş, indeks yenilemesi (2 saniye birleştirme) ve tercih değişimi planı yeniler; arka plana geçiş bekleyen planlamayı tamamlar, bugünün geçmiş saatleri atlanır. Uygulama kapalıyken planlı içerik yeniden hesaplanmaz; yeni değişiklikler sonraki açılış/yenilemede yansır. Yedi günlük pencere de ancak uygulama çalışırken ileri taşınır.
- Görev bildiriminden Görevler'in Bugün grubuna (yoksa önceki günlerden açık gruba), hedef bildiriminden Bugün'e, günlük hatırlatmasından hızlı giriş odaklı Bugün'e gidilir; ön planda da banner gösterilir.
- “Planlananlar” listesinde kimlik, tarih ve başlık; “Şimdi yeniden planla” ile teşhis ve yeniden deneme bulunur. Mac'te Bildirimler ayar sekmesi, iPhone'da Ayarlar içinden açılır.

## Widget'lar (3)

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

- **İlk açılış:** Boş Bugün ekranı ve giriş kutusunda örnek bir ipucu. Kurulum sihirbazı yoktur; ilk kişi ve konum yazarken oluşturulur.
- **Boş gün:** Suçlayıcı olmayan kısa bir metin; giriş kutusu hazır.
- **Kasa eşitlenirken:** Eldeki içerik gösterilir, eşitleme durumu küçük bir göstergeyle belirtilir.
