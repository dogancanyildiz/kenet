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
- Kasa uygulamanın kendi iCloud klasöründe durur. Mac'te Obsidian ile kasa olarak açılabilir.

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
- Bir varlığın adı değiştiğinde uygulama dosyayı yeniden adlandırır ve kasadaki tüm bağlantıları günceller.

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
| Tekrar (aşama 5) | `🔁 every week` |
| Proje | `#project/portfolyo` |

Örnek: `- [/] Portfolyo sitesini bitir 🛫 2026-10-05 📅 2026-10-20 #project/portfolyo ^z5n4r2`

- Çitli kod bloğu ve frontmatter içindeki satırlar olay ya da görev sayılmaz.
- Tanınmayan durum karakteri korunur ve açık görev sayılır; `[X]` bitti sayılır.
- Durum değiştirilirken yalnızca kutunun içindeki karakter değişir. Metin değiştirilirken girinti, liste işareti, kutu ve altındaki satırlar korunur.
- Yeniden okunduğunda istenenden farklı okunacak metin (saatsiz olayda saatle başlayan, olayda onay kutusuyla başlayan, kimlik gibi biten metin) yazılmaz; işlem reddedilir ve dosyaya dokunulmaz.
- Uygulamanın ayrıştırmadığı alanlar (tanımadığı emoji alanları dahil) metnin parçası olarak korunur.

**Tarihsiz görevler:** Bitiş tarihi olmayan görev, oluşturulduğu gün bugün ekranında görünür. Sonraki günlerde bugün ekranında yer almaz, "tarihsiz" listesinde durur.

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
- Bir ad ya da takma ad tek bir varlığa aitse otomatik bağlanır.
- Birden fazla varlığa aitse adaylar bağlama göre sıralanır: o konumda daha önce birlikte geçmiş olmak, yakın zamanda geçmiş olmak, geçme sıklığı. En olası aday üstte önerilir.
- Uygulama emin değilse bağlamaz, kullanıcıya sorar. Sıralama ölçütleri dosyada tutulmaz, indeksten hesaplanır.

## Konum dosyası

Yol: `places/Kadıköy Ofis.md`

```markdown
---
type: place
name: Kadıköy Ofis
aliases: [ofis]
coordinates: [40.9903, 29.0290]
radius: 100
---
```

- `coordinates` enlem ve boylam, `radius` metre. İkisi de isteğe bağlıdır; yoksa konum yalnızca adla eşleşir.

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
| `kind` | `boolean`, `number` | Kayıt türü |
| `target` | sayı | Dönem başına hedef (haftada 3 gün, yılda 24 kitap, günde 20 sayfa) |
| `unit` | metin, isteğe bağlı | Sayısal hedefte birim (sayfa, bardak) |
| `place` | bağlantı, isteğe bağlı | Aşama 4: konuma girince işaretleme |

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
