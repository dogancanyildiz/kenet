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

`expected.json` kökünde her konu kendi anahtarını taşır; bugün yalnızca `frontmatter` vardır, bölümler, olaylar ve bağlantılar geldikçe yeni anahtarlar eklenir. İstemci yalnızca dosyada bulunan anahtarları karşılaştırır; karşılaştırma katıdır (fazla ya da eksik alan hatadır, metinler bayt bayt karşılaştırılır). Satır numaraları 1'den başlar; BOM satır sayılmaz.

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
- Kök anahtar işlemin hedefini söyler (`frontmatter`); bölüm ve satır işlemleri geldikçe yeni kök anahtarlar eklenir.

İstemci her yazma örneğinde şunları da denetler: frontmatter dışındaki baytlar değişmez, frontmatter içinde yalnızca hedef anahtarın satırları değişir, yazılan değer yeniden okununca aynı değeri verir, işlem ikinci kez uygulanınca dosya değişmez.

### Başka okuyucularla karşılaştırma

Uygulamanın okuyucusu ve yazıcısı aynı kuralları paylaşır; ikisinde birden yanlış olan bir kural kendi testlerinden geçer. `.github/scripts/check-frontmatter-yaml.rb` geliştirici betiği `parse/` beklentilerini ve `write/` çıktılarını Ruby Psych (YAML 1.1) ve istenirse js-yaml (YAML 1.2, Obsidian'ın okuyucusu) ile karşılaştırır; testlerin rastgele ürettiği blokları da aynı okuyuculara gösterebilir. Betik CI'da çalışmaz; frontmatter kuralları ya da örnekler değiştiğinde elle çalıştırılır. Kullanımı betiğin başında yazılıdır.

### Adlandırma

`parse/` ve `write/` klasör adları taşıdıkları bayt özelliğini söyler ve testler bunu ham baytlardan denetler: adında `crlf`, `cr`, `bom` sözcüğü ya da `mixed-line-endings`, `no-final-newline`, `invalid-utf8`, `read-only`, `exact-key-match` geçen örneğin Markdown dosyaları o özelliği taşımak zorundadır.

### `vaults/sample`

Kasa formatının ve istemci uygulamaların (ayrıştırıcı, modeller, indeksleyici, Obsidian uyumluluğu, arayüz, arama) uçtan uca test edilmesi için kullanılan tam ve tutarlı kurgusal örnek kasa. `Fixtures/vaults/sample/` altında yer alır:

- `journal/`: 2026-09-14 ile 2026-09-27 arası 14 gün dosyası.
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
3. **Frontmatter'sız not:** `notes/Proje Fikirleri.md` dosyası frontmatter taşımaz ve içinde elle yazılmış gibi blok kimliği bulunmayan görev satırları (`- [ ]`) ile bağlantılar içerir.
4. **Kod bloğu içindeki bağlantı ve başlık:** `notes/Toplantı Notları.md` içinde çitli kod bloğunda `[[Deniz Arıkan]]` ve `## Events` yer alır; bunlar ayrıştırıcı tarafından varlık bağlantısı ya da bölüm başlığı sayılmamalıdır.
5. **Çakışma kopyası:** `conflicts/2026-09-20 (conflict 20260920T183000Z).md`, `journal/2026-09-20.md` dosyasının bir olay metni farklı sürümüdür; taranmayan klasörler kuralı gereği indekslenmez.
6. **Çok satırlı `aliases`:** `people/Deniz Arıkan.md` dosyasında Obsidian'ın yazdığı gibi blok liste biçiminde (`- Deniz\n  - Deniz abi`), diğer varlıklarda tek satırlı liste (`[Selin]`) biçimindedir.

### Diğer kategoriler

Birleştirme kategorisi ilgili işle birlikte tanımlanır; klasör adları ve beklenen çıktı biçimleri o zaman bu belgeye eklenir.

## Testlerin klasörü bulması

Swift testleri `Fixtures/` klasörünü test kaynak dosyasından yukarı doğru çıkarak bulur. Paket deponun dışında derleniyorsa `FIXTURES_DIR` ortam değişkeni klasörün yolunu verir.
