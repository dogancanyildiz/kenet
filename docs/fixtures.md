# Fixtures

`Fixtures/` klasörü kasa formatının sözleşme testleridir: örnek Markdown dosyaları ve (ilgili kategorilerde) beklenen çıktılar. Dosyalar dilden bağımsızdır; bugün Swift testleri okur, ileride başka platformlardaki istemciler de aynı dosyalarla sınanır. Formatın kendisi `vault-format.md` belgesindedir.

## Kurallar

- **Bayt düzeyinde korunur.** `.gitattributes` içindeki `Fixtures/** -text` satırı git'in satır sonu dönüşümünü kapatır. Satır sonu, BOM ya da geçersiz bayt taşıyan dosyalar editörle değil `printf` ile oluşturulur ve `xxd` ile doğrulanır. Testler bu özellikleri ham baytlardan ayrıca denetler; bir araç dosyayı dönüştürürse test kırmızıya döner.
- **İçerik kurgusaldır.** Repo herkese açıktır; gerçek kişi, konum ya da günlük verisi girmez. Yalnızca aşağıdaki adlar kullanılır.
- **İçine belge konmaz.** Klasörde README ya da açıklama dosyası bulunmaz; her `.md` dosyası test verisidir. Açıklamalar bu belgeye yazılır.
- `Vault` ya da `vault` adında klasör açılmaz; `.gitignore` bu adları her derinlikte dışarıda bırakır.

## Kurgusal adlar

| Tür | Adlar |
|---|---|
| Kişi | Deniz Arıkan, Selin Korkmaz, Baran Tunç, Ece Yalın, Mert Aksu |
| Konum | Çınaraltı Kafe, Liman Ofis, Tepe Spor Salonu, Ev |
| Hedef | Spor, Kitap, Su |
| Emoji örneği | Ev 🏠 |

Yeni ad gerekirse önce bu tabloya eklenir.

## Kategoriler

### `roundtrip/`

İçindeki her dosya okunup hiçbir değişiklik yapılmadan yazıldığında bayt bayt aynı kalmalıdır. Beklenen çıktı dosyanın kendisidir; ayrı bir çıktı dosyası yoktur. Testler `Fixtures/` altındaki bütün `.md` dosyalarını (diğer kategorilerdekiler dahil) bu denetimden geçirir, bu yüzden yeni dosya eklemek için kod değiştirmek gerekmez. Aynı testler her dosyanın türetilmiş hallerini de dener: bütün satır sonları LF'ye, CRLF'ye ya da CR'ye çevrilmiş, başına BOM eklenmiş, son satır sonu atılmış ve her bayt konumunda kesilmiş.

Bu kategoriye, korunması gereken bir bayt özelliğini taşıyan dosyalar konur:

| Dosya | Özellik |
|---|---|
| `day-basic.md` | Olağan gün dosyası: UTF-8, LF, yeni satırla biter |
| `crlf.md` | Bütün satır sonları CRLF |
| `cr.md` | Bütün satır sonları tek CR |
| `bom.md` | Başta UTF-8 BOM |
| `no-final-newline.md` | Son satır yeni satırla bitmez |
| `mixed-line-endings.md` | LF, CRLF ve CR karışık; her biçimden boş satır da var |
| `empty.md` | Sıfır bayt |
| `invalid-utf8.md` | UTF-8 olarak çözülemeyen baytlar |

### `parse/`

Okuma örnekleri. Her örnek bir klasördür: `input.md` okunur, sonuç `expected.json` ile karşılaştırılır. Yeni örnek eklemek için klasör açmak yeter.

`expected.json` kökünde her konu kendi anahtarını taşır; `frontmatter`, `sections`, `tasks`, `events` ve `links` vardır. İstemci yalnızca dosyada bulunan anahtarları karşılaştırır; karşılaştırma katıdır (fazla ya da eksik alan hatadır, metinler bayt bayt karşılaştırılır). Satır numaraları 1'den başlar; BOM satır sayılmaz.

