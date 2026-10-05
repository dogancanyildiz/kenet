# Kasa formatı

**Sürüm:** 0.3 (taslak)

Bu belge platformlar arası sözleşmedir. Uygulamanın her sürümü ve ileride yazılacak her istemci bu belgeye uyar. Format değişikliği önce burada yapılır.

## Genel kurallar

- Uygulamanın oluşturduğu dosyalar UTF-8'dir (BOM'suz), satır sonu LF'tir.
- Satır sonu LF, CRLF ya da ardından LF gelmeyen tek CR'dir (Obsidian ve CommonMark da böyle sayar). Okurken üçü de, baştaki BOM ve satır sonuyla bitmeyen son satır kabul edilir ve aynen korunur.
- Uygulama var olan bir dosyaya satır eklerken o dosyadaki ilk satır sonunun biçimini kullanır. Son satır yeni satırla bitmiyorsa ardına satır eklenmeden önce sonlandırılır. Dosyada hiç satır sonu yoksa LF kullanılır.
- Baştaki BOM dosyanın özelliğidir ve her zaman en başta kalır; dosyanın başına içerik (örneğin yeni frontmatter) eklendiğinde de. Baş dışındaki BOM baytları sıradan içeriktir.
- UTF-8 olarak çözülemeyen dosya salt okunurdur: uygulama içine yazmaz. Çözülemeyen, Unicode'a göre iyi biçimli olmayan bayt dizisi demektir (aşırı uzun kodlama, vekil kod noktası, yarım dizi); NUL ve U+FFFD geçerlidir. Gösterirken geçerli satırlar olduğu gibi, geçersiz bayt dizileri U+FFFD olarak gösterilir.
- Sözdizimi Obsidian uyumludur: YAML frontmatter, `[[wikilink]]`, `#etiket`, blok kimliği, Obsidian Tasks görev biçimi.
- Kasa bugün uygulamanın yerel klasöründe ya da kullanıcının seçtiği klasörde durur; uygulamanın kendi iCloud klasörü planlanmıştır (henüz yok). Mac'te Obsidian ile kasa olarak açılabilir.

## Dil

- **Dosyadaki yapı İngilizce ve sabittir:** klasör adları, frontmatter anahtarları, `type` değerleri ve gün dosyasındaki bölüm başlıkları. Kullanıcının dili ne olursa olsun aynıdır; böylece kasa her dilde ve her istemcide aynı şekilde okunur.
- **Arayüz kullanıcının dilindedir.** Kullanıcı `people/` klasörünü "Kişiler", `aliases` alanını "Takma adlar" olarak görür.
- **İçerik kullanıcınındır:** varlık adları, notlar, kullanıcının eklediği serbest alanlar ve şablon alan adları istediği dilde olur.

## Birlikte yaşama kuralları

