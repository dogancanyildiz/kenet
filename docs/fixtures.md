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
| Kişi | Deniz Arıkan, Selin Korkmaz |
| Konum | Çınaraltı Kafe, Liman Ofis |

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

### Diğer kategoriler

Ayrıştırma, yazma, birleştirme ve örnek kasa kategorileri ilgili işle birlikte tanımlanır; klasör adları ve beklenen çıktı biçimleri o zaman bu belgeye eklenir.

## Testlerin klasörü bulması

Swift testleri `Fixtures/` klasörünü test kaynak dosyasından yukarı doğru çıkarak bulur. Paket deponun dışında derleniyorsa `FIXTURES_DIR` ortam değişkeni klasörün yolunu verir.