```json
{
  "frontmatter": {
    "state": "parsed",
    "firstLine": 1,
    "lastLine": 3,
    "fields": [
      { "key": "name", "firstLine": 2, "lastLine": 2,
        "scalar": { "type": "text", "text": "Deniz Arıkan", "raw": "\"Deniz Arıkan\"" },
        "listItems": ["Deniz Arıkan"] }
    ]
  }
}
```

- `state`: `parsed`, `absent` (frontmatter yok) ya da `unreadable` (bütünü çözülemiyor). Son ikisinde başka alan bulunmaz. Hangi bloğun hangi durumda olduğu `vault-format.md` "Frontmatter" bölümündedir.
- `firstLine`, `lastLine`: blokta açılış ve kapanış `---` satırları; alanda anahtar satırı ile alanın boş ya da yorum olmayan son satırı.
- Her alan `scalar`, `list`, `mapping`, `raw` anahtarlarından tam birini taşır:
  - `scalar`: `type` (`text`, `number`, `boolean`, `date`, `empty`), `text` (tırnağı ve kaçışı çözülmüş metin) ve `raw` (dosyadaki yazım, tırnaklar dahil). Türlerin yazımı `vault-format.md` "Türler" başlığındadır.
  - `list`: `style` (`inline` ya da `block`) ve `items` (her biri bir `scalar`).
  - `mapping`: sırayla `key`, `line` ve `value` (bir `scalar`) taşıyan kayıtlar.
  - `raw`: alt küme dışı alanın ham metni: anahtar satırında anahtardan sonra gelen kısım, ardından alanın kalan satırları, LF ile birleştirilmiş.
- `listItems`: alanın liste olarak görünümü (öğelerin `text` değerleri); tek değer tek öğeli, boş değer boş listedir. `mapping` ve `raw` alanlarında bulunmaz.
- `fields` dosya sırasındadır.

`parse/section-<ad>/expected.json` kökündeki `sections`, `preamble` (ön içerik) ve dosya sırasındaki `items` listesini taşır. Her aralık `firstLine` ve `lastLine` ile 1 tabanlı, iki ucu dahil yazılır; boş ön içerik `null` olur. Her öğe `kind` (`Tasks`, `Events`, `Journal` ya da tanınmayan/yinelenen başlık için `null`), `headingLine`, `level`, `firstLine`, `lastLine` taşır. Aralık başlığı ve sondaki boş satırları içerir. İç başlıklar ayrı öğe değildir. Örnek: `{ "sections": { "preamble": null, "items": [{ "kind": "Tasks", "headingLine": 1, "level": 2, "firstLine": 1, "lastLine": 2 }] } }`.

`parse/line-<ad>/expected.json` kökündeki `tasks` ve `events` dosya sırasındaki listelerdir. Her öğe `line` (ilk satır), `firstLine`, `lastLine` (iki ucu dahil blok aralığı), `id` (şapkasız kimlik veya `null`) ve `text` taşır. Aralık ilk satırdan daha girintili devamları ve aralarında kalan boş satırları içerir; sondaki boş satırları içermez. İç içe görevlerin aralıkları örtüşebilir; kardeş görevler birbirinin aralığına girmez. Girinti yalnızca satır başındaki boşluk ve sekmelerle ölçülür: boşluk bir sütun, sekme bir sonraki dördün katına ilerler; `>` girinti sayılmaz. Alıntı içindeki görevler tek satırlık bloklardır. Metin yalnızca ilk satırdan gelir: görevde kutuya kadar olan liste/alıntı sözdizimi, olayda liste işareti ve ardından gelen boşluk ve sekmeler çıkarılır; kutu ve saat sonrasındaki tek ayırıcı boşluk da çıkarılır. Diğer boşluklar, emoji alanları, Türkçe karakterler ve bağlantılar aynen kalır. Kimlik önündeki tek boşluk ve kimlik sonrasındaki boşluk/sekme çıkarılır; kimlik yoksa sondaki boşluklar da metinde kalır.

