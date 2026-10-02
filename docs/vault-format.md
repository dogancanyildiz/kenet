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
- Şunlar taranmaz; içlerindeki dosyalar varlık sayılmaz ve indekslenmez: adı nokta ile başlayan klasörler (`.app/`, `.obsidian/`, `.trash/`), `templates/` ve `conflicts/`.
- Kullanıcının açtığı diğer klasörler ve alt klasörler taranır.
- İndeks veritabanı kasanın içinde durmaz.

## Adlar ve karşılaştırma

- Dosya adları ve adlarla yapılan tüm karşılaştırmalar Unicode NFC'ye normalleştirilir (macOS ve iCloud dosya adlarını farklı biçimde döndürebilir; Türkçe karakterlerde eşleşme hatasına yol açar).
- Karşılaştırma büyük/küçük harfe duyarsızdır ve cihazın dilinden bağımsızdır: iki ad NFC'ye çevrildikten sonra Unicode'un varsayılan (yerelden bağımsız) küçük harf eşlemesiyle karşılaştırılır. Mac dosya sistemi ve Obsidian büyük/küçük harfe duyarsız, iPhone dosya sistemi duyarlıdır; bu yüzden kural dosya sistemine bırakılmaz.
- Türkçeye özel eşleme uygulanmaz: `I` ile `i` aynı, `İ` ile `i` ve `I` ile `ı` farklı harflerdir. Örneğin `Işık` ile `işık` aynı ad, `ışık` ise ayrı bir ad sayılır. Uygulamanın yazdığı bağlantılar dosya adını birebir taşıdığı için bu kural yalnızca elle yazılan bağlantıları etkiler.
- Dosya adları (uzantısız) kasa genelinde benzersizdir. Uygulama kendi oluşturduğu dosyalarda bunu sağlar.
- Aynı ad dışarıdan iki dosyaya verilmişse bağlantı, kasa köküne göre yolu kod noktası sırasında önce gelen dosyaya gider; uygulama durumu kullanıcıya bildirir.
- Dosya adında şu karakterler bulunamaz: `/ \ : * ? " < > |` ve bağlantı sözdizimini bozan `# ^ [ ]`. Görünen ad bu karakterleri içeriyorsa `name` alanında aynen durur; uygulama dosya adını üretirken onları atar.

## Frontmatter