1. **Tanımadığına dokunma.** Uygulama bir dosyada yalnızca kullanıcının işleminin hedeflediği satırı ya da alanı değiştirir. Dosyanın geri kalanı bayt düzeyinde korunur.
   - Hedef, uygulamanın üretmediği bir satır da olabilir (Obsidian'da yazılmış bir görevi tamamlamak gibi); o zaman da yalnızca o satır değişir.
   - Birden çok dosyaya dokunan işlemler bellidir: varlık adını değiştirme (bağlantılar güncellenir) ve çakışma birleştirme.
   - Uygulama dışında yazılmış metin kendiliğinden yeniden yazılmaz: biçimi düzeltilmez, içindeki adlar sonradan bağlantıya çevrilmez.
2. **Tanımadığını gösterebil.** Beklenmeyen dosya ya da sözdizimi hata üretmez; düz not olarak gösterilir.
3. **Dosyada olmayan bilgi tutma.** Kasa tek başına tüm veriyi geri getirebilmelidir.

### Var olan kasayı açma ve hazırlama

İçe aktarma kaynak klasörde çalışır; dosyaları kopyalamaz veya taşımaz. Eksik yapı için rapor ve ayrı onay seçenekleri gösterilir: standart klasörler/eksik person-place şablonları, yalnız eksik `.app/vault.json`, `people/` ve `places/` altındaki `type` alanı bulunmayan okunabilir Markdown dosyalarına ilgili `type` eklenmesi. Mevcut `type` değeri, şablon, ayar, bilinmeyen alanlar ve gövde korunur. Çözülemeyen frontmatter/UTF-8 ve sembolik bağlantılar değiştirilmez, raporlanır. Kullanıcı Atla derse yalnız indekslenir; `.obsidian/` ve diğer dosyalar korunur.

`journal/YYYY-MM-DD.md` tanınan gün yoludur. Kökte veya `daily/` altında aynı tarih adlı dosyalar raporda yalnız bilgi olarak gösterilir; kullanıcı isterse Obsidian'da kendisi düzenler. Uygulama bu dosyaları taşımaz, farklı yol için gün kimliği kuralını değiştirmez. Hazırlama format sürümünü yükseltmez ve var olan vault.json'u yeniden yazmaz; desteklenmeyen/okunamayan sürüm dosyası için hazırlama yazıları sunulmaz.

## Klasör yapısı

```
Vault/
  journal/       Gün dosyaları (YYYY-MM-DD.md)
  people/        Kişi dosyaları
  places/        Konum dosyaları
  goals/         Hedef tanımları
  notes/         Serbest notlar
  templates/     Varlık şablonları (person.md, place.md)
  conflicts/     Çakışma kopyaları (bkz. Senkronizasyon çakışması)
  .app/          Ayarlar ve görünüm tercihleri (JSON)
```

- Bir dosyanın türünü klasör değil frontmatter'daki `type` belirler. Klasörler, uygulamanın yeni dosyayı nereye koyacağını söyler. Tek istisna gün dosyalarıdır: kimlikleri yollarıdır (bkz. Gün dosyası).
- `type` alanı olmayan ya da tanınmayan bir `type` taşıyan dosya düz nottur.
- Yalnızca `.md` uzantılı dosyalar okunur. Diğer dosyalar (görsel, PDF) yok sayılır ve korunur.
- Şunlar taranmaz; içlerindeki dosyalar varlık sayılmaz ve indekslenmez: adı nokta ile başlayan klasörler (`.app/`, `.obsidian/`, `.trash/`), (kökteki) `templates/` ve `conflicts/`.
- Kullanıcının açtığı diğer klasörler ve alt klasörler taranır.
- Sembolik bağlantılar izlenmez. Adları aynı NFC biçimine dönüşen iki dosyadan bayt sırasında önce gelen indekslenir; diğeri bildirilir.
- İndeks veritabanı kasanın içinde durmaz.

## Adlar ve karşılaştırma

- Dosya adları ve adlarla yapılan tüm karşılaştırmalar Unicode NFC'ye normalleştirilir (macOS ve iCloud dosya adlarını farklı biçimde döndürebilir; Türkçe karakterlerde eşleşme hatasına yol açar). Bu kural yalnızca dosya ve varlık adlarını kapsar; satırlar ve frontmatter değerleri bayt düzeyinde, normalleştirme yapılmadan karşılaştırılır.
- Karşılaştırma büyük/küçük harfe duyarsızdır ve cihazın dilinden bağımsızdır: iki ad NFC'ye çevrildikten sonra Unicode'un varsayılan (yerelden bağımsız) küçük harf eşlemesiyle karşılaştırılır. Mac dosya sistemi ve Obsidian büyük/küçük harfe duyarsız, iPhone dosya sistemi duyarlıdır; bu yüzden kural dosya sistemine bırakılmaz.
- Türkçeye özel eşleme uygulanmaz: `I` ile `i` aynı, `İ` ile `i` ve `I` ile `ı` farklı harflerdir. Örneğin `Işık` ile `işık` aynı ad, `ışık` ise ayrı bir ad sayılır. Uygulamanın yazdığı bağlantılar dosya adını birebir taşıdığı için bu kural yalnızca elle yazılan bağlantıları etkiler.
- Dosya adları (uzantısız) kasa genelinde benzersizdir. Uygulama kendi oluşturduğu dosyalarda bunu sağlar.
- Aynı ad dışarıdan iki dosyaya verilmişse bağlantı, kasa köküne göre yolu kod noktası sırasında önce gelen dosyaya gider; uygulama durumu kullanıcıya bildirir.
- Dosya adında şu karakterler bulunamaz: `/ \ : * ? " < > |` ve bağlantı sözdizimini bozan `# ^ [ ]`. Görünen ad bu karakterleri içeriyorsa `name` alanında aynen durur; uygulama dosya adını üretirken onları atar.

## Frontmatter

Dosyanın ilk satırı (varsa BOM'dan sonra) `---` ise frontmatter başlar ve sonraki ilk `---` satırında biter. Sınır satırı tam olarak `---` olmalıdır.

Uygulama bir bloğu ancak bütün YAML okuyucularının (Obsidian dahil) aynı okuyacağından eminse okur. Blok üç durumdan birindedir:

- **Yok:** dosya `---` ile başlamıyor ya da kapanış satırı da kapanış adayı da (ardında boşluk ya da sekme olan `---`) yok. Kapanışı olmayan `---` ile başlayan dosyaya alan yazılınca başa yeni bir blok eklenir; eski `---` satırı gövdede kalır.
- **Okunur:** her alan desteklenen alt kümededir ya da ham alandır.
- **Çözülemez:** frontmatter yok sayılır: `type` okunmaz, uygulama frontmatter'a yazmaz, alan yazma isteği hata döndürür (başa yeni blok da eklenmez). İki uygulama aynı dosyayı aynı görmelidir; Obsidian'ın okuyamadığı bloğa yazılmaz.

Desteklenen YAML alt kümesi:

```yaml
name: Ahmet Yılmaz            # düz değer
place: "[[Spor Salonu]]"      # tırnaklı değer (tek ya da çift tırnak)
radius: 100                   # sayı
date: 2026-10-02              # tarih
aliases: [Ahmet, Ahmet abi]   # tek satırlı liste
diller:                       # çok satırlı liste
  - Türkçe
  - İngilizce
etiketler:                    # çok satırlı liste, anahtarla aynı girintide
- günlük
goals:                        # tek düzey iç içe eşlem
  spor: true                  # evet/hayır
  kitap: 25
"iki nokta: içeren": değer    # tırnaklı anahtar
```

- Anahtar satır başında yazılır; boşluk ve Türkçe karakter içerebilir (`doğum günü`). Anahtardan sonra `:` ve ardından boşluk, sekme ya da satır sonu gelir; `anahtar : değer` yazımı da kabul edilir. Anahtar tırnaklı olabilir.
- Anahtarlar Unicode normalleştirmesi yapılmadan bayt bayt karşılaştırılır. Bir anahtar blokta (ve bir eşlemde) yalnızca bir kez geçer.
- Yorum, satır başındaki ya da öncesinde boşluk olan `#` ile başlar. Yorumlar ve boş satırlar korunur.
- İki liste biçimi eşdeğerdir; Obsidian bir özelliği düzenlediğinde listeyi çok satırlı biçimde yeniden yazar. Liste beklenen alandaki tek değer tek öğeli liste, boş değer boş liste sayılır.
- Liste öğesi ve eşlem kaydı tek satırlık tek değerdir. Girinti boşlukla yapılır; bir listenin ya da eşlemin bütün satırları aynı girintidedir.

### Türler

Tırnaklı değer her zaman metindir. Tırnaksız değerin türü yazımından okunur:

| Tür | Kabul edilen yazım |
|---|---|
| Sayı | `[-+]?(0\|[1-9][0-9]*)(\.[0-9]+)?` (örnek: `25`, `-3`, `+5`, `29.0290`) |
| Evet/hayır | `true`, `True`, `TRUE`, `false`, `False`, `FALSE` |
| Boş | değer yok, `null`, `Null`, `NULL`, `~` |
| Tarih | `YYYY-MM-DD`; var olan bir gün, yıl 0100 ile 9999 arası |
| Metin | diğer her şey |

Okuyucuların birbirinden farklı okuduğu yazımlar metin okunur: `yes`, `no`, `on`, `off`, `012`, `0x1F`, `.5`, `5.`, `1_000`, `14:30`, üstel sayılar (`1e-5`), `2026-1-2`, zaman damgaları (`2026-10-02T10:00:00`), var olmayan tarihler.

Çift tırnak içinde şu kaçışlar okunur: `\0 \a \b \t \n \v \f \r \e \" \/ \\ \N \_ \L \P`, ters bölüden sonra boşluk ya da sekme, `\xHH`, `\uHHHH`, `\UHHHHHHHH`. Tek tırnak içinde `''` tek tırnak demektir; başka kaçış yoktur.

### Ham alanlar

Geçerli YAML olan ama alt kümenin dışında kalan yapılar yalnızca kendi anahtarını etkiler: o alan ham metin olarak gösterilir, uygulama onu değiştirmez ve silmez. Diğer alanlar okunur ve düzenlenir. Ham alan olan yapılar:

- Blok metin (`|`, `>`).
- Çapa (`&ad`) ve daha önce tanımlanmış bir çapaya takma ad (`*ad`); ad yalnızca ASCII harf, rakam, `-` ve `_` içerir.
- Tek satırlık tek değerin önündeki `!!str` etiketi.
- Akış eşlemi (`{a: 1}`), iç içe akış (`[a, [b]]`, `[a: b]`) ve sonunda virgül olan liste (`[a, b,]`), tek satırda.
- Daha derin iç içelik: eşlem içinde eşlem ya da liste, liste içinde eşlem ya da liste.
- Tırnaksız bir değerin sonraki girintili satırlarda süren metni.

### Çözülemeyen bloklar

Aşağıdakilerden biri bloğun bütününü çözülemez kılar:

- Açılış ya da kapanış adayında `---` ardından boşluk ya da sekme; blok içinde `---` ya da `...` ile başlayıp boşlukla süren ya da biten satır.
- Yinelenen anahtar (üst düzeyde ya da aynı eşlem içinde) ve `<<` anahtarı.
- Satır başında anahtar olmayan içerik; girintili ilk anahtar.
- Tırnaksız yazılmış, metinden başka okunabilecek anahtar: Türler tablosunda metin olmayan bir yazım; Tırnaklama 7 ve 8'deki tarih ve `...` yazımları; `-`, `?`, `:` ile başlayan anahtar; sayıya benzeyen anahtar (isteğe bağlı `+` işaretinden sonra `.` ile başlayıp Tırnaklama 6'ya uyan, ya da rakamla başlayıp yalnızca rakam, `a`-`f`, `A`-`F`, `x`, `X`, `o`, `O`, `_`, `.`, `+`, `-`, `:` içeren). `yes`, `no`, `on`, `off` anahtar olarak kabul edilir.
- Satırında kapanmayan tırnak, köşeli ya da süslü parantez.
- Tırnaklı değerden ya da tek satırlı listeden sonra yorum dışında içerik (`"a" b`); araya boşluk konmadan yazılmış yorum (`"a"# yorum`).
- Tırnaksız değerde ikinci `: ` (`a: b: c`) ya da sondaki `:`.
- Yukarıda sayılmayan kaçış (`"\q"`).
- Değeri olan satırın altında girintili `-` ya da `anahtar: değer` satırı; tırnaklı değerin, tek satırlı listenin ya da ham değerin altında girintili içerik. Süren metnin bir satırı `-`, `?`, `:` ya da Tırnaklama 2'deki karakterlerden biriyle başlıyorsa, `:` ardından boşluk ya da yorum içeriyorsa, ya da satırları arasında yorum varsa.
- Liste ile eşlemin aynı düzeyde karışması; tutarsız girinti.
- Girintide sekme, `-` işaretinden sonra sekme, yalnızca sekme içeren boş satır, sekmeyle girintilenmiş yorum.
- Değerin başında `, ] } % @` ya da ters tırnak; değer olarak tek başına `-`, `?`, `:` ya da bunlardan sonra boşluk.
- Tek satırlı listede boş öğe, öğe içinde yorum, tırnaksız öğede `?` ya da ardından boşluk gelmeyen `:` (`[a:b]`), çapa, takma ad ya da etiket.
- Tanımlanmamış çapaya takma ad; takma addan sonra içerik; art arda iki çapa; `!!str` dışında etiket ya da `!!str` ardından tek satırlık tek değerden başka bir şey.
- Blok metin başlığından sonra yorum dışında içerik (`> metin`); blok metnin, ilk satırından (başlık girinti belirtiyorsa o girintiden) daha az girintili satırı; satır başındaki bir yorumla bölünmesi; ilk satırından önce ondan uzun, yalnızca boşluktan oluşan satır.
- Derin yapının içinde: sonraki satırda süren metin, girinti belirten blok metin başlığı (`|2`), blok metin bulunan alanda araya giren yorum ya da yalnızca boşluktan oluşan satır.
- Kontrol karakteri (sekme dışında U+0000 ile U+001F arası, U+007F ile U+009F arası), U+2028, U+2029, U+FEFF, U+FFFE, U+FFFF ya da UTF-8 olarak çözülemeyen bayt.

### Tırnaklama

Uygulama metni, şu koşulların hepsi sağlanıyorsa tırnaksız, yoksa çift tırnak içinde yazar:

1. Boş değildir; ilk ve son karakteri boşluk ya da sekme değildir.
2. İlk karakteri şunlardan biri değildir: `- ? : , [ ] { } # & * ! | > ' " % @` ve ters tırnak.
3. `:` ardından boşluk ya da sekme içermez, `:` ile bitmez; boşluk ya da sekme ardından `#` içermez.
4. Kaçış gerektiren karakter içermez (aşağıda).
5. Büyük küçük harf ayrımı yapılmadan şunlardan biri değildir: `true`, `false`, `yes`, `no`, `on`, `off`, `y`, `n`, `null`, `~`, `<<`, `=`.
6. Sayıya benzemez. İsteğe bağlı bir `+` ya da `-` işaretinden sonra: rakamla başlıyor ve hiç boşluk ya da sekme içermiyorsa; ya da `.` ile başlıyor ve ardından rakam geliyorsa ya da kalanı (harf ayrımı yapılmadan) `inf` ya da `nan` ise sayıya benzer.
7. Tarihe benzemez: dört rakam, `-`, bir ya da iki rakam, `-`, bir ya da iki rakamla başlamaz (devamı ne olursa olsun).
8. `...` değildir ve `...` ardından boşluk ya da sekme ile başlamaz.
9. Tek satırlı liste içindeyse ayrıca `, [ ] { } : ?` karakterlerinden hiçbirini içermez.

Çift tırnak içinde: ters bölü `\\`, çift tırnak `\"`, LF `\n`, CR `\r`, sekme `\t`, U+0000 `\0`, U+0085 `\N`, U+2028 `\L`, U+2029 `\P` olarak yazılır. Kalan U+0001 ile U+001F arası ve U+007F ile U+009F arası karakterler `\xHH` (iki büyük harfli onaltılık hane), U+FEFF, U+FFFE ve U+FFFF `\uHHHH` olarak yazılır. Başka hiçbir karakter kaçışla yazılmaz. Böylece satır sonu içeren metin de tek satırda kalır.

Anahtar da aynı kuralla (1 ile 8 arası) tırnaksız ya da çift tırnakla yazılır. Boş anahtar ve `<<` yazılamaz.

Diğer türler: evet/hayır `true` ya da `false`; tam sayı ondalık rakamlarla; sayı, kendisine verilen yazımla (Türler bölümündeki sayı yazımına uymayan yazım reddedilir); tarih `YYYY-MM-DD`.

### Yazma kuralları

- Bir alan değişirken yalnızca o anahtarın satırları yeniden yazılır. Diğer satırlar, sıraları, tırnak biçimleri ve yorumlar korunur; değerler yeniden üretilmez (`29.0290`, `29.029` olmaz).
- Yeniden yazılan satırda anahtar, `:` ve değerden önceki boşluklar aynen kalır (değer yoksa tek boşluk konur); satır sonundaki yorum, önündeki boşluklarla birlikte korunur; yorum yoksa sondaki boşluklar atılır. Yeniden yazılan satır kendi satır sonunu korur.
- Aynı değeri yeniden yazmak dosyayı değiştirmez. Metin bayt bayt ve yalnızca metinle karşılaştırılır. Sayılar değerce karşılaştırılır: işaret, tam kısım ve sondaki sıfırları atılmış kesir aynıysa sayı aynıdır (`20.029` ile `20.0290`, `+5` ile `5`, `-0` ile `0`). Evet/hayır ve tarih değerce, liste sırayla öğe öğe karşılaştırılır.
- Değişen listenin mevcut biçimi (tek satırlı ya da çok satırlı) korunur. Listede ya da listeye çevrilen tek değerde, yeni bir öğeyle aynı olan mevcut değer dosyadaki yazımıyla yazılır (sırayla ilk eşleşen); tek satırlı listeye girecek tırnaksız yazım 9. koşulu sağlamıyorsa yeniden üretilir.
- Tek satırlı liste `[a, b]` biçiminde, öğeler `, ` ile ayrılarak yazılır; boşalan liste `[]` olur.
- Çok satırlı listede baştaki ve sondaki aynı kalan öğelerin satırlarına dokunulmaz. Aradaki satırlar sırayla yeniden yazılır (girinti, `-` sonrası boşluk ve yorum korunur); fazla yeni öğeler son yeniden yazılan satırın ardına (böyle bir satır yoksa aynı kalan önceki öğenin ardına, o da yoksa ilk öğenin önüne) mevcut girintiyle ve `- ` ile eklenir; fazla eski satırlar silinir. Boşalan listede `anahtar:` satırı kalır.
- Eşlemde yalnızca hedef kaydın satırı değişir; yeni kayıt son kaydın ardına mevcut girintiyle eklenir. Son kaydı silinen eşlemin `anahtar:` satırı kalır. Değeri olmayan anahtara kayıt yazılınca kayıt anahtarın altına iki boşluk girintiyle eklenir; değeri olan bir alana kayıt yazılamaz.
- Çok satırlı liste olmayan bir alana (tek değer, boş değer, eşlem) liste yazılırsa tek satırlı yazılır; liste ya da eşlem olan bir alana tek değer yazılırsa değer anahtar satırına yazılır. İki durumda da eski öğe ve kayıt satırları silinir.
- Alan silinirken ya da biçimi değişirken aradaki yorum ve boş satırlar yerinde kalır. Olmayan alanı ya da kaydı silmek dosyayı değiştirmez.
- Yeni anahtar frontmatter'ın sonuna, kapanış satırının hemen önüne eklenir. Uygulama yeni listeyi tek satırlı, yeni eşlemi iki boşluk girintiyle yazar.
- Frontmatter'ı olmayan dosyaya alan yazılacaksa dosyanın başına yeni bir blok eklenir: `---`, alan satırları, `---`. Blok ile gövde arasına boş satır eklenmez.
- Ham alan değiştirilemez ve silinemez; çözülemeyen bloğa yazılmaz.

## Bağlantılar

- Varlığa bağlantı: `[[Ahmet Yılmaz]]`
- Metinde takma ad geçiyorsa görünen metin korunur: `[[Ahmet Yılmaz|Ahmet abi]]`
- Arayüzdeki `@` ile seçim dosyaya wikilink olarak yazılır; `@` işareti dosyada yer almaz.
- Bir varlığın adı değiştiğinde uygulama aynı kasa yazma kuyruğu altında önce varlık dosyasının `name` ve `qualifier` alanlarını yazar (ayırt edici kaldırılmışsa anahtar silinir), dosyayı yeni ada taşır, ardından indekste eski dosyaya çözülen bağlantıların kaynak dosyalarını diskten yeniden okuyup düzenler. Eski/yeni yol ve değişen kaynaklar en son indekslenir. Yeni dosya adı mevcut ad üretme ve kasa genelinde benzersizlik kurallarına uyar; başka dosyanın üzerine yazılmaz.
- Yeniden adlandırmada yalnız hedef yazımı değişir. Çapa, gömme işareti, hedef çevresindeki boşluklar, `.md` soneki, yol hedefinin yol biçimi ve tablo ayırıcı kaçışı korunur. Açık görünen metin kullanıcınındır: `[[Eski|Eski]]` → `[[Yeni|Eski]]`; görünen metinsiz `[[Eski]]` → `[[Yeni]]`. Kullanıcı görünen metni ayrıca düzeltir.
- Gövdede hedef bayt aralığı değiştirilir; frontmatter'da çözülmüş metin değeri ilgili alan/liste/eşlem girdisi yazıcısıyla YAML kaçışları doğru kodlanarak yazılır. Ham alanlar değiştirilmez; eski hedefe benzeyen bağlantı içeren ham alanlar sonuçta bildirilir. İndeks yalnız kaynakları ve çözülmüş hedefi seçmek içindir; eski satır veya bayt aralığı yazmak için kullanılmaz. Yeniden okunan bağlantı hedefi ve dosya sahipliği doğrulanır; aynı yazımlı başka dosya bağlantısı korunur.
- Kaynak dosyası okunamaz veya yazılamazsa diğer kaynaklar devam eder; sonuç yeni varlık yolunu, güncellenen dosyaları ve güncellenemeyen dosya/neden listesini taşır. Çok dosyalı işlem kasa genelinde atomik değildir: kesinti sonrası varlık taşınmış, bazı bağlantılar eski kalmış olabilir. Sonraki yeniden adlandırma hâlâ çözülen bağlantıları günceller; artık çözülmeyen eski hedefler elle düzeltilir. İşlem geçmişi veya gizli yönlendirme bilgisi tutulmaz.
- Metadata yazımından sonra dosya taşıma başarısız olursa bağlantı kaynaklarına geçilmez; okunan özgün varlık belgesi atomik olarak geri yazılır. Hedef sonradan oluşmuşsa, başarılı geri yazmadan sonra ad çakışması bildirilir. Geri yazma da başarısız olursa sonuç eski yolu ve açık bir kısmi değişiklik bildirimi taşır; arayüz işlemi tamamlanmış gibi göstermez. İndeks mevcut disk durumundan yenilenir.

Sözdizimi: `[[hedef]]`, `[[hedef|görünen metin]]`, `[[hedef#çapa]]`, `[[hedef#çapa|görünen metin]]`.

- Hedef, ilk `#` ya da `|` karakterine kadar olan kısımdır; baştaki ve sondaki boşluklar atılır. Hedef uzantısız dosya adıdır; sondaki `.md` yok sayılır. `/` içeren hedef kasa köküne göre yoldur. Baştaki `/` ya da `./` yok sayılır. Sondaki `.md` atıldıktan sonra boşluklar yeniden atılır.
- Tablo içinde görünen metin ayırıcısı `\|` olarak yazılabilir; ters bölü ayırıcının parçasıdır, hedefe dahil değildir.
- Çapa bir başlık ya da `^` ile başlayan blok kimliğidir. Yeniden adlandırmada yalnızca hedef değişir; çapa ve görünen metin korunur.
- Hedefi boş olan bağlantı (`[[#Başlık]]`) aynı dosyanın içine gider; varlık bağlantısı değildir.
- Gömme (`![[hedef]]`) aynı kurallarla bağlantı sayılır. Kaçırılmış ünlem (`\![[hedef]]`) gömme değildir.
- Bağlantı tek satırdadır ve içinde `[[` ya da `]]` bulunmaz.
- Çitli kod bloğu (```` ``` ```` ya da `~~~` ile açılan) ve satır içi kod içindeki `[[...]]` bağlantı sayılmaz.
- Hedefi kasada bulunmayan bağlantı geçerlidir ve korunur. Taranmayan klasörlerdeki dosyalar hedef olamaz.
- Markdown biçimli bağlantılar (`[metin](dosya.md)`) korunur ama varlık bağlantısı sayılmaz ve yeniden adlandırmada güncellenmez.

- Görünen metin, ilk `|` karakterinden sonraki her şeydir. Hedefi ve çapası birlikte boş olan yazım bağlantı değildir.
- Satır içi kod, bir ya da daha çok ters tırnakla açılır ve aynı satırda aynı sayıda ters tırnakla kapanır. Ters bölüyle kaçırılmış açılış (`\[[`) bağlantı değildir.
- Frontmatter'da bağlantı, çözülmüş değerlerin metninde aranır; ham alanlarda ve çözülemeyen blokta aranmaz.

## Blok kimliği

- Uygulamanın ürettiği her olay ve görev satırı sonunda bir kimlik taşır: `^a1b2c3`
- Biçim: satırın sonunda, bir boşluktan sonra `^` ve ardından 6 karakter (küçük harf `a-z` ve rakam).
- Kimlik opaktır: tür ya da başka anlam taşıyan bir önek içermez. Satırın olay mı görev mi olduğunu kimlik değil satırın yazımı belirler.
- Uygulama kimliği rastgele üretir ve kasadaki mevcut kimliklerle çakışmadığını denetler. Satır düzenlense de kimlik değişmez.
- Kimliği olmayan (elle ya da Obsidian'da yazılmış) satıra, uygulama o satırı ilk kez değiştirdiğinde kimlik eklenir.
- Okurken Obsidian'ın kabul ettiği her kimlik (harf, rakam ve `-`, herhangi bir uzunlukta) tanınır ve değiştirilmez.
- Kimliğin kasa genelinde benzersiz olması amaçlanır ama garanti değildir: dışarıda yapılan kopyalama aynı kimliği çoğaltabilir. Bu durumda kimliğin sahibi ilk geçen satırdır (dosya yolu sırası, sonra dosya içi sıra). Diğer satırlar kendiliğinden değiştirilmez; uygulama onlardan birini değiştirdiğinde o satıra yeni kimlik verir.
- Bir olay ya da görev satırının altındaki, kendisinden daha girintili satırlar (alt madde, devam satırı) o satırın parçasıdır: onunla birlikte taşınır, birleştirilir ve silinir. Uygulama bu satırları üretmez, yalnızca korur. Aradaki boş satırlar, ardından yine girintili bir satır geliyorsa bloğa dahildir. Girinti yalnızca satır başındaki boşluk ve sekmelerle sütun olarak ölçülür; sekme bir sonraki dördün katına ilerler. Alıntı içindeki görevler tek satırlık bloklardır; `>` girinti sayılmaz. Alt satır olan bir görev silinince yalnızca kendi satırları silinir; üst blok o kadar kısalır; sonunda kalan boş satırlar blok aralığından çıkar ama dosyada korunur.

## Gün dosyası

Yol: `journal/2026-10-02.md`

Gün dosyasının kimliği yoludur: `journal/` altında adı geçerli bir tarih olan (`YYYY-MM-DD.md`) dosya, frontmatter'ı olmasa da (örneğin Obsidian'da açılmışsa) o günün dosyasıdır. Bir günün tek dosyası vardır. Uygulama dosyayı oluştururken `type` ve `date` alanlarını yazar; `date` ile dosya adı çelişirse dosya adı geçerlidir.

```markdown
---
type: journal
date: 2026-10-02
goals:
  spor: true
  kitap: 25
---

## Tasks
- [ ] [[Ahmet Yılmaz]]'a teklifi gönder 📅 2026-10-05 ^k7m2p9
- [x] Market alışverişi ✅ 2026-10-02 ^q3w8e1

## Events
- 14:30 [[Ahmet Yılmaz|Ahmet]] ile [[Kadıköy Ofis]]'te teklifi konuştuk ^a1b2c3
- [[Elif]] ile yemek ^d4e5f6

## Journal
Bugün genel olarak verimli geçti...
```

- **Tasks:** O gün oluşturulan görevler. Görev, bitiş tarihi ne olursa olsun oluşturulduğu günün dosyasında kalır. Yeni görev bölümün sonuna eklenir.
- **Events:** Hızlı giriş ve widget buraya satır ekler.
- **Journal:** Serbest yazı. Uygulamada yazarken tanınan varlık adları bağlantıya çevrilir, başka değişiklik yapılmaz.
- `goals` altındaki anahtar, hedef dosyasının `key` alanıdır. Değer evet/hayır hedefinde `true`, sayısal hedefte sayıdır.

### Hedef gün kayıtları

- `goals` eşleminde `true` yapıldı, `false` veya anahtarın yokluğu yapılmadı demektir. Sayısal kayıt o günün miktarıdır; `0` ve yokluk ilerleme sağlamaz. Kaldırma ilgili anahtarı siler, `false` yazmaz. Eksik dosyada kaldırma no-op'tur; değer yazılırken gün dosyası `type: journal` ve `date` ile oluşturulur.
- Yalnız hedef eşlem kaydı değişir; komşu değerler, yorumlar ve gövde baytları korunur. Aynı anlamdaki değer no-op'tur. Eksik `goals` veya değersiz `goals:` açılabilir; ham, skaler, liste veya açık `null` alanına yazma/silme `notAMapping` hatası verir.
- Miktarlar sonlu, negatif olmayan sayılardır. Negatif, taşan, ham veya tanımla türü uyuşmayan dış kayıtlar korunur ama hesaplara katılmaz. Aynı güne birden fazla kayıt verilirse son kayıt geçerlidir; iki kez toplanmaz. Hesaplar verilen günün sonuna kadarki kayıtları kullanır; gelecek kayıtlar güncel ilerlemeyi/seriyi artırmaz.

### Bölümler

- Başlık satırı, satır başında en çok üç boşluktan sonra gelen 1 ile 6 arası `#` ve ardından boşluk, sekme ya da satır sonudur. Altı çizili başlıklar tanınmaz. Tanınan bölüm başlığında `##` ile ad arasında tek boşluk bulunur.
- Çitli kod bloğu, satır başında en çok üç boşluktan sonra gelen en az üç `` ` `` ya da `~` ile açılır; bir liste öğesinin içindeyse girinti öğenin içerik sütununa göre ölçülür. Ters tırnaklı çitin açılış satırında başka ters tırnak bulunmaz. Çit, aynı işaretten en az o kadarını taşıyan ve başka içeriği olmayan satırla kapanır; kapanmayan çit dosya sonuna kadar sürer. İçindeki satırlar başlık, olay, görev ya da bağlantı sayılmaz.

- Bölüm başlığı tam olarak `## Tasks`, `## Events` ya da `## Journal` satırıdır (sondaki boşluklar yok sayılır). Bölüm, aynı ya da daha üst düzeydeki bir sonraki başlığa kadar sürer.
- Aynı başlık birden fazla geçerse ilki geçerlidir.
- Tanınmayan başlıklar ve ilk başlıktan önceki içerik korunur, düz metin olarak gösterilir.
- Günlük yazısı değiştirilirken Journal bölümünün başlığından sonraki satırlar, bölümün sonundaki boş satırlar hariç, yeni metinle değiştirilir. Bölüm yoksa yalnız boş olmayan metin için açılır; bölüm yoksa ve metin boş ya da yalnız boşluklardan oluşuyorsa dosyaya dokunulmaz, eksik gün dosyası oluşturulmaz. Mevcut bölümde metin boşsa başlık ve sondaki boş satırlar kalır; metnin sondaki boş satırları (yalnız boşluk veya sekme içerenler dahil) yazılmaz. Eklemedeki yapı kısıtları burada da geçerlidir; gövdedeki `---` yatay çizgisi frontmatter oluşturmadığı için kabul edilir.
- Bölümler ilk ihtiyaç duyulduğunda oluşturulur. Boş bölüm yazılmaz; içi sonradan boşalan bölümün başlığı silinmez.
- Yeni bölüm Tasks, Events, Journal sırasındaki yerine açılır: bu sırada kendinden sonra gelen ilk mevcut bölümün önüne, öyle bir bölüm yoksa dosyanın sonuna. Öncesinde bir boş satır bırakılır (frontmatter'dan hemen sonra açılıyorsa da); dosyanın ilk içeriğiyse bırakılmaz.
- Ekleme yeniden okunduğunda satır hedef bölümde görünmeyecekse (kapanmayan kod çiti, çözülemeyen frontmatter) ya da eklenen metin belgenin yapısını değiştirecekse (birinci ya da ikinci düzey başlık, kapanmayan kod çiti, frontmatter sınırı) işlem reddedilir ve dosyaya dokunulmaz. Alt başlık (`###` ve aşağısı) ve kapalı kod bloğu eklenebilir.
- Yalnızca boş satırlardan oluşan ekleme yapılmaz.
- Bölümün sonuna eklenen satır, bölümdeki son boş olmayan satırın ardına yazılır.

### Olay satırı

- Events bölümündeki, girintisiz `- ` ile başlayan ve görev olmayan her liste satırı bir olaydır. Okurken `* ` ve `+ ` liste işaretleri de kabul edilir.
- Saatli: `- HH:MM metin ^kimlik` (24 saat, iki haneli). Okurken tek haneli saat (`9:05`) de kabul edilir ve olduğu gibi korunur.
- Saat 0-23, dakika 00-59 olmalıdır; geçersiz yazım saat sayılmaz, satır saatsiz olaydır ve yazım metnin parçası kalır.
- Saatsiz: `- metin ^kimlik` (saat isteğe bağlıdır)
- Olay okunurken liste işaretinden sonraki boşluk ve sekmeler metne dahil edilmez; düzenlerken bu ayırıcıların özgün yazımı korunur.
- Saat, olayın yazıldığı yerin yerel saatidir; saat dilimi tutulmaz.
- Geçmiş bir güne sonradan olay eklenebilir; satır o günün dosyasına yazılır.
- Saatli olay, saati kendisinden büyük olan ilk saatli olayın önüne eklenir; öyle bir olay yoksa bölümün sonuna. Saatsiz olay bölümün sonuna eklenir. Mevcut satırların yeri değişmez.
- Olayın saati değiştirilirse ya da saatsiz olaya saat verilirse satır, altındaki satırlarla birlikte, aynı kuralla yeni yerine taşınır; kural onu zaten bulunduğu yere koyuyorsa satırlar yer değiştirmez. Saati kaldırılan olay yerinde kalır. Taşınan satırların içeriği korunur, satır sonları yeni satır kuralına uyar. Bu kural saati küçülen olayı, kendisinden büyük saatli olay yoksa, saatsiz olayların da arkasına koyar.
- Uygulama yeni olayı `- ` işaretiyle yazar; saat, metin ve kimlik arasında tek boşluk bulunur. Mevcut satır düzenlenirken yalnızca değişen parça (metin, saat ya da kimlik) yeniden yazılır; girinti, liste işareti ve altındaki satırlar korunur.
- Gösterim sırası dosyadaki sıradır.

## Görev satırı

Obsidian Tasks biçimi. Onay kutusu taşıyan her liste satırı görevdir; hangi dosyada ya da bölümde durduğu fark etmez. Girintili görev satırı (alt görev) de görevdir. Okurken `*` ve `+` işaretleri, numaralı liste (`1.` ya da `1)`) (en çok dokuz rakam), işaretten sonra birden çok boşluk ve alıntı içindeki görev (`> - [ ] ...`) de kabul edilir. Kutunun içinde tek karakter bulunur ve `]` işaretinden sonra boşluk ya da satır sonu gelir.

| Öğe | Yazım |
|---|---|
| Yapılacak | `- [ ]` |
| Devam ediyor | `- [/]` |
| Bitti | `- [x]` |
| İptal | `- [-]` |
| Bitiş tarihi | `📅 2026-10-05` |
| Başlangıç tarihi | `🛫 2026-10-01` |
| Tamamlanma tarihi | `✅ 2026-10-02` |
| Öncelik | `⏫` yüksek, `🔼` orta, `🔽` düşük |
| Tekrar | `🔁 every week` |
| Proje | `#project/portfolyo` |

Örnek: `- [/] Portfolyo sitesini bitir 🛫 2026-10-05 📅 2026-10-20 #project/portfolyo ^z5n4r2`

- Çitli kod bloğu ve frontmatter içindeki satırlar olay ya da görev sayılmaz.
- Tanınmayan durum karakteri korunur ve açık görev sayılır; `[X]` bitti sayılır.
- Alanlar boşlukla ayrılır; tarih işareti ile ISO tarih arasında tek boşluk vardır. Yeni satırda metinden sonra ve kimlikten önce `🛫 başlangıç`, `📅 bitiş`, `✅ tamamlanma`, öncelik, `🔁 tekrar`, `#project/...` sırasıyla yazılır. Okurken sıra serbesttir; alanlar metnin herhangi bir yerinde bulunabilir. Metin tanınan alanlar çıkarıldıktan sonra kalan parçaların boşluk/sekmeleri sadeleştirilmiş halidir. Ham satır baytları değişmez. Geçersiz tarih (`📅 2026-13-40`) ve tanınmayan emoji metin olarak kalır. Satır içi kod ve wikilink, satır içi Markdown bağlantısı veya referans bağlantısı (`[metin][etiket]`, `[metin][]`) içindeki alan benzeri yazım alan değildir.
- Tarih/öncelik/tekrar/proje yinelenirse ilk geçerli alan değerdir; bütün tanınan tokenların UTF-8 aralıkları saklanır. Proje `#project/` ardından boş olmayan, boşluk ve Markdown ayraçları içermeyen bir addır; tek proje kullanılır, birden çoksa ilki. `/` ile alt projeler serbesttir. Proje adları NFC ve yerelden bağımsız küçük harf eşlemesiyle karşılaştırılır; özgün yazım dosyada korunur. Alt proje ayrı projedir (üst projenin görevlerine otomatik katılmaz). `🔺` ve `⏬` öncelikleri `other` olarak okunur; uygulama yalnız `⏫`, `🔼`, `🔽` yazar.
- Alan düzenlenirken mevcut konum ve çevredeki diğer baytlar korunur; eksik alan kimlikten önce sona eklenir. Alan kaldırılırken token ve varsa önündeki tek boşluk/sekme silinir; yinelenen aynı alanların tümü kaldırılır. Metin düzenlemesi alanları ve bunların sırasını korur; yeni metin ilk mevcut metin parçasının yerini alır.
- Yeni görev eklemede ham metnin boşlukları, kod ve bağlantı yazımı aynen korunur; boşluk sadeleştirmesi yalnız okunan görev metnine uygulanır. Tamamlama (`done`) çağıranın verdiği yerel gün ile `✅ YYYY-MM-DD` yazar; yalnız zaten `done` durumunda var olan tarih çağıran yeni tarih vermedikçe korunur. Başka bir durumdan `done` durumuna geçişte çağıranın tarihi zorunludur. Tarihsiz tamamlama isteği reddedilir. Yeniden açma (`todo` veya `inProgress`) tanınan `✅` alanlarını kaldırır. İptal (`cancelled`) tamamlanma tarihine dokunmaz; yoksa eklemez. Diğer baytlar, girinti, liste işareti, kutu yazımı ve alt satırlar korunur.
- Yeniden okunduğunda istenenden farklı okunacak metin (saatsiz olayda saatle başlayan, olayda onay kutusuyla başlayan, kimlik gibi biten metin) yazılmaz; işlem reddedilir ve dosyaya dokunulmaz.
- Uygulamanın ayrıştırmadığı alanlar (tanımadığı emoji alanları dahil) metnin parçası olarak korunur.

**Tarihsiz görevler:** Bitiş tarihi olmayan görev, oluşturulduğu gün bugün ekranında görünür. Sonraki günlerde bugün ekranında yer almaz, "tarihsiz" listesinde durur.

### Tekrarlayan görevler (aşama 5)

- Desteklenen `🔁` alanı: `every day`, `every N days`, `every week`, `every N weeks`, `every month`, `every N months`, `every year`, `every N years`, `every monday|tuesday|wednesday|thursday|friday|saturday|sunday` (tek gün) ve `every week on monday` (aynı şekilde tek gün). N pozitif tam sayıdır. İngilizce sözcüklerin harfi duyarsız okunur; uygulama küçük harfle yazar. İsteğe bağlı `when done` soneki sonraki tarihi tamamlanma gününden hesaplar. Yoksa referans bitiş tarihi, yoksa başlangıç tarihi, ikisi de yoksa tamamlanma günüdür.
- Alan `🔁` ile sonraki tarih/öncelik/proje/tekrar alanı veya satır sonu arasında kalan kuraldır. Alt küme dışındaki yazım düz metin olarak korunur; arayüz “Tanınmayan tekrar” gösterir, yeni görev üretmez. Kod ve bağlantı içindeki yazım alan değildir. Yinelenen geçerli tekrarda ilk kural kullanılır. Açıkça Tekrar düzenlenirse eski tekrar yazımı hedef alınıp değiştirilir/kaldırılır.
- Yeni görevde yazım sırası: `🛫`, `📅`, `✅`, öncelik, `🔁`, `#project/...`, kimlik. Mevcut görevde yalnız hedef alan yerinde değiştirilir.
- Açık tekrarlayan görev tamamlandığında özgün satır `[x]` ve `✅` alarak yerinde kalır; hemen üstüne aynı ilk satır metni ve alanlarıyla, açık `[ ]`, sonraki `📅`, varsa `🛫` aynı gün farkıyla kaydırılmış, `✅` olmadan ve kasada benzersiz yeni kimlikle yeni satır eklenir. Devam satırları ve alt görevler özgün görevde kalır; yeni örneğe kopyalanmaz. Kapatılmış görevi tekrar tamamlamak veya iptal etmek yeni örnek üretmez; geri açma mevcut sonraki örneği silmez.
- Haftanın günü sonraki o gündür (referans gün aynıysa yedi gün sonra). Gün/hafta tam aralık kadar ilerler. Ay/yıl taşması ayın son gününe sıkıştırılır (31 Ocak → 28/29 Şubat; 29 Şubat → sonraki yıl 28 Şubat). Desteklenen tarih sınırında sonraki tarih üretilemiyorsa işlem yazmadan hata verir; tamamlanma ve yeni satır tek atomik dosya işlemidir.
- Hızlı girişte yalnız görev modunda, metnin başında/sonunda bağımsız `!` orta (`🔼`), `!!` yüksek (`⏫`) olur; `!!!`, sözcük içi işaretler, kod ve bağlantı içindekiler korunur. Baş ve son işaret birlikteyse yüksek olan seçilir; açık emoji önceliği korunur. Düşük yalnız öncelik seçicisinden verilir. `her gün/hafta/ay/yıl`, `her N gün/hafta/ay/yıl`, `her pazartesi/.../pazar`, İngilizce eşdeğerleri ve `tamamlanınca`/`when done` hızlı girişte tekrar alanına çevrilir. Tekrar sözcükleri tarih ayrıştırmasından önce tüketilir; bilinen/protected bağlantı, kod, etiket ve `🔁` alanına dokunulmaz.

## Kişi dosyası

Yol: `people/Ahmet Yılmaz.md`

```markdown
---
type: person
name: Ahmet Yılmaz
aliases: [Ahmet, Ahmet abi]
tanışma: Üniversite
doğum günü: 1995-04-12
---

Serbest notlar...
```

- Uygulamanın kullandığı alanlar: `type`, `name`, `aliases`, `qualifier`.
- Uygulama yeni varlık oluştururken `name` alanını her zaman yazar. `name` ve `qualifier` değerlerinin başındaki ve sonundaki boşluklar ve satır sonları kırpılır; içteki satır sonları ve kontrol karakterleri reddedilir. Boş takma adlar atılır. Üretilen dosya adı uzantısıyla birlikte en fazla 255 UTF-8 baytı olabilir; boş veya kontrol karakteri içeren adlar reddedilir.
- `name` alanı yoksa, boşsa ya da yalnız boşluk içeriyorsa görünen ad dosya adıdır.
- Diğer alanlar `templates/person.md` şablonundan gelir. Varsayılan şablon kasa oluşturulurken kullanıcının dilinde yazılır. Kullanıcı şablonu değiştirebilir ve kişi bazında istediği alanı ekleyebilir. Uygulama tanımadığı alanları korur ve kişi sayfasında gösterir.

### Aynı adlı varlıklar

Bağlantılar dosya adına gittiği için dosya adları farklı olmak zorundadır; ama kullanıcı dosya adı düşünmez.

- Görünen ad `name` alanındadır. Arayüz her yerde `name` değerini gösterir.
- Var olan bir adla ikinci varlık oluşturulurken uygulama kısa bir ayırt edici sorar ("iş", "üniversite"). Bu değer `qualifier` alanına yazılır ve dosya adını uygulama üretir:

```markdown
people/Ahmet Yılmaz (iş).md
---
type: person
name: Ahmet Yılmaz
qualifier: iş
aliases: [Ahmet]
---
```

- Arayüzde ikisi de "Ahmet Yılmaz" görünür; ayırt edici, adın altında küçük yazıyla gösterilir.
- Bağlantı: `[[Ahmet Yılmaz (iş)|Ahmet]]`
- İlk varlığın dosya adı değişmez; kullanıcı isterse ona da ayırt edici ekleyebilir.
- Aynı kural konumlar için de geçerlidir.

### Otomatik tanıma ve belirsizlik

- Tanıma `name` ve `aliases` üzerinden yapılır.
- Eşleşme Unicode harf ve rakam sınırlarında yapılır; sözcük içindeki ad tanınmaz. NFC ve yerelden bağımsız küçük harf karşılaştırması kullanılır; çok sözcüklü adın aralarında bir veya daha çok Unicode boşluk olabilir, satır sonu olamaz.
- Örtüşen eşleşmelerden en uzunu seçilir; eşit uzunlukta ad takma addan, sonra metinde önce başlayan eşleşme sonrakinden önce gelir. Aynı yazıma uyan bütün farklı varlıklar aday kalır.
- Adın hemen ardından gelen `'` veya `’` ile başlayan ek bağlantının dışında kalır. Var olan wikilinkler ve `[metin](hedef)` Markdown bağlantılarının tamamı, satır içi kod, kod çiti satırları ve belge düzeyindeki çağrıda frontmatter satırları taranmaz. `://` içeren, e-posta gibi içinde `@` geçen veya harf.harf biçiminde noktayla birleşen boşluksuz parçalar taranmaz; sözcük başındaki açık anmanın `@` işareti bu dışlamanın istisnasıdır. `#` veya `^` ile başlayan boşluksuz etiket ve kimlik parçaları da taranmaz.
- `@` yalnız önünde harf ya da rakam yokken açık anmadır; bilinen adda kaldırılır ve yalnız ad bağlanır. Bilinmeyen açık anmada `@` sonrasındaki büyük harfle başlayan en çok dört sözcük bildirilir; satır sonu, noktalama veya küçük harfle başlayan sözcük diziyi bitirir, kesmeyle başlayan ek dışarıda kalır.
- Tek aday ve kaynak yazımın ilk harfi adın veya eşleşen takma adın ilk harfiyle aynı büyük/küçük harfteyse eşleşme kesindir. İlk harfin büyük/küçük harfi farklıysa `isCaseMismatch` ile öneri olarak bildirilir, kullanıcı seçmeden bağlanmaz; açık `@` anmasında bu fark kesinliği bozmaz. Birden fazla aday, puanı ne olursa olsun belirsizdir ve kullanıcı seçmeden bağlanmaz. Bilinmeyen açık anma da bağlanmaz.
- Önünde boşluk olmadan `[`, `!`, `\`, `#`, `^` veya `|` bulunan ya da hemen arkasında `]` bulunan anma taranmaz; kaçırılmış ve kapanmamış bağlantı yazımı düz metin kalır. U+2028 ve U+0085 satır sonu sayılır, çok sözcüklü adın aralarındaki boşluk yerine geçmez.
- Bağlantı hedefi uzantısız dosya adıdır. Kaynak yazımı dosya adıyla bayt bayt aynıysa `[[Dosya Adı]]`, diğer durumda `[[Dosya Adı|yazım]]` yazılır; ayırt edicili varlıkta görünen metin her zaman yazılır. Takma ad dosya adıyla bayt bayt aynıysa ayırt edicisiz hedefte görünen metin ayrıca yazılmaz. Başındaki boşluklardan sonra `|` ile başlayan tablo satırında görünen metin ayırıcısı `\|` yazılır. Yazımın harfleri, boşlukları, ekler ve metnin diğer bütün baytları korunur.
- Kaynak yazımı artık aralıkla uyuşmuyorsa bağlantıya çevirme eski anma hatası verir. Hedef veya görünen metin wikilink sözdizimiyle temsil edilemiyorsa (örneğin görünen adda köşeli ayraç varsa) işlem reddedilir; hiçbir kısmi çıktı üretilmez.
- Bağlanan anmalar yeniden tanınmaz; kullanıcı seçimi bekleyen öneri, belirsiz ve bilinmeyen anmalar metinde kalır ve yeniden bildirilir.
- Bir ad ya da takma ad tek bir varlığa aitse ve yukarıdaki kesinlik koşulunu sağlıyorsa otomatik bağlanır.
- Birden fazla varlığa aitse adaylar bağlama göre sıralanır: o konumda daha önce birlikte geçmiş olmak, yakın zamanda geçmiş olmak, geçme sıklığı. En olası aday üstte önerilir.
- Uygulama emin değilse bağlamaz, kullanıcıya sorar. Sıralama ölçütleri dosyada tutulmaz, indeksten hesaplanır.

## Konum dosyası

Yol: `places/Kadıköy Ofis.md`

```markdown
---
type: place
name: Kadıköy Ofis
aliases: [ofis]
coordinates: [10.5000, 20.0290]
radius: 100
---
```

- `coordinates` enlem ve boylam, `radius` metre. İkisi de isteğe bağlıdır. Koordinat yoksa konum yalnızca adla eşleşir; GPS önerisinde yarıçap yoksa 100 metre kullanılır. Geçersiz koordinat veya yarıçap öneriye alınmaz; dosya değiştirilmez.

## Hedef dosyası

Yol: `goals/Spor.md`

```markdown
---
type: goal
name: Spor
key: spor
period: week
kind: boolean
target: 3
place: "[[Spor Salonu]]"
---
```

| Alan | Değerler | Açıklama |
|---|---|---|
| `key` | küçük harf, boşluksuz | Gün dosyasındaki `goals` anahtarı |
| `period` | `day`, `week`, `year` | Hedefin dönemi |
| `kind` | `boolean`, `number`, `milestone` | Kayıt türü; milestone sayılamayan yıllık hedeftir |
| `target` | sayı (milestone türünde yok) | Dönem başına hedef (haftada 3 gün, yılda 24 kitap, günde 20 sayfa) |
| `unit` | metin, isteğe bağlı | Sayısal hedefte birim (sayfa, bardak) |
| `place` | bağlantı, isteğe bağlı | Boolean hedefin koordinat ve açık yarıçap alanı olan konumuna girişte bugünün kaydı; cihaz tercihine göre bildir veya otomatik işaretle |

- Yeni hedefler şablonsuz `goals/<Ad>.md` dosyasında oluşturulur; ad ve dosya gövde adı NFC + harf duyarsız karşılaştırmada benzersizdir. Dosya adında kişi/konum oluşturmayla aynı güvenli karakter kuralları uygulanır.
- Otomatik anahtar: ad küçük harfe çevrilir; Türkçe `ç/ğ/ı/ö/ş/ü` → `c/g/i/o/s/u`, diğer aksanlar sadeleştirilir; ASCII harf ve rakam dışındaki ardışık karakterler tek `-` olur, uçtaki `-` kaldırılır. Boş sonuç `goal` olur. Örnek: `Su İçme` → `su-icme`. Kasadaki anahtarlarla NFC + harf duyarsız çakışmada `-2`, `-3`, … eklenir. Tanımı geçersiz hedeflerin anahtarları ve sahipsiz gün kayıtları da ayrılır. Anahtar oluşturulduktan sonra tanım düzenleyicisinde değişmez; ad değişikliği dosyayı taşımaz, geçmiş kayıtlar korunur.

- Hafta pazartesi–pazar, yıl 1 Ocak–31 Aralık takvim yılı, günlük dönem tek gündür. Desteklenen aralık kenarında dönem sınırları 0100-01-01 / 9999-12-31 ile kırpılır.
- `kind: milestone` yalnız `period: year` ile geçerlidir; `target` bulunmaz. Örneğin “Portfolyo sitesini bitir”. Tamamlandığı gün gün dosyasına `goals.<key>: true` bir kez yazılır; geri alma o kaydı kaldırır. İlerleme yapıldı/yapılmadı ve tamamlanma tarihidir; zincir ve ısı haritası yoktur. Hesaplama verilen güne kadarki, aynı yıl içindeki boolean true kayıtlarının ilk tarihini kullanır; yinelenen dış kayıtlar sayılmaz, false ve sayılar tamamlanma değildir. Uygulama aynı yıl içinde ikinci bir kayıt oluşturmaz; başka güne ait tamamlanmayı bugünkü kart geri almaz.
- Boolean/sayısal tanımlarda `period`: `day`/`week`/`year`; `kind`: `boolean`/`number`; `key` boş olmayan metin; `target` sonlu, sıfırdan büyük sayı. Geçersiz tanımlar korunur ama hesaplanabilir tanımlar listesine alınmaz. Boolean `true` katkısı 1, diğer boolean katkısı 0; sayı katkısı gün miktarıdır. Dönem toplamı ≥ `target` ise dönem başarılıdır. Haftalık boolean 3, haftada üç farklı gün; yıllık sayısal 24, yıl kayıtlarının toplamıdır.
- Zincir verilen günün döneminden geriye ardışık başarılı dönem sayısıdır. Güncel dönem henüz başarılı değilse önceki dönemden sayılır ve `isPendingToday` bayrağı döner (haftalık/yıllık hedeflerde güncel dönem bekliyor). Başarısız veya kayıtsız dönem zinciri keser. En uzun seri verilen güne kadarki tüm kayıtlardaki en uzun ardışık başarılı dönemdir.
- Isı haritası iki ucu dahil aralıktaki her gün için işaret verir: boolean `true` tam; `false`/eksik ve sayısal `0` yok; pozitif sayı `target` altında kısmi, eşit/üstünde tam. Haftalık/yıllık başarı ayrı dönem toplamıdır; harita günlük katkıyı gösterir. Açık harita aralığı gelecek kayıtlarını da gösterebilir. Yıl toplamı güncel yılın verilen güne kadarki katkılarıdır; yıllık ilerleme bu toplamı hedef miktarla karşılaştırır.

Zincir, en uzun seri ve ilerleme dosyada tutulmaz; gün dosyalarındaki kayıtlardan hesaplanır.

## Serbest notlar

`notes/` altındaki dosyalar herhangi bir yapıya uymak zorunda değildir. İçlerindeki bağlantılar ve görev satırları indekslenir.

## Ayarlar

`.app/` altında JSON dosyaları: görünüm tercihleri, kanban sütun düzeni gibi veri olmayan ayarlar. Obsidian nokta ile başlayan klasörleri göstermez.

`.app/vault.json` kasanın format sürümünü taşır:

```json
{ "formatVersion": 1 }
```

- Uygulama kasayı oluştururken yazar. Dosya yoksa sürüm 1 kabul edilir.
- Sürüm, eski bir istemcinin veriyi bozabileceği format değişikliklerinde artırılır.
- Desteklediğinden büyük bir sürüm gören istemci kasaya yazmaz; salt okunur açar ve güncelleme gerektiğini bildirir.

## Varlık tipleri

`.app/types.json` isteğe bağlıdır; yoksa yalnız yerleşik kişi/konum tipleri sunulur. Bu ek dosya kasa sürümünü değiştirmez; eski istemciler özel tip dosyalarını düz not olarak okuyabilir. Örnek:

```json
{
  "formatVersion": 1,
  "types": [{
    "id": "book", "folder": "books",
    "name": { "tr": "Kitap", "en": "Book" },
    "plural": { "tr": "Kitaplar", "en": "Books" },
    "icon": "book",
    "fields": [{ "key": "yazar", "kind": "text" }, { "key": "bitirme", "kind": "date" }],
    "template": "templates/book.md"
  }]
}
```

- `id` `[a-z][a-z0-9_-]*` biçiminde ve benzersizdir; `person`, `place`, `goal`, `journal`, indeksin iç türleri `day`/`note` ayrılmıştır. Düzenlemede id değişmez; yeni id yeni tiptir.
- `folder` kasa köküne göre göreli, boş olmayan dizin yoludur. Boş bileşen, `.`/`..`, noktayla başlayan bileşen, ters bölü ve kontrol karakterleri kabul edilmez; kökte `templates`, `conflicts`, `journal` hedef klasör olamaz. Sembolik bağlantılar izlenmez. Yeni dosya bu klasöre yazılır; mevcut dosyalar taşınmaz. Tür frontmatter `type: <id>` ile belirlenir.
- `name`/`plural` Türkçe ve İngilizce boş olmayan görünen adlardır. `icon` boş olmayan SF Symbol adıdır; tanınmayan simge arayüzde genel simgeyle gösterilebilir.
- `fields` sıralı, benzersiz anahtarlı arayüz tanımlarıdır; `kind` text/date/number/boolean/link olabilir. `type`, `name`, `qualifier`, `aliases` ve boş/geçersiz frontmatter anahtarları ayrılmıştır. Alan tanımı dosyada değer yaratmaz; boş/missing alan için uygun düzenleyici sunulur. Var olan değerin türü tanımla uyuşmazsa ham/mevcut alan düzenleyicisi kullanılır; kendiliğinden dönüşüm yapılmaz. Bilinmeyen alanlar korunur. `link` tek wikilink metnidir; kullanıcıya görünen hedef kayıtta `[[hedef]]` olarak yazılır.
- `template` isteğe bağlı, kasa köküne göre göreli `.md` yoludur; gizli bileşen, `.`/`..`, ters bölü, kontrol karakteri ve sembolik bağlantı kabul edilmez. Yeni dosyada şablonun gövdesi/diğer alanları korunur; `type` hedef id, `name` kullanıcının adı olur. Eksik şablonda asgari frontmatter üretilir. Okunamayan/çözülemeyen şablonla oluşturma reddedilir, şablon değiştirilmez.
- Bozuk/okunamayan, desteklenmeyen sürümlü veya çakışan tanımlı dosyada tüm özel tipler devre dışı kalır; yalnız yerleşik tipler ve kullanıcıya uyarı gösterilir. Özgün JSON üzerine sessizce yazılmaz. Tanımı silinen/eksik dosyalar düz not olarak kalır; dosyalar ve bağlantılar silinmez. `types.json` değişince indeks dosyalardan yeniden sınıflandırılır.
- Yeni tip oluşturma/düzenleme/silme yalnız hedef tip tanımını değiştirir. Diğer tipler ve bilinmeyen JSON anahtar/değerleri bayt düzeyinde korunur. Yazma atomiktir ve ortak kasa yazma kuyruğunda yapılır; tip silme varlık Markdown dosyalarına dokunmaz.

## Senkronizasyon çakışması

Aynı içeriğin iki sürümü iki yoldan oluşur:

- **Aynı dosya iki cihazda eşitlenmeden düzenlenir.** iCloud sürümlerden birini geçerli sayar, diğerini çakışan sürüm olarak saklar.
- **Aynı gün dosyası iki cihazda eşitlenmeden oluşturulur.** iCloud ikinci dosyayı adının sonuna sayı ekleyerek ayırır: `journal/2026-10-02 2.md`. Bu adı taşıyan dosya o günün kopyasıdır.

Uygulama iki sürümü tek içerikte birleştirir. Kopya dosya birleştirildikten sonra silinir; ana dosya yoksa kopya onun adını alır.

### Birleştirme işlevi

- Yalnızca iki sürümün içeriğine ve değişiklik zamanlarına bağlıdır; cihazın durumuna ya da indekse bağlı değildir. Değişiklik zamanı tam sayıdır; birimini çağıran belirler.
- Sürümlerin veriliş sırası sonucu değiştirmez. Sonuç, sürümlerin ikisinden de büyük bir zamanla (birleşmiş dosya sonradan yazılır) sürümlerden biriyle yeniden birleştirilirse içerik değişmez.
- Böylece iki cihaz aynı çakışmayı ayrı ayrı çözse de aynı içeriğe varır.
- **Yeni sürüm**, değişiklik zamanı daha büyük olandır; zamanlar eşitse içeriği bayt sırasında büyük olandır. Diğeri **eski sürüm**dür.
- Bayt bayt aynı iki sürümün sonucu kendileridir; kopya saklanmaz. Yalnızca satır sonu biçimi ya da baştaki BOM'u farklı sürümlerin sonucu yeni sürümdür; kopya saklanmaz.
- Sürümlerden biri salt okunursa (UTF-8 olarak çözülemiyorsa) birleştirme yapılmaz: sonuç yeni sürümdür, eski sürüm çakışma kopyası olarak saklanır.
- Birleşmiş dosyanın BOM'u ve yeni eklenen satırların satır sonu yeni sürümden alınır; iki sürümden aynen alınan satırlar kendi satır sonlarını korur. Tek istisna: CR ile biten bir satırın ardına gelen, LF ile biten boş satır CR ile sonlandırılır; yoksa iki bayt tek CRLF okunur ve boş satır kaybolurdu. Satırlar ve değerler eşleştirilirken satır sonu biçimi dikkate alınmaz.
- **Kayıp yok:** bir sürümdeki herhangi bir içerik (bir blok, boş olmayan bir serbest yazı satırı, bir frontmatter alanı) sonuçta yoksa o sürüm çakışma kopyası olarak saklanır. Tek istisnalar aşağıdaki kurallardır: kapalı görevin açık görevi yenmesindeki durum işareti ve tamamlanma tarihi farkı, iki kapalı görev arasındaki yalnız tamamlanma tarihi farkı, `goals` altında ilerleyen değerin alınması, yalnızca yazımı farklı frontmatter değerleri ve satır sonu biçimi. Denetim bölge bölge ve satır sayılarıyla yapılır: bir bölgedeki serbest yazı satırı ancak sonuçta aynı bölgenin serbest yazısında, en az o kadar sayıda bulunuyorsa var sayılır; frontmatter ya da blok satırı serbest yazı satırının yerine geçmez. İşlev sonucu vermeden önce onu yeniden okuyup bu koşulu ve yapının kurulduğu gibi okunduğunu (frontmatter sınırı, bölgeler, bloklar; örneğin bir sürümdeki kapanmayan kod çiti diğerinin satırlarını yutmamış) kendi üzerinde denetler; denetim tutmazsa birleştirme yapılmamış sayılır: sonuç yeni sürümdür, eski sürüm saklanır. Fazladan kopya zararsızdır, eksik kopya veri kaybıdır.

### Bölgeler

- Gövde (frontmatter'dan sonrası), kod çiti dışındaki birinci ve ikinci düzey başlıklarla bölgelere bölünür. Bölge, başlık satırından bir sonraki böyle başlığa kadar olan satırlardır. Bölgenin anahtarı başlık satırının içeriğidir (sondaki boşluklar hariç); ilk başlıktan önceki kısım başlıksız bölgedir ve her sürümde (boş da olsa) vardır.
- Aynı anahtar iki sürümde eşleşir; bir sürümde birden çok geçiyorsa sırasıyla eşleşir (birinci birinciyle).
- **Yalnızca bir sürümde olan bölge** bütünüyle sonuca eklenir. Tanınan bölümler (`## Tasks`, `## Events`, `## Journal` başlıklarının ilk geçenleri) bölüm açma kuralındaki yerine; diğerleri, kendi sürümünde kendisinden önce gelen ve sonuçta bulunan en yakın bölgenin ardına, öyle bir bölge yoksa sona. Eklenen bölgenin önüne, önceki satır boş değilse (frontmatter'ın kapanışı da olabilir), bir boş satır konur; ardından satır geliyorsa ve bölgenin son satırı boş değilse ardına da bir boş satır konur.
- **İki sürümde de olan bölge** içinde bloklar "Satırlar", serbest yazı "Serbest yazı" kurallarıyla birleşir. Düzen yeni sürümünkidir; serbest yazısı kapsayan taraf yalnızca eski sürümse o bölgede eski sürümün düzeni esas alınır (yeni sürümün bölge sonundaki boş satırı korunur). Yalnızca diğer sürümde bulunan olaylar olay ekleme kuralıyla (saati kendisinden büyük olan ilk saatli olayın önüne, öyle bir olay yoksa bölgenin sonuna; saatsiz olay sona), görevler kendi sıralarıyla bölgenin son boş olmayan satırının ardına eklenir. Mevcut satırların yeri değişmez.

### Satırlar

- **Blok**, girintisiz bir olay ya da görev satırı ve altındaki daha girintili satırlardır (bkz. Blok kimliği). Girintisiz bir bloğa ait olmayan girintili görevler, alıntı içindeki görevler ve kod çiti içindeki satırlar serbest yazıdır.
- Bloklar bölge içinde eşleştirilir; karşılaştırma satır içerikleriyle yapılır. Önce blok kimliğine göre: bir kimlik iki sürümden birinde birden fazla geçiyorsa o kimliği taşıyan bütün satırlar iki sürümde de kimliksiz sayılır. Kimliksiz bloklar, bütün satırlarının içeriği birebir aynıysa eşleşir; aynı blok bir sürümde k, diğerinde m kez geçiyorsa sırayla eşleşir ve sonuçta büyük olan sayı kadar bulunur.
- Aynı kimlik iki sürümde farklı türdeyse (olay, görev) ya da farklı bölgedeyse farklı satır sayılır: yeni sürümdeki alınır, eski sürümdeki alınmaz ve eski sürüm saklanır.
- Yalnızca bir sürümde olan blok sonuca eklenir. İki sürümde aynı olan blok tek kez, düzeni esas alınan sürümün satırlarıyla yazılır.
- Aynı kimlikli blok iki sürümde farklıysa:
  - Görevlerden biri kapalı (`x`, `-`), diğeri açıksa (` `, `/` ya da tanınmayan karakter) kapalı olan alınır.
  - Diğer durumlarda yeni sürümdeki alınır.
  - Bloğu alınmayan sürüm çakışma kopyası olarak saklanır; yalnız iki durumda saklanmaz: (a) kapalı görev açık görevi yenmiş ve normalize metinleri aynıdır; (b) ikisi de kapalı, durum karakterleri aynı (`X` ile `x` aynı) ve yalnız tamamlanma tarihi farklıdır. Normalize metin: ilk satırdan kutunun içindeki karakter ve ilk satırın sonunda (kimlikten önce) duran, önündeki tek boşlukla birlikte `✅ YYYY-MM-DD` yazımı çıkarılır; blokların diğer satırları aynen karşılaştırılır. Metnin ortasındaki `✅` tarihi metnin parçasıdır. `/` ile ` `, `x` ile `-` ve tanınmayan karakterler arasındaki fark, her metin farkı gibi, saklanmayı gerektirir. Olaylarda her fark saklanmayı gerektirir.

### Frontmatter

- Alanlar anahtar bazında birleştirilir; yorumlar ve boş satırlar yeni sürümün bloğundan gelir. Eski sürümün bloğundaki boş olmayan bir satır (yorum satırı ya da satır sonu yorumu taşıyan alan satırı) sonucun bloğunda birebir yoksa ve yorumu aynı alanın aynı anahtar parçalı (liste öğesinde aynı öğeli) satırında yeniden bulunmuyorsa eski sürüm saklanır; sonuçtaki her satır yalnız bir satırın yerine geçer. Anahtar sırası yeni sürümünkidir; yalnızca eski sürümde olan anahtarlar, eski sürümdeki sıralarıyla ve satırlarıyla aynen (ham alanlar dahil) kapanış satırının önüne eklenir. Yeni sürümde frontmatter yoksa dosyanın başına yeni blok açılır.
- Değerler anlamca karşılaştırılır: Yazma kurallarındaki "aynı değer" tanımına uyan değerler aynı sayılır (yalnızca yazımı farklı olanlar: tırnaklı ve tırnaksız metin, `+5` ile `5`, tek satırlı ve çok satırlı liste, tek değer ile tek öğeli liste). Eşlemler kayıt bazında, sıraya bakılmadan; ham alanlar ham metinleriyle karşılaştırılır.
- `goals` iki sürümde de eşlemse kayıtları da anahtar bazında birleştirilir; yalnızca eski sürümde olan kayıt, eski sürümdeki satırıyla (girintisi yeni sürümün eşlemine uydurularak) son kaydın ardına eklenir. Aynı kayıt iki sürümde farklıysa ilerleyen değer alınır: iki değer de sayıysa büyüğü (kazananın yazımıyla), ikisi de evet/hayırsa `true`. Türleri farklıysa ya da ikisi de başka türdense yeni sürümdeki değer alınır ve eski sürüm saklanır. `goals` iki sürümde de eşlem değilse sıradan anahtar gibi davranır.
- Başka bir anahtar iki sürümde farklıysa yeni sürümdeki değer alınır ve eski sürüm çakışma kopyası olarak saklanır.
- İki sürümden birinin bloğu çözülemiyorsa ve blokların satır içerikleri aynı değilse yeni sürümün bloğu aynen alınır ve eski sürüm saklanır. Birleştirilen blok yeniden okununca okunur değilse ya da beklenen alanları taşımıyorsa da öyle yapılır.

### Serbest yazı

Bölgede başlık satırı ve bloklar dışındaki her şey serbest yazıdır; bölge bölge karşılaştırılır. Satırlar içerikleriyle karşılaştırılır; boş satırlar sayılmaz (yalnızca boş satır farkı kopya gerektirmez).

- Bir sürümün yazısı diğerinin tüm satırlarını aynı sırayla içeriyorsa (diğeri yalnızca eksikse) kapsayan sürüm alınır.
- İki sürüm de farklı yönde değişmişse yeni sürümün yazısı alınır ve eski sürüm çakışma kopyası olarak saklanır.

### Çakışma kopyası

- Saklanacak sürüm (çoğunlukla eski sürüm; kapalı görev kuralında yeni sürüm de olabilir) bayt bayt aynen `conflicts/` klasörüne yazılır: `conflicts/2026-10-02 (conflict 20261002T110533Z).md`. Addaki zaman, o sürümün UTC değişiklik zamanıdır.
- `conflicts/` taranmaz: kopyalar indekslenmez, içlerindeki satırlar olay ya da görev sayılmaz.
- Uygulama kopyaları kullanıcıya gösterir; kullanıcı gerekeni ana dosyaya aldıktan sonra kopyayı siler.
- Birleştirilmiş içerik ve gerekiyorsa çakışma kopyası yazılmadan hiçbir sürüm silinmez. Hiçbir içerik sessizce kaybolmaz.

### Bilinen sonuçlar

İki sürümün ortak atası bilinmediği için silme ile ekleme, geri alma ile ilerleme birbirinden ayırt edilemez. Bu yüzden çakışma anında:

- Bir cihazda silinen satır geri gelebilir.
- Geri alınan bir işaret (yeniden açılan görev, kaldırılan hedef işareti, küçültülen sayı) eski haline dönebilir.
- Bir cihazda yeniden adlandırılan başlık iki bölge olarak geri gelir (eski ad, içindeki bloklar kimlikle eşleşirse boş kalır) ve diğer sürüm saklanır; aynı kimlikli blok farklı bölgelere taşındığında içerik aynı olsa da kopya saklanır. İkisi de kurala uygun, gürültülü sonuçlardır.

Gün dosyaları dışında iCloud'un ayırdığı kopyalar (`Elif 2.md` gibi) kendiliğinden birleştirilmez; kuralı aşama 1'de belirlenir.