Görev ayrıca `rawStatus` (tek Unicode skaleri), `status` (`todo`, `inProgress`, `done`, `cancelled`, `unknown`), `isClosed` ve `isOpen` taşır. Olay ayrıca `time` taşır: `null` veya `{ "hour": 9, "minute": 5, "raw": "9:05" }`. Kimlik uzunluğu ve yinelenmesi korunur. Örnek: `{ "tasks": [{ "line": 1, "firstLine": 1, "lastLine": 1, "id": null, "text": "kitap", "rawStatus": " ", "status": "todo", "isClosed": false, "isOpen": true }], "events": [] }`.

`parse/link-<ad>/expected.json` kökündeki `links`, fiziksel dosya sırasındaki bağlantı listesidir. `line` 1 tabanlıdır. `byteRange` ve `targetRange`, satır içeriğinin UTF-8 baytlarında 0 tabanlı, başlangıcı dahil sonu hariç `[başlangıç, son]` çiftleridir; BOM ve satır sonu sayılmaz. Bağlantı aralığı `[[` ile `]]` dahil yazımı kapsar, gömmenin `!` işaretini kapsamaz. Hedef aralığı çevresindeki Unicode boşlukları ve `\|` ayırıcısının ters bölüsü hariç, `.md` dahil özgün hedef yazımını kapsar; boş hedefte iki uç eşittir.

Her öğe `target` (çözülmüş, çevresindeki Unicode boşlukları ve tam `.md` soneki atılmış hedef), `rawTarget` (hedef aralığındaki özgün kaynak yazımı), `anchor` (`null` veya `{ "kind": "heading"|"block", "text": "..." }`; hash ve blok şapkası hariç), `displayText` (`null` veya ilk borudan sonraki metin), `isEmbedded`, `isSameFile`, `isPath` ve `source` taşır. Kaynak `{ "kind": "body" }` veya `{ "kind": "frontmatter", "key": "...", "entry": null|"..." }` biçimindedir; `entry` yalnızca eşlem kaydında doludur. Çapa ve görünen metin kırpılmaz, boş ama yazılmış değer boş metin olarak korunur.

Frontmatter'da tarama çözülmüş metinde yapılır; aralıklar fiziksel YAML satırına geri eşlenir. Bir kaçışın ürettiği baytlar kaçışın tamamını kapsar; `rawTarget` kaçışları korur. Kaçışla yazılmış ayraçlarda bağlantı aralığının fiziksel uçları da kaçış yazımıdır. Çözülmüş satır sonları bağlantıyı böler. Kod, kaçış ve gömme tanıması çözülmüş metinde uygulanır; ham alanlar, anahtarlar ve yorumlar taranmaz. Yinelenen hedefler ayrı öğelerdir. `links: []` hiç bağlantı olmadığını denetler.

### `write/`

Yazma örnekleri. Her örnek bir klasördür: `input.md` üzerine `operation.json` içindeki işlem uygulanır, sonuç `expected.md` ile bayt bayt karşılaştırılır. Reddedilmesi gereken işlemlerde `expected.md` bulunmaz; `operation.json` içindeki `expectedError` beklenen hatayı adlandırır ve dosyaya dokunulmaz.

```json
{
  "frontmatter": { "operation": "set-entry", "key": "goals", "entry": "kitap", "value": { "integer": 30 } }
}
```

| `operation` | Alanlar | İşlem |
|---|---|---|
| `set-value` | `key`, `value` | Alana tek değer yazar |
| `set-list` | `key`, `items` | Alana liste yazar |
| `set-entry` | `key`, `entry`, `value` | `key` altındaki eşlemde `entry` kaydını yazar |
| `remove-entry` | `key`, `entry` | Eşlemden kaydı siler |
| `remove-field` | `key` | Alanı siler |