Dosyanın ilk satırı (varsa BOM'dan sonra) `---` ise frontmatter başlar ve sonraki ilk `---` satırında biter. Kapanış satırı yoksa dosyada frontmatter yok sayılır.

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
goals:                        # tek düzey iç içe eşlem
  spor: true                  # evet/hayır
  kitap: 25
```

- Anahtar satır başında yazılır; boşluk ve Türkçe karakter içerebilir (`doğum günü`). Anahtarlar birebir karşılaştırılır.
- Yorumlar (`#`) ve boş satırlar korunur.
- İki liste biçimi eşdeğerdir; Obsidian bir özelliği düzenlediğinde listeyi çok satırlı biçimde yeniden yazar. Liste beklenen alandaki tek değer, tek öğeli liste sayılır.
- Aynı anahtar iki kez geçerse ilki geçerlidir.

Alt kümenin dışında kalan yapılar (çok satırlı metin blokları, çapa ve takma ad, daha derin iç içelik):

- Yalnızca kendi anahtarını etkiler: o alan ham metin olarak gösterilir ve uygulama onu değiştirmez. Diğer alanlar okunur ve düzenlenir.
- Frontmatter'ın bütünü çözülemiyorsa (satır başında anahtar olmayan içerik gibi) frontmatter yok sayılır: `type` okunmaz, uygulama frontmatter'a yazmaz.

Yazma kuralları:

- Bir alan değişirken yalnızca o anahtarın satırları yeniden yazılır. Diğer satırlar, sıraları, tırnak biçimleri ve yorumlar korunur; değerler yeniden üretilmez (`29.0290`, `29.029` olmaz).
- Değişen listenin mevcut biçimi (tek satırlı ya da çok satırlı) korunur.
- Yeni anahtar frontmatter'ın sonuna eklenir. Uygulama yeni listeyi tek satırlı yazar.
- Düz yazıldığında YAML'da başka anlama gelecek metin çift tırnak içinde yazılır.
- Frontmatter'ı olmayan dosyaya alan yazılacaksa dosyanın başına yeni bir frontmatter bloğu eklenir.

## Bağlantılar

- Varlığa bağlantı: `[[Ahmet Yılmaz]]`
- Metinde takma ad geçiyorsa görünen metin korunur: `[[Ahmet Yılmaz|Ahmet abi]]`
- Arayüzdeki `@` ile seçim dosyaya wikilink olarak yazılır; `@` işareti dosyada yer almaz.
- Bir varlığın adı değiştiğinde uygulama dosyayı yeniden adlandırır ve kasadaki tüm bağlantıları günceller.

Sözdizimi: `[[hedef]]`, `[[hedef|görünen metin]]`, `[[hedef#çapa]]`, `[[hedef#çapa|görünen metin]]`.

- Hedef, ilk `#` ya da `|` karakterine kadar olan kısımdır; baştaki ve sondaki boşluklar atılır. Hedef uzantısız dosya adıdır; sondaki `.md` yok sayılır. `/` içeren hedef kasa köküne göre yoldur.
- Çapa bir başlık ya da `^` ile başlayan blok kimliğidir. Yeniden adlandırmada yalnızca hedef değişir; çapa ve görünen metin korunur.
- Hedefi boş olan bağlantı (`[[#Başlık]]`) aynı dosyanın içine gider; varlık bağlantısı değildir.
- Gömme (`![[hedef]]`) aynı kurallarla bağlantı sayılır.
- Bağlantı tek satırdadır ve içinde `[[` ya da `]]` bulunmaz.
- Çitli kod bloğu (```` ``` ```` ya da `~~~` ile açılan) ve satır içi kod içindeki `[[...]]` bağlantı sayılmaz.
- Hedefi kasada bulunmayan bağlantı geçerlidir ve korunur. Taranmayan klasörlerdeki dosyalar hedef olamaz.
- Markdown biçimli bağlantılar (`[metin](dosya.md)`) korunur ama varlık bağlantısı sayılmaz ve yeniden adlandırmada güncellenmez.

## Blok kimliği

- Uygulamanın ürettiği her olay ve görev satırı sonunda bir kimlik taşır: `^a1b2c3`
- Biçim: satırın sonunda, bir boşluktan sonra `^` ve ardından 6 karakter (küçük harf `a-z` ve rakam).
- Kimlik opaktır: tür ya da başka anlam taşıyan bir önek içermez. Satırın olay mı görev mi olduğunu kimlik değil satırın yazımı belirler.
- Uygulama kimliği rastgele üretir ve kasadaki mevcut kimliklerle çakışmadığını denetler. Satır düzenlense de kimlik değişmez.
- Kimliği olmayan (elle ya da Obsidian'da yazılmış) satıra, uygulama o satırı ilk kez değiştirdiğinde kimlik eklenir.
- Okurken Obsidian'ın kabul ettiği her kimlik (harf, rakam ve `-`, herhangi bir uzunlukta) tanınır ve değiştirilmez.
- Kimliğin kasa genelinde benzersiz olması amaçlanır ama garanti değildir: dışarıda yapılan kopyalama aynı kimliği çoğaltabilir. Bu durumda kimliğin sahibi ilk geçen satırdır (dosya yolu sırası, sonra dosya içi sıra). Diğer satırlar kendiliğinden değiştirilmez; uygulama onlardan birini değiştirdiğinde o satıra yeni kimlik verir.
- Bir olay ya da görev satırının altındaki girintili satırlar (alt madde, devam satırı) o satırın parçasıdır: onunla birlikte taşınır, birleştirilir ve silinir. Uygulama bu satırları üretmez, yalnızca korur.

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

- Bölüm başlığı tam olarak `## Tasks`, `## Events` ya da `## Journal` satırıdır (sondaki boşluklar yok sayılır). Bölüm, aynı ya da daha üst düzeydeki bir sonraki başlığa kadar sürer.
- Aynı başlık birden fazla geçerse ilki geçerlidir.
- Tanınmayan başlıklar ve ilk başlıktan önceki içerik korunur, düz metin olarak gösterilir.
- Bölümler ilk ihtiyaç duyulduğunda oluşturulur. Boş bölüm yazılmaz; içi sonradan boşalan bölümün başlığı silinmez.
- Yeni bölüm Tasks, Events, Journal sırasındaki yerine açılır: bu sırada kendinden sonra gelen ilk mevcut bölümün önüne, öyle bir bölüm yoksa dosyanın sonuna. Öncesinde bir boş satır bırakılır.
- Bölümün sonuna eklenen satır, bölümdeki son boş olmayan satırın ardına yazılır.

### Olay satırı

- Events bölümündeki, girintisiz `- ` ile başlayan ve görev olmayan her liste satırı bir olaydır. Okurken `* ` ve `+ ` liste işaretleri de kabul edilir.
- Saatli: `- HH:MM metin ^kimlik` (24 saat, iki haneli). Okurken tek haneli saat (`9:05`) de kabul edilir ve olduğu gibi korunur.
- Saatsiz: `- metin ^kimlik` (saat isteğe bağlıdır)
- Saat, olayın yazıldığı yerin yerel saatidir; saat dilimi tutulmaz.
- Geçmiş bir güne sonradan olay eklenebilir; satır o günün dosyasına yazılır.
- Saatli olay, saati kendisinden büyük olan ilk saatli olayın önüne eklenir; öyle bir olay yoksa bölümün sonuna. Saatsiz olay bölümün sonuna eklenir. Mevcut satırların yeri değişmez.
- Olayın saati değiştirilirse satır aynı kuralla yeni yerine taşınır.
- Gösterim sırası dosyadaki sıradır.

## Görev satırı

Obsidian Tasks biçimi. Onay kutusu taşıyan her liste satırı görevdir; hangi dosyada ya da bölümde durduğu fark etmez. Girintili görev satırı (alt görev) de görevdir. Okurken `* ` ve `+ ` liste işaretleri de kabul edilir.

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

- Tanınmayan durum karakteri korunur ve açık görev sayılır; `[X]` bitti sayılır.
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
- `name` alanı yoksa görünen ad dosya adıdır.
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

- Yalnızca iki sürümün içeriğine ve değişiklik zamanlarına bağlıdır; cihazın durumuna ya da indekse bağlı değildir.
- Sürümlerin veriliş sırası sonucu değiştirmez. Sonucu sürümlerden biriyle yeniden birleştirmek de değiştirmez.
- Böylece iki cihaz aynı çakışmayı ayrı ayrı çözse de aynı içeriğe varır.
- **Yeni sürüm**, değişiklik zamanı daha büyük olandır; zamanlar eşitse içeriği bayt sırasında büyük olandır.
- Birleşmiş dosyanın BOM'u ve yeni eklenen satırların satır sonu yeni sürümden alınır; iki sürümden aynen alınan satırlar kendi satır sonlarını korur. Satırlar eşleştirilirken satır sonu biçimi dikkate alınmaz.

### Satırlar

- Olay ve görev satırları blok kimliğine göre eşleştirilir. Kimliği olmayan ya da kimliği aynı sürümde birden fazla geçen satırlar, metinleri birebir aynıysa eşleşir.
- Eşleştirme girintisiz satırlar üzerinden yapılır; altındaki girintili satırlar o satırla birlikte tek blok sayılır.
- Yalnızca bir sürümde olan satır sonuca eklenir. İki sürümde aynı olan satır tek kez yazılır.
- Aynı kimlikli satır iki sürümde farklıysa:
  - Görevlerden biri kapalı (`x`, `-`), diğeri açıksa kapalı olan alınır.
  - Diğer durumlarda yeni sürümdeki satır alınır.
  - İki satır arasında durum işareti ve tamamlanma tarihi (`✅`) dışında bir fark varsa, satırı alınmayan sürüm çakışma kopyası olarak saklanır.

### Frontmatter

- Alanlar anahtar bazında birleştirilir; `goals` altındaki kayıtlar da öyle. Yalnızca bir sürümde olan anahtar sonuca eklenir.
- Değerler anlamca karşılaştırılır: yalnızca yazımı farklı olan değerler (tek satırlı ve çok satırlı liste gibi) aynı sayılır.
- Aynı `goals` anahtarı iki sürümde farklıysa ilerleyen değer alınır: `false` karşısında `true`, küçük sayı karşısında büyük sayı. Türleri farklıysa yeni sürümdeki değer alınır.
- Başka bir anahtar iki sürümde farklıysa yeni sürümdeki değer alınır ve diğer sürüm çakışma kopyası olarak saklanır.

### Serbest yazı

Frontmatter ile olay ve görev satırları dışındaki her şey serbest yazıdır; bölüm bölüm karşılaştırılır.

- Bir sürümün yazısı diğerinin tüm satırlarını aynı sırayla içeriyorsa (diğeri yalnızca eksikse) kapsayan sürüm alınır.
- İki sürüm de farklı yönde değişmişse yeni sürümün yazısı alınır ve diğer sürüm çakışma kopyası olarak saklanır.

### Sıra

Sonuçta yeni sürümün düzeni esas alınır. Yalnızca diğer sürümde bulunan olaylar olay ekleme kuralıyla yerleştirilir; görevler, kendi aralarındaki sırayla, bulundukları bölümün (bölüm yoksa dosyanın) sonuna eklenir.

### Çakışma kopyası

- Kaybeden sürüm bayt bayt aynen `conflicts/` klasörüne yazılır: `conflicts/2026-10-02 (conflict 20261002T110533Z).md`. Addaki zaman, o sürümün UTC değişiklik zamanıdır.
- `conflicts/` taranmaz: kopyalar indekslenmez, içlerindeki satırlar olay ya da görev sayılmaz.
- Uygulama kopyaları kullanıcıya gösterir; kullanıcı gerekeni ana dosyaya aldıktan sonra kopyayı siler.
- Birleştirilmiş içerik ve gerekiyorsa çakışma kopyası yazılmadan hiçbir sürüm silinmez. Hiçbir içerik sessizce kaybolmaz.

### Bilinen sonuçlar

İki sürümün ortak atası bilinmediği için silme ile ekleme, geri alma ile ilerleme birbirinden ayırt edilemez. Bu yüzden çakışma anında:

- Bir cihazda silinen satır geri gelebilir.
- Geri alınan bir işaret (yeniden açılan görev, kaldırılan hedef işareti, küçültülen sayı) eski haline dönebilir.

Gün dosyaları dışında iCloud'un ayırdığı kopyalar (`Elif 2.md` gibi) kendiliğinden birleştirilmez; kuralı aşama 1'de belirlenir.