- Değer, türünü adlandıran tek anahtarlı nesnedir: `{ "text": "..." }`, `{ "boolean": true }`, `{ "integer": 25 }`, `{ "number": "20.029" }`, `{ "date": "2026-10-02" }`. `number` yazılacak yazımı metin olarak taşır; böylece beklenen çıktı bir dilin ondalık sayı biçimlendirmesine bağlı kalmaz.
- Beklenen çıktının her baytı `vault-format.md` içindeki "Tırnaklama" ve "Yazma kuralları" başlıklarından türetilebilir.
- `expectedError` değerleri: `read-only-document` (dosya UTF-8 değil), `unreadable-frontmatter`, `raw-field` (ham alan), `not-a-mapping` (değeri olan alana kayıt yazma), `invalid-key` (boş anahtar ya da `<<`), `invalid-value` (sayı yazımına uymayan `number`).
- Kök anahtar işlemin hedefini söyler (`frontmatter` ya da `sections`); diğer işlemler geldikçe yeni kök anahtarlar eklenir.

`write/section-journal-<ad>/operation.json` kökündeki `sections`, `{ "operation": "replace-journal", "text": "..." }` biçimiyle günlük yazısının tamamını değiştirir. Mevcut bölümde boş metin başlığı ve sondaki boş satırları korur. Bölüm yokken boş ya da yalnız boşluklardan oluşan metnin beklenen çıktısı girdinin aynısıdır (değişiklik yok); gövdedeki `---` başarı örneğidir. Beklenen baytlar ve yapı kısıtlarından doğan hatalar aynı şekilde denetlenir; aynı metinle ikinci uygulamanın ilk uygulamayla bayt bayt aynı kaldığı da doğrulanır.

`write/section-<ad>/operation.json` kökündeki `sections`, `{ "operation": "append", "kind": "Tasks", "lines": ["- [ ] kitap"] }` biçimindedir. En az bir boş olmayan satır gerekir. Hatalar: `section-not-writable`, `empty-section-append`, `line-break-in-content`, `read-only-document`. Beklenen çıktı bağımsız yazılır; test baytları ve yeniden okunan modeli karşılaştırır. Ekleme tekrarlandığında yeni satırlar tekrar eklenir; frontmatter işlemlerindeki eşgüçlülük denetimi burada uygulanmaz.

`write/line-<ad>/operation.json` kökündeki `lines` tek bir işlemdir. `operation`: `add-event` (`text`, `id`, isteğe bağlı `time`), `add-task` (`text`, `id`), `text` (`line`, `text`, isteğe bağlı `id`), `status` (`line`, `status`, isteğe bağlı `id`), `time` (`line`, `time`, isteğe bağlı `id`) ya da `delete` (`line`). `line` hedef bloğun 1 tabanlı ilk satırıdır. `time`, `null` ya da `{ "hour": 9, "minute": 5 }`; `status`, `todo`, `inProgress`, `done`, `cancelled` biçimindedir (`unknown` reddetme örneğinde kullanılır). Düzenlemedeki `id` yeni kimliktir; yoksa özgün kimlik yazımı korunur. `stale-delete` ve `stale-text`, `replacement` içindeki Markdown belgeye eski bloğu uygulamayı dener; `wrong-status` ve `wrong-time`, yanlış türden hedefi sınar. `stale`, hedef okunduktan sonra metni `Su` yapan ve eski hedefle tekrar düzenlemeyi deneyen test işlemidir. Ek hatalar: `target-not-found`, `empty-text`, `content-not-representable`, `identifier-exhausted` (kimlik üreticisinin deneme sınırı doldu); `invalid-value`, `line-break-in-content`, `read-only-document`, `section-not-writable` da kullanılabilir. Başarıda beklenen baytlar ve yeniden okunan model, ayrıca hedef dışında kalan satırların baytları denetlenir.

İstemci her frontmatter yazma örneğinde şunları da denetler: frontmatter dışındaki baytlar değişmez, frontmatter içinde yalnızca hedef anahtarın satırları değişir, yazılan değer yeniden okununca aynı değeri verir, işlem ikinci kez uygulanınca dosya değişmez.

### Başka okuyucularla karşılaştırma

Uygulamanın okuyucusu ve yazıcısı aynı kuralları paylaşır; ikisinde birden yanlış olan bir kural kendi testlerinden geçer. `.github/scripts/check-frontmatter-yaml.rb` geliştirici betiği `parse/` beklentilerini ve `write/` çıktılarını Ruby Psych (YAML 1.1) ve istenirse js-yaml (YAML 1.2, Obsidian'ın okuyucusu) ile karşılaştırır; testlerin rastgele ürettiği blokları da aynı okuyuculara gösterebilir. Betik CI'da çalışmaz; frontmatter kuralları ya da örnekler değiştiğinde elle çalıştırılır. Kullanımı betiğin başında yazılıdır.

### Adlandırma

`parse/` ve `write/` klasör adları taşıdıkları bayt özelliğini söyler ve testler bunu ham baytlardan denetler: adında `crlf`, `cr`, `bom` sözcüğü ya da `mixed-line-endings`, `no-final-newline`, `invalid-utf8`, `read-only`, `exact-key-match` geçen örneğin Markdown dosyaları o özelliği taşımak zorundadır.

### `vaults/sample`

Kasa formatının ve istemci uygulamaların (ayrıştırıcı, modeller, indeksleyici, Obsidian uyumluluğu, arayüz, arama) uçtan uca test edilmesi için kullanılan tam ve tutarlı kurgusal örnek kasa. `Fixtures/vaults/sample/` altında yer alır:

- `journal/`: 2026-09-14 ile 2026-09-27 arası 14 gün dosyası; toplam 40 olay ve 22 görev.
- `people/`: 6 kişi dosyası.
- `places/`: 4 konum dosyası.
- `goals/`: 3 hedef tanımı (`Spor.md`, `Kitap.md`, `Su.md`).
- `notes/`: 3 serbest not (`Proje Fikirleri.md`, `Okuma Listesi.md`, `Toplantı Notları.md`).
- `templates/`: `person.md` ve `place.md` şablonları.
- `conflicts/`: 1 senkronizasyon çakışması kopyası.
- `.app/`: `vault.json` (format sürümü).

#### Kurgusal kadro

- **Kişiler:** Deniz Arıkan (takma adlar: Deniz, Deniz abi), Selin Korkmaz (takma ad: Selin), Baran Tunç (takma ad: Baran), Ece Yalın (takma ad: Ece), Mert Aksu ve ikinci bir Mert Aksu (iş ayırt edicili).
- **Konumlar:** Liman Ofis (takma ad: ofis, koordinat: `[10.5000, 20.0290]`, yarıçap: 100), Çınaraltı Kafe, Tepe Spor Salonu (takma ad: salon, koordinat: `[10.5210, 20.0415]`, yarıçap: 80), Ev.
- **Hedefler:** Spor (`spor`, haftada 3 gün, boolean, konum: Tepe Spor Salonu), Kitap (`kitap`, günde 20, sayı, birim: sayfa), Su (`su`, günde 8, sayı, birim: bardak).

#### Bilerek konmuş özel durumlar

1. **Aynı adlı iki kişi:** `people/Mert Aksu.md` ve ayırt edicili `people/Mert Aksu (iş).md` (`qualifier: iş`). Bağlantılarda `[[Mert Aksu]]` ve `[[Mert Aksu (iş)|Mert]]` olarak kullanılır.
2. **Var olmayan hedefe bağlantı:** `journal/2026-09-18.md` içinde `[[Henüz Yazılmamış Not]]` bağlantısı (kasada hedef dosyası bulunmayan tek bağlantı).
3. **Frontmatter'sız not:** `notes/Proje Fikirleri.md` dosyası frontmatter taşımaz ve içinde elle yazılmış gibi blok kimliği bulunmayan görev satırları (`- [ ]`) ile bağlantılar içerir; toplam 2 kimliksiz görev vardır.
4. **Kod bloğu içindeki bağlantı ve başlık:** `notes/Toplantı Notları.md` içinde çitli kod bloğunda `[[Deniz Arıkan]]` ve `## Events` yer alır; bunlar ayrıştırıcı tarafından varlık bağlantısı ya da bölüm başlığı sayılmamalıdır.
5. **Çakışma kopyası:** `conflicts/2026-09-20 (conflict 20260920T183000Z).md`, `journal/2026-09-20.md` dosyasının bir olay metni farklı sürümüdür; taranmayan klasörler kuralı gereği indekslenmez.
6. **Çok satırlı `aliases`:** `people/Deniz Arıkan.md` dosyasında Obsidian'ın yazdığı gibi blok liste biçiminde (`- Deniz\n  - Deniz abi`), diğer varlıklarda tek satırlı liste (`[Selin]`) biçimindedir.

### `recognition/`

Her örnek `entities.json`, `input.md`, `expected.json` ve `linked.md` taşır. `entities.json` kökünde `entities` dizisi vardır: `file`, `kind` (`person` veya `place`), `name`, isteğe bağlı `qualifier`, `aliases`. İsteğe bağlı `usage` dizisi `file`, `totalCount`, `lastDate` (ISO gün veya null), `cooccurrences` (dosya yolu → birlikte geçilen gün sayısı) taşır. Karşılaştırma anahtarları adlardan türetilir. `Işık`, yalnız Türkçe harf kuralını sınamak için Deniz'in sentetik takma adıdır. Ek örneğindeki `e`, Ece için eki ayrı ad saymayı engelleyen sentetik takma addır. Örtüşme örneğindeki `Arıkan Selin Korkmaz`, aynı kurgusal kadrodan oluşturulmuş sentetik konum takma adıdır.

`expected.json` kökündeki `mentions`, `line` (sıfır tabanlı), `byteRange` (satır içeriğinde UTF-8, başlangıç dahil son hariç iki sayı), `spelling`, sıralı aday yolları `candidates`, `isAmbiguous`, `isCaseMismatch` ve `isCertain` taşır. `unknownMentions` öğeleri aynı konum ve yazım alanlarını taşır, aday içermez. Aralıklar `@` ve ekleri kapsamaz. Beklentiler uygulamadan bağımsız yazılır. `linked.md` yalnız kesin anmaların bağlandığı bayt çıktısıdır; yeniden tanımada kesin anma kalmaz, kullanıcı seçimi bekleyen öneri, belirsiz ve bilinmeyenler kalabilir. Rastgele testler bütün bilinen anmalara seçim vererek tam bağlantının eşgüçlülüğünü ayrıca denetler. `escaped-code` içindeki kaçırılmış wikilink düz metin olarak korunur; e-posta, alan adı, etiket, kimlik, Markdown bağlantısı, sözdizimi komşuları ve frontmatter koruma örnekleri değişmeyen baytları denetler. Tablo örneğinde görünen metin ayırıcısı kaçırılır. Eşit uzunlukta örtüşme örneklerindeki `Deniz Ece` ve `Ece Selin`, kurgusal kadronun ad parçalarından oluşturulmuş sentetik ad/takma adlardır.

### `index/`

`index/sample/expected.json`, örnek kasanın tam yeniden üretiminden beklenen kanonik indeks dökümüdür. JSON kökünde `files`, `entities`, `aliases`, `blocks`, `links`, `goalLogs` dizileri bulunur. Dosyalar NFC yolun kod noktası sırasındadır; diğer diziler dosya yolu, ardından kaynak sıra (`ordinal`) ya da hedef anahtarı sırasındadır. Sıra sıfır tabanlı, satırlar bir tabanlı ve iki ucu dahildir; bayt aralıkları sıfır tabanlı, sonu hariçtir. İsteğe bağlı alanlar yoksa JSON anahtarı yazılmaz. Değişiklik zamanı, boyut ve içerik özeti döküme girmez.

`files`: `path`, `kind`, isteğe bağlı `date`, `readable`. `entities`: `file`, `kind`, `name`, `comparisonKey`, isteğe bağlı `qualifier`, `goalKey`, `period`, `goalKind`, `target`, `unit`. `aliases`: `file`, `ordinal`, `name`, `comparisonKey`. `blocks`: `file`, `ordinal`, `kind`, `firstLine`, `lastLine`, `text`, `section`, `ownsIdentifier`; isteğe bağlı `time`, `status`, `rawStatus`, `identifier`, `headingLevel` (`heading` bloğunda 1–6). `links`: `file`, `ordinal`, `line`, `byteStart`, `byteEnd`, `target`, `targetKey`, `embedded`; isteğe bağlı `block`, `key`, `entry`, `anchorKind`, `anchor`, `displayText`, `resolvedFile`. `goalLogs`: `file`, `key`, `date`, `kind`, `value` (metin; boolean standart `true`/`false`, sayı özgün yazım, diğer tür ham yazım).

Beklenti: 30 dosya, 13 varlık, 40 olay, 22 kimlikli ve 2 kimliksiz görev, 31 paragraf, 6 başlık, 61 bağlantı, 14 ayrı hedef adı, tek çözülmemiş hedef ve 31 hedef kaydı (`spor`: 6, `kitap`: 12, `su`: 13; 27 Eylül’de kayıt yok). Tam döküm paragraf metinlerini, kod çitlerini ve frontmatter bağlantılarını da denetler. Sentetik test kasaları geçici dizinlerde oluşturulur; fixture dosyası test sırasında güncellenmez.

`index/continuation/`, görev devamındaki girintili başlığın ayrı başlık veya paragraf üretmediğini kanonik dökümle doğrular; `input.md` üç satırlık tek görev bloğudur.

### `merge/`

Senkronizasyon çakışması birleştirme örnekleri (`vault-format.md`, "Senkronizasyon çakışması"). Her örnek bir klasördür: `a.md` ve `b.md` iki sürümün baytları, `case.json` zamanları ve saklanacak sürümleri, `expected.md` birleşmiş dosyanın baytlarıdır. Beklenen çıktılar koddan üretilmez; kurallar elle uygulanarak yazılır.

```json
{ "times": { "a": 10, "b": 20 }, "preserved": ["a"] }
```

- `times`: her sürümün değişiklik zamanı, tam sayı. Birim yoktur; yalnızca sıra anlamlıdır. Eşit zamanlar yeni sürümün bayt sırasıyla seçildiğini sınar.
- `preserved`: çakışma kopyası olarak saklanacak sürümlerin adları, alfabetik sırayla; hiçbiri saklanmıyorsa `[]`.

İstemci her örnekte şunları denetler: iki veriliş sırası da aynı baytları ve aynı saklanacak sürümleri verir; sonuç, `times` değerlerinin ikisinden de büyük bir zamanla iki sürümden her biriyle yeniden birleştirilince baytları değişmez; sonuç okunup yazılınca aynı kalır; işlevin kendi denetiminden bağımsız bir kayıp denetimi tutar (her sürümün blokları, bölge bölge ve sayımlı olarak serbest yazı satırları, frontmatter alanları ve yorum satırları sonuçta vardır ya da o sürüm saklanır; yalnızca kapalı görevin açık görevin yerini alması, iki kapalı görev arasında yalnız `✅` tarihi farkı, `goals` altında ilerleme ve yalnızca yazım farkı kayıp sayılmaz); adında `falls-back` geçmeyen hiçbir örnekte işlev son güvenceye düşmez (`fellBack` yanlıştır). Adlandırma kuralı burada da geçerlidir: adında `crlf`, `cr`, `bom`, `mixed-line-endings`, `no-final-newline`, `invalid-utf8` ya da `read-only` geçen örneğin Markdown dosyalarından en az biri o özelliği taşır.

### `journal/`

Uygulama katmanının günlük yazısı düzenleyicisi için örnek: `journal/edit/input.md` bir gün dosyası, `expected.md` Journal bölümü değiştirildikten sonraki tam dosyadır (frontmatter ve Events bayt bayt aynı kalır). Testi `Tests/JournalTests/JournalEditingTests.swift` çalıştırır.

## Testlerin klasörü bulması

Swift testleri `Fixtures/` klasörünü test kaynak dosyasından yukarı doğru çıkarak bulur. Paket deponun dışında derleniyorsa `FIXTURES_DIR` ortam değişkeni klasörün yolunu verir.
