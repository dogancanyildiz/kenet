# Fixtures

**Amaç:** Bu belge `Fixtures/` klasöründeki test verisinin düzenini, girdi ve beklenen çıktı sözleşmesini ve yeni örnek ekleme yolunu tarif eder.

**Kapsam:** `Fixtures/` altındaki kümeler ve kasalar; her kümenin dosya biçimi, davranış aileleri, test eşlemesi ve yeni fixture ekleme adımları.

| Terim | Tanım |
|---|---|
| Küme | `Fixtures/` altındaki birinci düzey klasör. |
| Örnek | Kümedeki tek vaka klasörü ya da bir JSON dosyasındaki tek vaka kaydı. |
| İstemci | Fixture dosyalarını okuyup sınayan test kodu. Bugün Swift testleridir; başka platformlar aynı dosyaları kullanır. |
| Kasa | `vaults/` altındaki tam örnek kasa. Birden çok küme aynı kasayı okur. |

Kasa biçiminin kuralları [Kasa biçimi](vault-format.md) belgesindedir. Bu belge kural tanımlamaz; kuralın hangi dosyayla sınandığını söyler.

## Belgenin sınırı

| Konu | Kural |
|---|---|
| Sayı | Belge örnek ve dosya sayısı tutmaz. Sayıyı disk verir. |
| Küme ve kasa sayımı | `find Fixtures -mindepth 2 -maxdepth 2 -type d \| cut -d/ -f2 \| sort \| uniq -c` |
| Bir kümenin vakaları | `ls Fixtures/<küme>` ya da kümenin `cases.json` dosyası |
| Vaka listesi | Belge vakaları tek tek değil, davranış ailesine göre listeler. |
| Vaka açıklaması | Açıklama fixture dosyasındaysa belge yinelemez. Bugün yalnız `summaries/entity-density.json` `description` alanı taşır. |
| Açıklaması dosyada olmayan vaka | Belge vakanın ne sınadığını kümenin "Vakalar" tablosunda tutar. |

## Genel kurallar

| Kural | Ayrıntı |
|---|---|
| Baytları koru | `.gitattributes` içindeki `Fixtures/** -text` satırı git'in satır sonu dönüşümünü kapatır. |
| Özel baytı `printf` ile yaz | Satır sonu, BOM ya da geçersiz bayt taşıyan dosyayı editörle değil `printf` ile oluştur. `xxd` ile doğrula. |
| Ham bayt denetimi | Testler bu özellikleri ham baytlardan ayrıca denetler. Bir araç dosyayı dönüştürürse test kırmızıya döner. |
| Kurgusal içerik | Repo herkese açıktır. Gerçek kişi, konum ya da günlük verisi girmez. |
| Belge yok | Klasörde README ya da açıklama dosyası yoktur. Her `.md` dosyası test verisidir. |
| `vault` adı yok | `Vault` ya da `vault` adında klasör açma. `.gitignore` bu adları her derinlikte dışarıda bırakır. |
| `.obsidian/` istisnası | `.gitignore` her `.obsidian/` klasörünü dışlar. `!Fixtures/**/.obsidian/` satırı fixture içindekini geri alır. |
| Kasa yeri | Yeni kasayı `Fixtures/vaults/<ad>/` altına koy. |
| Beklentiyi elle yaz | Fixture yazarı beklenen çıktıyı kurallardan, uygulamadan bağımsız yazar. Testler fixture dosyasını güncellemez. |

**Tablo, beklentisi koddan gelen 4 istisnayı verir.**

| Fixture | Beklentinin kaynağı |
|---|---|
| `recognition/mixed-digit-names-baseline/` | Rakam ad kuralından önceki tanıyıcının çıktısı. Dosya eski davranışı kanıt olarak tutar. |
| `recognition/unlinked-mentions-hostile/expected.json` | Çıktıdan üretildi; fixture yazarı satır satır elle gözden geçirdi. |
| `vaults/day-copies/expected/` | Birleştirme kodu üretti; fixture yazarı kuralları elle uygulayıp her dosyayı doğruladı. |
| `vaults/rhythm/` günlük hedef zinciri ve skoru | Fixture yazarı kodla karşılaştırdı; kurallar `SummaryGoalScoreTests` ile aynıdır. |

**UYARI:** `Fixtures/` altındaki bir dosyayı editörle açıp kaydetme; editör satır sonunu ya da BOM'u değiştirebilir.

**DİKKAT:** `Fixtures/vaults/sample` kasasına dosya ya da alan ekleme; yeni dosya testlerdeki elle sayımları ve ekran görüntüsü referanslarını bozar.

**DİKKAT:** `mixed-digit-names-baseline` beklentisini elle düzeltme.

**NOT:** Yeni bir fixture yolunu bitirmeden önce `git check-ignore -v <yol>` ile denetle.

## Kurgusal adlar

**Tablo, `vaults/sample/` kasasının kadrosunu verir. Yeni fixture önce bu adları kullanır.**

| Tür | Ad | Ayrıntı |
|---|---|---|
| Kişi | Deniz Arıkan | Takma adlar: Deniz, Deniz abi. Yeniden adlandırma örneği: Deniz Arıkan Yılmaz. |
| Kişi | Selin Korkmaz | Takma ad: Selin |
| Kişi | Baran Tunç | Takma ad: Baran |
| Kişi | Ece Yalın | Takma ad: Ece |
| Kişi | Mert Aksu | İkinci bir Mert Aksu `iş` ayırt edicisini taşır. |
| Konum | Liman Ofis | Takma ad: ofis; koordinat: `[10.5000, 20.0290]`; yarıçap: 100 |
| Konum | Çınaraltı Kafe | |
| Konum | Tepe Spor Salonu | Takma ad: salon; koordinat: `[10.5210, 20.0415]`; yarıçap: 80 |
| Konum | Ev | Emoji örneği: Ev 🏠 |
| Hedef | Spor | `spor`; haftada 3 gün; boolean; konum: Tepe Spor Salonu |
| Hedef | Kitap | `kitap`; günde 20; sayı; birim: sayfa |
| Hedef | Su | `su`; günde 8; sayı; birim: bardak |
| Özel tip varlığı | Yeni Kitap, Örnek Kitap, Örnek Film, Örnek Kurum, Örnek Proje, Örnek Etkinlik, Örnek Seyahat, Örnek Tarif, Örnek Ürün, Örnek Evcil Hayvan, Örnek Araç | `vaults/typed/`, `vaults/gallery/` |

| Durum | Kural |
|---|---|
| Yeni fixture, olağan ad | Tablodaki adı kullan. |
| Yeni fixture, tabloda karşılığı olmayan ad | Kurgusal bir ad seç. Ad `sample` kasasına girecekse önce tabloya ekle. |
| Var olan öteki kasalar | Kendi kurgusal kadrolarını taşır: `cadence`, `rhythm`, `anniversaries`, `history`, `turkce-buyuk-harf`, `unlinked-mentions*`. |
| Sentetik ad | Bir kuralı zorlamak için uydurulan ad ya da takma ad. Örnek: `Işık`, `Sayılar`, `12`, `2026-10-12`. |
| Bir kasanın kadrosu | `find Fixtures/vaults/<kasa> -name '*.md' -not -path '*/diary/*'` |
| Gerçek ad | Hiçbir kasada kullanma. |

## Klasör bulma

| Sıra | Koşul | Sonuç |
|---|---|---|
| 1 | `FIXTURES_DIR` dolu ve yol bir klasör | Test o klasörü kullanır. |
| 2 | `FIXTURES_DIR` dolu, yol klasör değil | Hata: geçersiz yol. |
| 3 | `FIXTURES_DIR` boş | Test kaynak dosyasının klasöründen yukarı çıkar ve ilk `Fixtures` klasörünü kullanır. |
| 4 | Dosya sisteminin köküne kadar `Fixtures` yok | Hata: `Fixtures` bulunamadı. |

Paket deponun dışında derlenirse `FIXTURES_DIR` ortam değişkeni klasörün yolunu verir.

## Fixture ve test eşlemesi

**Tablo, her kümeyi ve kasayı, ne sınadığını, koşan test dosyasını ve testin örnekleri nasıl bulduğunu verir.**

| Küme ya da kasa | Ne sınar | Test dosyası | Örnek bulma |
|---|---|---|---|
| Bütün `.md` dosyaları | Gidiş dönüş | `VaultFormatTests/RoundTripTests.swift` | Klasör tarama |
| `roundtrip/` | Korunacak bayt özellikleri | `VaultFormatTests/FixtureByteGuardTests.swift` | Dosya adı kodda |
| `parse/` | Okuma | `VaultFormatTests/ParseFixtureTests.swift`, `FixtureCaseGuardTests.swift` | Klasör tarama |
| `write/` | Dosya yazma | `VaultFormatTests/WriteFixtureTests.swift`, `FixtureCaseGuardTests.swift` | Klasör tarama |
| `write/diary-append-*` | Diary sonuna ekleme | ek olarak `VaultStoreTests/DiaryAppendTests.swift` | Klasör tarama |
| `write/relations/` | Açık bağ ekleme ve kaldırma | `VaultStoreTests/RelationsWriteTests.swift` | Klasör tarama |
| `write/mention-*` | Bağlanmamış anmayı bağlama | ek olarak `VaultStoreTests/UnlinkedMentionTests.swift` | Klasör tarama |
| `write/task-recur-trailing-text` | Tekrar kuralı | ek olarak `VaultFormatTests/RecurrenceTests.swift` | Ad kodda |
| `write/cadence-*` | Ritim alanı | ek olarak `Tests/KenetTests/CadenceTests.swift` | Ad kodda |
| `write/alias-*` | Takma ad | ek olarak `Tests/KenetTests/EntityAliasTests.swift` | Ad kodda |
| `merge/` | Çakışma birleştirme | `VaultFormatTests/MergeFixtureTests.swift`, `VaultStoreTests/DayCopyMergeCaseTests.swift` | Klasör tarama |
| `recognition/<ad>/` | Ad tanıma | `EntityRecognitionTests/Fixtures.swift` | Ad listesi |
| `recognition/attendees/` | Takvim katılımcısı eşleme | `EntityRecognitionTests/AttendeeMatchingTests.swift` | Ad kodda |
| `recognition/unlinked-mentions/` | Bağlanmamış anma sorgusu | `VaultStoreTests/UnlinkedMentionTests.swift`, `Tests/KenetTests/UnlinkedMentionsTests.swift` | Ad kodda |
| `recognition/unlinked-mentions-hostile/` | Sorguyu ve yazıcıyı zorlayan satırlar | `VaultStoreTests/UnlinkedMentionAdversarialTests.swift` | Ad kodda |
| `index/sample/` | Kanonik indeks dökümü | `VaultIndexTests/IndexTests.swift` | Ad kodda |
| `index/continuation/` | Görev devamındaki girintili başlık | `VaultIndexTests/IncrementalTests.swift` | Ad kodda |
| `index/entity-fields/` | Varlık alanı satırları | `VaultIndexTests/EntityFieldTests.swift` | Ad kodda |
| `index/cadence/` | Ritim alanı ve yıl dönümü satırları | `VaultIndexTests/CadenceFieldTests.swift` | Ad kodda |
| `diary/edit/` | Diary yazısını değiştirme | `Tests/KenetTests/DiaryEditingTests.swift` | Ad kodda |
| `diary/weekly-review/` | Haftalık inceleme yazımı | `Tests/KenetTests/WeeklyReviewTests.swift` | Ad kodda |
| `entities/fields/` | Varlık sayfasından alan ve takma ad yazma | `Tests/KenetTests/EntityPageTests.swift` | Ad kodda |
| `entity-types/` | Özel tip tanımları | `VaultIndexTests/EntityTypeTests.swift`, `VaultStoreTests/EntityTypeStoreTests.swift` | Ad listesi |
| `migration/legacy-vault/` | Eski gün klasörünün geçişi | `VaultStoreTests/DayFolderMigrationTests.swift`, `VaultIndexTests/LegacyDayFolderIndexTests.swift`, `Tests/KenetTests/DayFolderMigrationWiringTests.swift` | Ad kodda |
| `rename/` | Yeniden adlandırma | `VaultStoreTests/RenameTests.swift` | Ad listesi |
| `import/` | Var olan klasörü kasa olarak hazırlama | `Tests/KenetTests/VaultImportFixtureTests.swift` | Ad listesi |
| `dates/cases.json` | Doğal tarih ayrıştırma | `DateParsingTests/DateFixtureTests.swift` | JSON vaka |
| `dates/quick-entry.json` | Hızlı giriş görev çözümlemesi | `DateParsingTests/QuickEntryTests.swift` | JSON vaka |
| `dates/recurrence.json` | Tekrar kuralından sonraki tarih | `DateParsingTests/RecurrenceTests.swift` | JSON vaka |
| `dates/birthday.json`, `dates/birthday-person.md` | Doğum günü alanı | `VaultFormatTests/PersonBirthdayTests.swift` | JSON vaka, Markdown girdi |
| `goals/cases.json` | Hedef hesabı | `GoalTrackingTests/GoalFixtures.swift` | JSON vaka |
| `goals/series.json` | Değer grafiği serisi | `GoalTrackingTests/GoalSeriesTests.swift` | JSON vaka |
| `goals/writes/` | Hedef gün kaydı yazma | `VaultStoreTests/GoalStoreFixtures.swift` | JSON vaka |
| `goals/creation/` | Hedef dosyası oluşturma | `VaultStoreTests/GoalCreationTests.swift`, `MilestoneStoreTests.swift`, `Tests/KenetTests/GoalDefinitionTests.swift` | JSON vaka |
| `goal-chain/cases.json` | Zincir günü | `GoalTrackingTests/GraceDayTests.swift`, `SummariesTests/GraceDaySummaryTests.swift` | JSON vaka |
| `goal-chain/query/` | Zincir günü indeks sorgusu | `VaultIndexTests/GraceDayQueryTests.swift` | Markdown kasa, ad kodda |
| `summaries/cases.json` | Dönem özeti | `SummariesTests/PeriodSummaryTests.swift`, `TaskFlowSeriesTests.swift` | JSON vaka |
| `summaries/weekly-review-text.json` | Haftalık gözden geçirme metni | `SummariesTests/WeeklyReviewTextTests.swift` | JSON vaka |
| `summaries/cadence.json` | Görüşme ritmi | `SummariesTests/MeetingCadenceTests.swift`, `Tests/KenetTests/CadenceTests.swift` | JSON vaka |
| `summaries/important-dates.json` | Önemli tarihler | `SummariesTests/ImportantDatesTests.swift` | JSON vaka |
| `summaries/on-this-day.json` | Bu gün geçmişte | `SummariesTests/OnThisDayTests.swift` | JSON vaka |
| `summaries/period-rhythm.json` | Dönem ritmi | `SummariesTests/PeriodRhythmTests.swift` | JSON vaka |
| `summaries/year-writing.json` | Yazılan günler haritası | `SummariesTests/YearWritingCalendarTests.swift` | JSON vaka |
| `summaries/weekly-rhythm.json` | Haftalık incelemenin kısa ritmi | `SummariesTests/WeeklyReviewRhythmTests.swift` | JSON vaka |
| `summaries/task-flow.json` | Açık görev eğrisi | `SummariesTests/TaskFlowSeriesTests.swift` | JSON vaka |
| `summaries/entity-density.json` | Kişi ve konum geçiş yoğunluğu | `SummariesTests/EntityMentionDensityTests.swift` | JSON vaka |
| `summaries/weekday-distribution.json` | Haftanın günleri yazma oranı | `SummariesTests/WeekdayDistributionTests.swift` | JSON vaka |
| `vaults/sample/` | Uçtan uca örnek kasa. Okuyan: `index/sample`, `summaries/cases.json`. | `IndexTests`, `PeriodSummaryTests`, `WikiLinkTests`, `MergeTests` ve uygulama testlerinin çoğu | Ad kodda |
| `vaults/typed/` | Özel kitap tipi | `EntityTypeTests`, `EntityTypeStoreTests`, `InitialIndexTests`, `Tests/KenetTests/CustomEntityTypeTests.swift` | Ad kodda |
| `vaults/gallery/` | Hazır tip galerisi | `VaultStoreTests/EntityTypeGalleryTests.swift`, `Tests/KenetTests/EntityTypeGalleryTests.swift` | Ad kodda |
| `vaults/backlinks/` | Bu güne bağlananlar sorgusu | `VaultIndexTests/DayBacklinksTests.swift` | Ad kodda |
| `vaults/placeholder/` | İndirilmeyi bekleyen yer tutucular | `VaultStoreTests/PlaceholderTests.swift`, `Tests/KenetTests/CloudDownloadTests.swift`, `SyncStatusTests.swift` | Ad kodda |
| `vaults/day-copies/` | Gün kopyası birleştirme | `VaultStoreTests/DayCopyTests.swift`, `DayCopyMergeCaseTests.swift`, `DayCopyFailureTests.swift`, `ConflictCopyListingTests.swift`, `Tests/KenetTests/DayCopyMergeWiringTests.swift` | Ad kodda (`Support/DayCopyVault.swift`) |
| `vaults/copy-files/` | Varlık kopyası ve gün kopyası listesi; birleştirme yok | `VaultIndexTests/CopyFileTests.swift`, `Tests/KenetTests/SyncedFolderNoticeTests.swift` | Ad kodda |
| `vaults/conflict-copies/` | Çakışma kopyası ad kuralı, `conflicts/` listesi, çakışan sürüm sorgusu | `VaultIndexTests/ConflictCopyTests.swift`, `Tests/KenetTests/SyncConflictTests.swift`, `DiagnosticsConflictWiringTests.swift`, `Snapshots/ConflictVersionsSnapshotTests.swift` | Ad kodda |
| `vaults/nfd-names/` | Ayrışmış (NFD) dosya adı, ad, takma ad ve bağlantı | `VaultIndexTests/ChangeDetectionTests.swift` (`DecomposedNameTests` kümesi) | Ad kodda |
| `vaults/turkce-buyuk-harf/` | Türkçe büyük harf eşlemesi | `VaultStoreTests/TurkishCapitalTests.swift` | Ad kodda |
| `vaults/entity-fields/` | Üst düzey tarih, sayı, evet/hayır alanları | `VaultIndexTests/EntityFieldTests.swift` | Ad kodda |
| `vaults/unlinked-mentions/` | Bağlanmamış anma sorgusu | `VaultStoreTests/UnlinkedMentionTests.swift`, `Tests/KenetTests/UnlinkedMentionsTests.swift`, `Tests/KenetUITests/UnlinkedMentionsAccessibilityUITests.swift` | Ad kodda; JSON `vault` alanı |
| `vaults/unlinked-mentions-hostile/` | Sorguyu ve yazıcıyı zorlayan satırlar | `VaultStoreTests/UnlinkedMentionAdversarialTests.swift` | Ad kodda; JSON `vault` alanı |
| `vaults/cadence/` | Görüşme ritmi kadrosu | `VaultIndexTests/CadenceFieldTests.swift`, `Tests/KenetTests/CadenceTests.swift`, `QueryOutcomeTests.swift`, `Snapshots/CadenceSnapshotTests.swift` | Ad kodda |
| `vaults/anniversaries/` | Yıl dönümü tarihleri | `SummariesTests/ImportantDatesTests.swift` | JSON `vault` alanı |
| `vaults/history/` | Bu gün geçmişte | `SummariesTests/OnThisDayTests.swift` | JSON `vault` alanı |
| `vaults/rhythm/` | Özetler'in yıl, süren dönem ve ritim hesabı | `SummariesTests/PeriodRhythmTests.swift`, `YearWritingCalendarTests.swift`, `WeeklyReviewRhythmTests.swift`, `WeekdayDistributionTests.swift` | JSON `vault` alanı |
| `vaults/graph/` | Graph anmaları, günün grafiği, açık ilişkiler | `VaultStoreTests/GraphMentionsTests.swift`, `DayGraphMentionsTests.swift`, `VaultIndexTests/RelationsIndexTests.swift`, `Tests/KenetTests/GraphMapTests.swift`, `DayGraphTests.swift`, `DayGraphMacHostedTests.swift`, `GraphCustomTypeTests.swift`, `EntityRelationsModelTests.swift`, `Snapshots/DayGraphSnapshotTests.swift`, `Snapshots/DayGraphMacSnapshotTests.swift` | Ad kodda |

| Konu | Anlam |
|---|---|
| Göreli yol | `Packages/Core/Tests/` altındadır. `Tests/KenetTests/` ile başlayan yol uygulama testidir. Önü yazılmamış ad bir önceki yolun klasöründedir. |
| Klasör tarama | Test yeni klasörü kendiliğinden bulur. |
| Ad listesi | Test yeni klasörü yalnız `@Test(arguments:)` listesine eklenince koşar. |
| JSON vaka | Test yeni vakayı JSON dizisine eklenince koşar. |
| JSON `vault` alanı | Vaka kasanın adını `vault` alanında verir. |

## Yeni fixture ekleme

| Davranışın katmanı | Küme | Bulma yolu |
|---|---|---|
| Okuma | `parse/` | Klasör tarama: kod değişmez. |
| Dosya yazma | `write/` | Klasör tarama: kod değişmez. |
| Birleştirme | `merge/` | Klasör tarama: kod değişmez. |
| Ad tanıma | `recognition/` | Ad listesine ekle. |
| İndeks ya da sorgu | `vaults/` altında yeni kasa ve beklenti JSON | Test dosyasına kasa adını yaz. |
| Saf hesap | `dates/`, `goals/` ya da `summaries/` | JSON dizisine vaka ekle. |

1. Davranışın kuralını önce [Kasa biçimi](vault-format.md) belgesinde bul.
2. Kural belgede yoksa önce belgeyi güncelle.
3. Yukarıdaki tablodan kümeyi seç.
4. Örnek klasörünü küme adlandırma desenine göre adlandır.
5. Ad bir bayt özelliği söylüyorsa dosyaya o özelliği ver.
6. Özel baytları `printf` ile yaz.
7. Baytları `xxd` ile doğrula.
8. Beklenen çıktıyı kurallardan elle yaz.
9. Beklentiyi uygulamanın çıktısından kopyalama.
10. Kurgusal adı "Kurgusal adlar" kuralına göre seç.
11. Küme ad listesi kullanıyorsa adı test dosyasındaki listeye ekle.
12. Yeni kasayı `Fixtures/vaults/<ad>/` altına koy.
13. Yeni yolu `git check-ignore -v` ile denetle.
14. `RoundTripTests` testini koş; yeni `.md` dosyası gidiş dönüşten geçmeli.
15. Kümenin testini koş.
16. Yeni küme, kasa ya da davranış ailesi açtıysan bu belgedeki tabloya satır ekle.

## Ortak alanlar

**Tablo, birden çok kümenin JSON dosyalarında aynı anlamla geçen alanları verir. Küme tabloları bu alanları yinelemez.**

| Alan | Tür | Anlam |
|---|---|---|
| `id` | metin | Vakanın adı. Ad vakanın ne sınadığını söyler. |
| `description` | metin | Vakanın açıklaması; isteğe bağlı. |
| `vault` | metin | `vaults/` altındaki kasanın adı. |
| `today` | ISO gün ya da `null` | Hesabın "bugün"ü. Yoksa bütün dönem ölçülür. |
| `expected` | nesne, dizi ya da `null` | Beklenen sonuç. |
| `expectedError`, `error` | metin | Beklenen hatanın adı. Ret örneğinde yazıcı dosyaya dokunmaz. |
| `period`, `containing` | `week`/`month`/`year`, ISO gün | Dönem türü ve dönemin içindeki bir gün. |
| `days` | dizi | Satır içi günler: `date`, `events`, `hasDiary`. Vaka ya `vault` ya `days` taşır. |
| `file`, `path` | metin | Kasa köküne göre göreli yol. |
| `line` | tam sayı | Satır. Tabanı küme tablosu söyler. |
| `firstLine`, `lastLine` | tam sayı | 1 tabanlı, iki ucu dahil aralık. BOM satır sayılmaz. |
| `byteRange` | `[başlangıç, son]` | Satır içeriğinin UTF-8 baytlarında 0 tabanlı aralık. Son hariçtir. Sayım BOM'u ve satır sonunu dışarıda bırakır. |
| `spelling` | metin | Anmanın kaynaktaki yazımı. `@` işaretini ve eki kapsamaz. |
| `candidates` | dizi | Sıralı aday dosya yolları. |
| Olmayan değer | `null` | Olmayan tarih ya da hesaplanmayan skor JSON `null` olur. |

## `roundtrip/` kümesi

| Adım | Ayrıntı |
|---|---|
| Girdi | `Fixtures/` altındaki her `.md` dosyası; öteki kümelerdekiler dahil. |
| Türetilmiş haller | Bütün satır sonları LF, CRLF ya da CR; başa BOM; son satır sonu atılmış; her bayt konumunda kesilmiş. |
| Kesme | 1.024 bayta kadar dosyada her bayt konumu. Daha büyük dosyada 257 eşit aralıklı konum. |
| Denetim | Test dosyayı okur ve değiştirmeden yazar. Baytlar aynı kalmalıdır. |
| Beklenen çıktı | Dosyanın kendisi; ayrı çıktı dosyası yoktur. |

| Dosya | Bayt özelliği |
|---|---|
| `day-basic.md` | Olağan gün dosyası: UTF-8, LF, yeni satırla biter |
| `crlf.md`, `cr.md` | Bütün satır sonları CRLF; tek CR |
| `bom.md` | Başta UTF-8 BOM |
| `no-final-newline.md` | Yeni satırla bitmez |
| `mixed-line-endings.md` | LF, CRLF ve CR karışık; her biçimden boş satır |
| `empty.md` | Sıfır bayt |
| `invalid-utf8.md` | UTF-8 olarak çözülemeyen baytlar |

Bu kümeye yalnız korunacak bir bayt özelliği taşıyan dosya koy.

## `parse/` kümesi

**Tablo, okuma örneklerini davranış ailesine göre verir.**

| Davranış ailesi | `expected.json` kökü | Örnek vaka |
|---|---|---|
| Okunabilir frontmatter yapısı | `frontmatter` | `person-basic`, `block-list`, `goals-with-comments` |
| Frontmatter yok | `frontmatter` | `absent-no-closing`, `absent-plain-note` |
| Ham alan | `frontmatter` | `raw-block-scalar`, `raw-anchor-alias-tag` |
| Çözülemeyen blok | `frontmatter` | `unreadable-duplicate-key`, `unreadable-tab-indentation` |
| Bayt özelliği | `frontmatter` | `bom`, `crlf`, `invalid-utf8-in-body` |
| Gün dosyası bölümleri | `sections` | `section-duplicate`, `section-out-of-order`, `section-legacy-heading` |
| Olay ve görev blokları | `tasks`, `events` | `line-siblings`, `line-statuses`, `line-quote-blocks` |
| Çitli kod içindeki satırlar | `tasks`, `events` | `line-fence-list`, `line-fence-tab`, `line-indented-fence` |
| Görev alanları | `tasks`, `events` | `task-fields-mixed`, `task-fields-protected` |
| Tekrar kuralı | `tasks`, `events` | `task-recurrence-supported`, `task-recurrence-unknown` |
| Bağlantılar | `links` | `link-frontmatter`, `link-yaml-escapes`, `link-table-separator` |

| Konu | Kural |
|---|---|
| Örnek | Bir klasör; tam olarak `input.md` ve `expected.json` taşır. |
| Kök anahtarlar | `frontmatter`, `sections`, `tasks`, `events`, `links` |
| Karşılaştırılan anahtar | Yalnız dosyada bulunan kök anahtarlar; boş `expected.json` hatadır. |
| Karşılaştırma | Katı: fazla ya da eksik alan hatadır. İstemci metinleri bayt bayt karşılaştırır. |
| Satır | 1 tabanlı. |

**Tablo, `expected.json` alanlarını verir.**

| Kök | Alan | Tür | Anlam |
|---|---|---|---|
| `frontmatter` | `state` | metin | `parsed`, `absent` ya da `unreadable`. Son ikisinde başka alan yoktur. |
| `frontmatter` | `firstLine`, `lastLine` | tam sayı | Blokta açılış ve kapanış `---` satırları. Alanda anahtar satırı ve alanın boş ya da yorum olmayan son satırı. |
| `frontmatter` | `fields` | dizi | Dosya sırasındaki alanlar. Her alan `key` ve aşağıdaki 4 anahtardan tam birini taşır. |
| `fields[]` | `scalar` | nesne | `type` (`text`, `number`, `boolean`, `date`, `empty`), `text` (çözülmüş metin), `raw` (dosyadaki yazım, tırnaklar dahil) |
| `fields[]` | `list` | nesne | `style` (`inline` ya da `block`) ve `items` (her biri bir `scalar`) |
| `fields[]` | `mapping` | dizi | Sırayla `key`, `line` ve `value` (bir `scalar`) taşıyan kayıtlar |
| `fields[]` | `raw` | metin | Alt küme dışı alanın ham metni: anahtardan sonraki kısım ve kalan satırlar, LF ile birleşik |
| `fields[]` | `listItems` | dizi | Liste görünümü: öğelerin `text` değerleri. Tek değer tek öğeli, boş değer boş listedir. `mapping` ve `raw` alanlarında yoktur. |
| `sections` | `preamble` | aralık ya da `null` | Ön içerik aralığı |
| `sections` | `items[]` | dizi | Dosya sırasındaki bölümler: `kind`, `headingLine`, `level`, `firstLine`, `lastLine`. İç başlıklar ayrı öğe değildir. |
| `items[]` | `kind` | metin ya da `null` | `Tasks`, `Events`, `Diary`. Tanınmayan ya da yinelenen başlıkta `null`. Eski `## Journal` başlığı da `Diary` verir. |
| `items[]` | `firstLine`, `lastLine` | tam sayı | Aralık başlığı ve sondaki boş satırları içerir. |
| `tasks`, `events` | `line`, `firstLine`, `lastLine` | tam sayı | İlk satır ve blok aralığı |
| `tasks`, `events` | `id`, `text` | metin ya da `null` | Şapkasız kimlik; sadeleşmiş metin. Kimlik uzunluğu ve yinelenmesi aynen kalır. |
| `events` | `time` | nesne ya da `null` | `{ "hour": 9, "minute": 5, "raw": "9:05" }` |
| `tasks` | `dueDate`, `startDate`, `doneDate` | ISO gün ya da `null` | Görev tarihleri |
| `tasks` | `priority` | metin, nesne ya da `null` | `"high"`, `"medium"`, `"low"`, `{ "other": "🔺" }`, `{ "other": "⏬" }` |
| `tasks` | `project` | metin ya da `null` | İlk proje adı |
| `tasks` | `recurrenceSource`, `recurrence` | metin | `🔁` alanının özgün yazımı ve okunan kural. Okunamayan kuralda `recurrence` `null` olur. Yalnız alan varsa yazılır. |
| `tasks` | `fieldRanges[]` | dizi | `{ "kind", "byteRange" }`. `kind`: `dueDate`, `startDate`, `doneDate`, `priority`, `project`, `recurrence`. |
| `tasks` | `rawStatus`, `status` | metin | Tek Unicode skaleri; `todo`, `inProgress`, `done`, `cancelled`, `unknown` |
| `tasks` | `isClosed`, `isOpen` | boolean | Durumun kapalı ve açık görünümü |
| `links` | `line`, `byteRange` | tam sayı, aralık | Satır ve `[[` ile `]]` dahil yazım. Gömmenin `!` işaretini kapsamaz. |
| `links` | `targetRange`, `rawTarget` | aralık, metin | `.md` dahil özgün hedef yazımı ve aralığı. Çevredeki Unicode boşlukları ve `\|` ayırıcısının ters bölüsü hariç. Boş hedefte iki uç eşittir. |
| `links` | `target` | metin | Çözülmüş hedef: çevredeki boşluklar ve tam `.md` soneki atılmış. |
| `links` | `anchor` | nesne ya da `null` | `{ "kind": "heading"\|"block", "text": "..." }`. Hash ve blok şapkası hariç. |
| `links` | `displayText` | metin ya da `null` | İlk borudan sonraki metin. Okuyucu çapayı ve görünen metni kırpmaz. |
| `links` | `isEmbedded`, `isSameFile`, `isPath` | boolean | Gömme, aynı dosya ve yol hedefi işaretleri |
| `links` | `source` | nesne | `{ "kind": "body" }` ya da `{ "kind": "frontmatter", "key": "...", "entry": null\|"..." }`. `entry` yalnız eşlem kaydında doludur. |

```json
{ "tasks": [{ "line": 1, "firstLine": 1, "lastLine": 1, "id": null, "text": "kitap",
  "dueDate": null, "startDate": null, "doneDate": null, "priority": null, "project": null,
  "fieldRanges": [], "rawStatus": " ", "status": "todo", "isClosed": false, "isOpen": true }],
  "events": [] }
```

**Tablo, beklentinin dayandığı kuralın yerini ve yalnız beklenti dosyasına ait ayrıntıyı verir.**

| Konu | Kural kaynağı | Beklenti dosyasına ait ayrıntı |
|---|---|---|
| Frontmatter durumu ve türler | [Frontmatter](vault-format.md#frontmatter), [Türler](vault-format.md#türler) | Yok |
| Blok aralığı ve girinti | [Blok kimliği](vault-format.md#blok-kimliği), "Satır bloğu" | Yok |
| Metin sadeleştirme | [Görev alanları](vault-format.md#görev-alanları), "Olay ve görev metninin okunması" | Yok |
| Görev alanı aralığı | [Görev alanları](vault-format.md#görev-alanları) | `byteRange` fiziksel ilk satırın baytlarıdır ve ayırıcı boşlukları kapsamaz. Geçerli yinelenen alanların hepsi aralıklarda yer alır. |
| Bağlantı ayrıştırma | [Bağlantı ayrıştırma](vault-format.md#bağlantı-ayrıştırma) | `links` fiziksel dosya sırasındadır. `links: []` hiç bağlantı olmadığını denetler. |
| Frontmatter bağlantısının aralığı | [Bağlantı ayrıştırma](vault-format.md#bağlantı-ayrıştırma) | Aralıklar fiziksel YAML satırına geri eşlenir. Bir kaçışın ürettiği baytlar kaçışın tamamını kapsar. `rawTarget` kaçışları korur. Kaçışlı ayraçta aralığın fiziksel uçları da kaçış yazımıdır. |

### Başka okuyucularla karşılaştırma

| Okuyucu | YAML sürümü | Koşul |
|---|---|---|
| Ruby Psych | YAML 1.1 | Her zaman |
| js-yaml | YAML 1.2, Obsidian'ın okuyucusu | İstenirse |

| Konu | Ayrıntı |
|---|---|
| Betik | `.github/scripts/check-frontmatter-yaml.rb`; kullanımı betiğin başındadır. |
| Neden | Uygulamanın okuyucusu ve yazıcısı aynı kuralları paylaşır. İkisinde birden yanlış olan kural kendi testlerinden geçer. |
| Karşılaştırılan | `parse/` beklentileri, `write/` çıktıları ve istenirse testlerin rastgele ürettiği bloklar. |
| `write/relations/` | Hatasız bağ işleminde okuyucu hedefe giden bağlantıyı dizgi olarak okumalıdır. Kaldırmada okumamalıdır. |
| Ne zaman | CI betiği koşmaz. Frontmatter kuralları ya da örnekler değişince betiği elle çalıştır. |

### Adlandırma

**Tablo, `parse/` ve `write/` klasör adındaki sözcüğün dosyaya yüklediği bayt özelliğini verir.**

| Addaki sözcük | Markdown dosyalarının taşıması gereken özellik |
|---|---|
| `crlf` | Yalnız CRLF satır sonu |
| `cr` | Yalnız CR satır sonu |
| `bom` | Başta UTF-8 BOM |
| `mixed-line-endings` | LF, CRLF ve CR birlikte |
| `no-final-newline` | Son satır sonu yok |
| `invalid-utf8`, `read-only` | Geçersiz UTF-8 |
| `exact-key-match` | Ayrışmış harf baytları |

`FixtureCaseGuardTests` bu özelliği ham baytlardan denetler. `crlf`, `cr` ve `bom` adda iki tire arasında tam sözcük olarak geçer. Diğer sözcükler adın herhangi bir yerinde geçebilir.

## `write/` kümesi

**Tablo, yazma örneklerini davranış ailesine göre verir.**

| Davranış ailesi | Kök anahtar | Örnek vaka |
|---|---|---|
| Tek değer yazma ve tırnaklama | `frontmatter` | `set-value-quotes-text-like-date`, `set-value-creates-frontmatter-crlf` |
| Liste yazma | `frontmatter` | `set-list-block-adds-item`, `set-list-inline-stays-inline` |
| Eşlem kaydı yazma ve alan silme | `frontmatter` | `set-entry-crlf`, `remove-entry`, `remove-field-mapping` |
| Reddedilen frontmatter yazımı | `frontmatter` | `error-raw-field-set-value`, `error-unreadable-duplicate-key` |
| Ritim alanı | `frontmatter` | `cadence-days-add`, `cadence-snooze-replace` |
| Takma ad ekleme ve kaldırma | `frontmatter` | `alias-add-missing-key`, `alias-remove-inline-keeps-spelling` |
| Bölüme satır ekleme | `sections` | `section-append-end`, `section-unclosed-fence-create` |
| Günlük yazısını değiştirme | `sections` | `section-diary-replace`, `section-diary-legacy-heading` |
| Günlük yazısına ekleme | `sections` | `diary-append-new`, `diary-append-legacy-heading` |
| Olay ve görev satırı: ekle, değiştir, sil, reddet | `lines` | `line-add-middle`, `line-fix-stale-task-text`, `line-reject-stale` |
| Görev alanı ve durum | `lines` | `task-due-replace-middle`, `task-complete`, `task-cancelled-complete-new-date` |
| Tekrar kuralı | `lines` | `task-recur-canonical-change`, `task-recur-when-done`, `task-recur-month-end` |
| Bağlanmamış anmayı bağlama | `mention` | `mention-alias`, `mention-nfd-bom-crlf-no-final-newline` |
| Açık bağ ekleme ve kaldırma | `relations/` alt klasörü | `place-target`, `label-zwj`, `remove-unreadable` |

| Konu | Kural |
|---|---|
| Başarılı örnek | `input.md`, `operation.json` ve `expected.md`. İstemci sonucu `expected.md` ile bayt bayt karşılaştırır. |
| Ret örneği | `expected.md` yoktur. `operation.json` içindeki `expectedError` hatayı adlandırır. İstemci dosyanın değişmediğini denetler. |
| Kök anahtar | İşlemin hedefini söyler. Yeni işlem türü yeni kök anahtar getirir. |
| Kural kaynağı | Beklenen her bayt [Kasa biçimi](vault-format.md) kurallarından türer. |

**Tablo, `operation.json` işlemlerini ve alanlarını verir.**

| Kök | `operation` | Alanlar | İşlem |
|---|---|---|---|
| `frontmatter` | `set-value` | `key`, `value` | Alana tek değer yazar |
| `frontmatter` | `set-list` | `key`, `items` | Alana liste yazar |
| `frontmatter` | `set-entry` | `key`, `entry`, `value` | `key` altındaki eşlemde `entry` kaydını yazar |
| `frontmatter` | `remove-entry` | `key`, `entry` | Eşlemden kaydı siler |
| `frontmatter` | `remove-field` | `key` | Alanı siler |
| `sections` | `append` | `kind`, `lines` | Bölüme satır ekler; en az bir boş olmayan satır gerekir |
| `sections` | `replace-diary` | `text` | Günlük yazısının tamamını değiştirir |
| `sections` | `append-diary` | `lines` | Diary bölümüne satır ekler; dizgiler satır sonu taşıyabilir |
| `lines` | `add-event` | `text`, `id`, isteğe bağlı `time` | Olay ekler |
| `lines` | `add-task` | `text`, `id` | Görev ekler |
| `lines` | `add-task-fields` | `text`, `id`, isteğe bağlı `due`, `start`, `priority`, `project` | Alanlı görev ekler |
| `lines` | `text` | `line`, `text`, isteğe bağlı `id` | Metni değiştirir |
| `lines` | `status` | `line`, `status`, isteğe bağlı `id`, tamamlamada `completionDate` | Durumu değiştirir |
| `lines` | `time` | `line`, `time`, isteğe bağlı `id` | Olay saatini değiştirir |
| `lines` | `delete` | `line` | Bloğu siler |
| `lines` | `due`, `start`, `priority`, `project` | `line`, alanın anahtarında değer, isteğe bağlı `id` | Görev alanını yazar ya da siler |
| `lines` | `recurrence` | `line`, `rule` (kural ya da `null`), isteğe bağlı `id` | `🔁` alanını yazar ya da siler |
| `lines` | `complete-recurring` | `line`, `id`, `completionDate` | Tekrarlayan görevi tamamlar ve sonraki görevi ekler |
| `lines` | `stale-delete`, `stale-text` | `replacement` | `replacement` içindeki Markdown belgeye eski bloğu uygulamayı dener |
| `lines` | `wrong-status`, `wrong-time` | `line` | Yanlış türden hedefi sınar |
| `lines` | `stale` | `line` | Hedef okunduktan sonra metni `Su` yapar ve eski hedefle düzenlemeyi dener |
| `mention` | yok | `vault`, `file`, `entity`, `line`, `byteRange`, `spelling` | Tek bir bağlanmamış anmayı bağlantıya çevirir |

```json
{ "frontmatter": { "operation": "set-entry", "key": "goals", "entry": "kitap", "value": { "integer": 30 } } }
```

**Tablo, işlem alanlarının değer biçimlerini verir.**

| Alan | Biçim |
|---|---|
| `value` | Türünü adlandıran tek anahtarlı nesne: `{ "text": "..." }`, `{ "boolean": true }`, `{ "integer": 25 }`, `{ "number": "20.029" }`, `{ "date": "2026-10-02" }` |
| `number` | Yazılacak yazımı metin olarak taşır. Böylece beklenti bir dilin ondalık sayı biçimine bağlı kalmaz. |
| `line` | `lines` kökünde hedef bloğun 1 tabanlı ilk satırı. `mention` kökünde sıfır tabanlı satır. |
| `time` | `null` ya da `{ "hour": 9, "minute": 5 }` |
| `status` | `todo`, `inProgress`, `done`, `cancelled`; `unknown` yalnız ret örneğinde |
| `id` | Düzenlemede yeni kimlik; yoksa özgün kimlik yazımı kalır |
| Görev alanı değeri | ISO gün, öncelik adı, proje adı ya da `null` |
| `mention.file`, `mention.entity` | Kasada `input.md` ile değiştirilen gün dosyası; bağlanacak varlık dosyası |
| `mention.byteRange` | Açık anmada önündeki `@` işaretini de kapsar. |

**Tablo, hata adlarını verir.**

| `expectedError` | Kök | Neden |
|---|---|---|
| `read-only-document` | hepsi | Dosya UTF-8 değil |
| `unreadable-frontmatter` | `frontmatter` | Frontmatter çözülemiyor |
| `raw-field` | `frontmatter` | Ham alan |
| `not-a-mapping` | `frontmatter` | Değeri olan alana kayıt yazma |
| `invalid-key` | `frontmatter` | Boş anahtar ya da `<<` |
| `invalid-value` | `frontmatter`, `lines` | Sayı yazımına uymayan `number`; geçersiz değer |
| `section-not-writable` | `sections`, `lines` | Bölüm yazılamıyor |
| `empty-section-append` | `sections` | Boş ekleme |
| `line-break-in-content` | `sections`, `lines` | İçerikte satır sonu |
| `target-not-found` | `lines` | Hedef blok yok |
| `empty-text` | `lines` | Boş metin |
| `content-not-representable` | `lines` | İçerik satırda yazılamıyor |
| `identifier-exhausted` | `lines` | Kimlik üreticisinin deneme sınırı doldu |

**Tablo, istemcinin beklenen baytların yanında yaptığı ek denetimleri verir.**

| Kök ya da işlem | Ek denetim |
|---|---|
| `frontmatter` | Frontmatter dışındaki baytlar değişmez. İçeride yalnız hedef anahtarın satırları değişir. Yeniden okuma yazılan değeri verir. İkinci uygulama dosyayı değiştirmez. |
| `sections`, `append` | Yeniden okunan model. Aynı ekleme ikinci kez gelince yazıcı satırları tekrar ekler; eşgüçlülük denetimi burada çalışmaz. |
| `sections`, `replace-diary` | Yapı kısıtlarından doğan hatalar. Aynı metinle ikinci uygulama ilkiyle bayt bayt aynıdır. |
| `sections`, `append-diary` | Yeniden okuma. Eski baytlar tek bir yeni parçanın iki yanında aynen kalır. Boş eklemede `expected.md` girdiyle aynıdır. |
| `lines` | Yeniden okunan model. Hedef dışında kalan satırların baytları. |
| `mention` | Aşağıdaki "Anma bağlama" tablosu. |

**Tablo, vaka adından anlaşılmayan aile ayrıntısını verir. Kural kaynağı ilgili [Kasa biçimi](vault-format.md) bölümüdür.**

| Aile | Sınanan ayrıntı | Kural kaynağı |
|---|---|---|
| `cadence-*` | Yorum satırı, komşu alan, CRLF ve BOM hedef satırın dışında kalır. `cadence-*-replace-text` yok sayılan yazımı (`aylık`, `yes`) seçilen değerle değiştirir. `cadence-snooze-replace` eski erteleme tarihini yerinde değiştirir. `cadence-snooze-remove-middle` sürdürmenin yalnız `cadence_paused` satırını sildiğini gösterir. | [Görüşme ritmi](vault-format.md#görüşme-ritmi) |
| `alias-*` | İşlem `set-list` işlemidir. Uygulama testi aynı baytları sayfanın ekleme ve kaldırma eylemiyle üretir. Vakalar eksik anahtarı, tırnağı, yorumu, CRLF ve BOM'u, tek değeri, virgüllü adı ve son öğeyi kapsar. | [Yazma kuralları](vault-format.md#yazma-kuralları) |
| `section-diary-*` | Bölüm yoksa boş metin dosyayı değiştirmez. Gövdedeki `---` bir başarı örneğidir. | [Diary yazısını değiştirme](vault-format.md#diary-yazısını-değiştirme) |
| `diary-append-*` | Yeni, eksik, boş ve dolu bölüm; sondaki boş satırlar; her bayt özelliği. Komşu yapılar: sonraki bölüm, yorum bloğu, yinelenen ve benzer başlık, alt başlık, liste, çit, tablo, frontmatter. `structure-lines` yapı satırlarının başına `· ` koyar. | [Diary bölümüne ekleme](vault-format.md#diary-bölümüne-ekleme) |
| `task-*` | Alanın yerinde değişmesi, kaldırma, yinelenmeler, salt okunur öncelikler, tamamlama, yeniden açma ve iptal. `task-text-keeps-positions` alan konumlarını korur. `task-due-reference-link` referans bağlantısında baytları değiştirmez. | [Görev düzenleme](vault-format.md#görev-düzenleme) |
| `task-recur-*` | Kuralı değiştirme, kaldırma ve onarma; ay sonu, taşma, iç içe görev, CRLF ve BOM, yinelenen kimlik, tamamlanınca tekrar. | [Tekrarlayan görevler](vault-format.md#tekrarlayan-görevler) |
| `*-legacy-heading` | Yazıcı eski `## Journal` başlığına yazar ve başlığı değiştirmez. | [Eski adlar ve geçiş](vault-format.md#eski-adlar-ve-geçiş) |
| `relations/` | `related` tek değerlerinin her türü, boş alanlar, liste biçimleri, kırpılan, geçersiz ve ayrılmış etiketler, güvenli silme, hedef türü ve yol yazımı. İç klasörler elle yazılmış önce ve sonra baytlarını ve `operation.json` taşır. | [İlişkiler](vault-format.md#i̇lişkiler) |
| `relations/`, hedef ve kaynak | `place-target`, `custom-target`, `place-source-label` ve `custom-source-label` konumu ve özel tipi hedef ve kaynak olarak yazar. `label-unresolved-link` çözülmeyen bağlantılı etiket alanına ekler. | [İlişkiler](vault-format.md#i̇lişkiler) |
| `relations/`, etiket | `label-zwj` emoji birleştiricili etiketi kabul eder. `invalid-label-nel` (U+0085) ve `invalid-label-only-newline` reddedilir. | [İlişkiler](vault-format.md#i̇lişkiler) |
| `relations/`, kaldırma | `remove-unreadable` çözülemeyen blokta kaldırmayı reddeder. `related-remove-all-block` çok satırlı listenin bütün öğelerini kaldırır; aradaki yorum kalır. | [İlişkiler](vault-format.md#i̇lişkiler) |

### Anma bağlama

İşlem kasa ve indeks gerektirir. Biçim testleri bu örnekleri yalnız dosya düzeni açısından denetler; depo katmanı işlemi uygular. `expected.md` girdiden yalnız `byteRange` aralığında farklıdır.

| `UnlinkedMentionTests` denetimi | Beklenti |
|---|---|
| Kasadaki diğer dosyalar | Değişmez |
| Yeniden okunan belge | Yalnız o bağlantı eklenmiştir |
| Olay saati ve görev alanları | Aynı kalır |
| Sorgu | Anma sorgudan çıkar |
| Aynı satırdaki diğer anmalar | Yeni bayt konumlarıyla kalır |
| Artımlı indeks | Tam yeniden kurulumla eşittir |
| İkinci uygulama | Aynı anma ikinci kez uygulanamaz |

| Bayat hedef türü | Testin kodda kurduğu durum |
|---|---|
| Satır | Satır ya da yazım değişti |
| Anma | Anma bu arada bağlandı |
| Konum | Satır kaydı ya da silindi |
| Dosya | Dosya ya da varlık silindi |
| Takma ad | Takma ad kalktı |
| İkiz satır | Dosya değişti. Örnek: `vaults/unlinked-mentions-hostile` içindeki `2026-03-01` günü. |

Bayat hedefte dosya ve indeks değişmez. Kural: [Tek geçişi bağlantıya çevirme](vault-format.md#tek-geçişi-bağlantıya-çevirme).

## `merge/` kümesi

| Davranış ailesi | Örnek vaka |
|---|---|
| Aynı, boş ya da eş zamanlı sürüm | `identical`, `empty-newer`, `equal-times-tie` |
| Satır sonu ve BOM | `crlf-newer-keeps-older-endings`, `bom-only`, `no-final-newline-older` |
| Salt okunur sürüm | `read-only-newer`, `read-only-older` |
| Frontmatter alanı ve yorumu | `frontmatter-comment-in-both`, `frontmatter-unreadable-newer`, `frontmatter-value-differs` |
| Hedef ilerlemesi | `goals-progress`, `goals-type-mismatch`, `goals-not-a-mapping` |
| Görev durumu ve metni | `task-closed-vs-text-changed`, `task-both-closed-date-only` |
| Olay ve blok | `events-both-added`, `event-text-both-changed`, `blocks-with-children` |
| Blok kimliği | `duplicate-ids`, `id-kind-mismatch`, `id-less-repeated-lines` |
| Serbest yazı | `free-text-diverged`, `free-text-reordered` |
| Bölge ve düzen | `region-only-in-newer`, `code-fence-lines`, `older-layout-keeps-newer-trailing-blank` |
| Son güvence | `unclosed-fence-falls-back` |

**Tablo, örnek dosyalarını ve `case.json` alanlarını verir.**

| Dosya ya da alan | Tür | Anlam |
|---|---|---|
| `a.md`, `b.md` | Markdown | İki sürümün baytları |
| `expected.md` | Markdown | Birleşmiş baytlar |
| `case.json`, `times` | `{ "a": 10, "b": 20 }` | Her sürümün değişiklik zamanı. Tam sayıdır; birim yoktur, yalnız sıra anlamlıdır. |
| `case.json`, `preserved` | dizi | Saklanacak sürümlerin alfabetik adları; hiçbiri saklanmıyorsa `[]` |

**Saklanan sürüm**, birleştirmenin `conflicts/` klasörüne yazdığı eski sürüm dosyasıdır. Kuralların kaynağı [Eşitleme çakışması](vault-format.md#eşitleme-çakışması) bölümüdür.

| Test yolu | Denetim |
|---|---|
| `ConflictMerge` | Sonuç `expected.md`, saklanacak sürümler `preserved` ile aynıdır. |
| `ConflictMerge`, sıra | İki veriliş sırası aynı baytları ve aynı saklanacak sürümleri verir. |
| `ConflictMerge`, kararlılık | Sonuç daha büyük bir zamanla her sürümle yeniden birleşince değişmez. Okunup yazılınca da aynı kalır. |
| Bağımsız kayıp denetimi | Her sürümün blokları, serbest yazı satırları, frontmatter alanları ve yorum satırları sonuçta vardır. Yoksa birleştirme o sürümü saklar. İstisnalar: [Birleştirme işlevi](vault-format.md#birleştirme-işlevi). |
| Son güvence | Adında `falls-back` geçmeyen örnekte `fellBack` yanlıştır. |
| Eşit zaman | Yeni sürümün bayt sırasıyla seçildiğini sınar. |
| Addaki bayt özelliği | [Adlandırma](#adlandırma) tablosundaki sözcüğü taşıyan örnekte en az bir Markdown dosyası o özelliği taşır. |
| `VaultStore.mergingDayCopy` | Core her örneği gün kopyası yolundan da koşar: önce `a` gün dosyası ve `b` kopyadır, sonra tersi. |
| Gün kopyası yolu, zaman | Zamanlar UTC saniyesidir. Test saniyenin bir kesrini ekler; kesir adı ve sırayı değiştirmemelidir. |
| Gün kopyası yolu, sonuç | Gün dosyası `expected.md` olur. Her saklanan sürüm `conflicts/2026-10-02 (conflict 19700101T0000SSZ).md` adıyla bayt bayt kendisidir. Kasada başka dosya kalmaz. |
| Gün kopyası yolu, tekrar | Kopya aynı baytlarla yeniden gelince kasa değişmez. |

## `recognition/` kümesi

| Davranış ailesi | Örnek vaka |
|---|---|
| Ad, takma ad ve belirsizlik | `names`, `ambiguous`, `alias-collision` |
| Türkçe harf, ek ve Unicode | `turkish`, `suffix`, `nfd` |
| Sözcük sınırı ve örtüşme | `boundaries`, `overlap`, `overlap-tie-first` |
| Korunan metin | `escaped-code`, `protected-addresses`, `markdown-links` |
| Bayt özelliği ve boş girdi | `crlf`, `bom-mixed-line-endings`, `table-crlf` |
| Yol hedefi | `path-link-target`, `root-path-link-target`, `unrepresentable-path-target` |
| Rakam adlar | `digit-names`, `mixed-digit-names-baseline` |
| Görev alanlı gün gövdesi | `task-fields` |
| Özel tip | `custom-book` |
| Takvim katılımcıları | `attendees` |
| Bağlanmamış anma sorgusu | `unlinked-mentions`, `unlinked-mentions-hostile` |

Kuralların kaynağı [Otomatik tanıma ve belirsizlik](vault-format.md#otomatik-tanıma-ve-belirsizlik) ve [Bağlantı yazımı](vault-format.md#bağlantı-yazımı) bölümleridir.

**Tablo, örnek dosyalarını ve alanlarını verir.**

| Dosya | Alan | Anlam |
|---|---|---|
| `entities.json` | `entities[]` | `file`, `kind` (`person` ya da `place`), `name`, isteğe bağlı `qualifier`, `aliases`, isteğe bağlı `linkTarget` |
| `entities.json` | `linkTarget` | Yazılacak wikilink hedefi; yoksa tanıyıcı uzantısız gövde adını kullanır. |
| `entities.json` | `usage[]` | İsteğe bağlı: `file`, `totalCount`, `lastDate`, `cooccurrences` (dosya yolundan birlikte geçilen gün sayısına eşlem) |
| `expected.json` | `mentions[]` | `line` (sıfır tabanlı), `byteRange`, `spelling`, `candidates`, `isAmbiguous`, `isCaseMismatch`, `isCertain` |
| `expected.json` | `unknownMentions[]` | Aynı konum ve yazım alanları; aday içermez. |
| `linked.md` | — | Yalnız kesin anmaların bağlandığı bayt çıktısı |
| `attendees.json` | `attendees[]` | Yalnız `attendees/`: `name` (takvimin verdiği ad; boş ya da e-posta olabilir) ve `isCurrentUser` |
| `expected.json` | `certain`, `ambiguous`, `unknown` | Yalnız `attendees/`, katılımcı sırasında. `certain`: `spelling` ve `file`. `ambiguous`: kırpık ad ve `candidates`. `unknown`: kırpık adlar. |
| `expected.json` | `vault`, `queries[]` | Yalnız `unlinked-mentions*`: her sorgu `entity` ve sıralı `mentions` taşır. |
| `expected.json` | `queries[].mentions[]` | `file`, `date`, `line` (sıfır tabanlı), `byteRange`, `spelling`, `isExplicit`, `isAmbiguous`, `isCaseMismatch` |

| Konu | Denetim |
|---|---|
| Yeniden tanıma | `linked.md` içinde kesin anma kalmaz. Temsil edilemeyen hedef yüzünden düz kalan anma istisnadır. |
| Bekleyenler | Öneri, belirsiz ve bilinmeyen anmalar kalabilir. |
| Rastgele testler | Bütün bilinen anmalara seçim verir ve tam bağlamanın eşgüçlülüğünü denetler. |
| `attendees/` | `input.md` ve `linked.md` yoktur. |
| `unlinked-mentions*` | `input.md` ve `entities.json` yoktur; girdi kasanın kendisidir. Kasadaki her varlığın bir sorgusu vardır. |
| Sorgu sırası | Yeni günden eskiye; gün içinde satır ve bayt sırası. |

**Tablo, vaka adından anlaşılmayan içeriği verir. Bu vakaların açıklaması fixture dosyasında yoktur.**

| Vaka | İçerik |
|---|---|
| `turkish` | `Işık`, yalnız Türkçe harf kuralını sınamak için Deniz'in sentetik takma adıdır. |
| `suffix` | `e`, Ece için eki ayrı ad saymayı engelleyen sentetik takma addır. |
| `overlap` | `Arıkan Selin Korkmaz` kadronun adlarından gelen sentetik konum takma adıdır. |
| `overlap-tie-first` | `Deniz Ece` ve `Ece Selin` kadronun ad parçalarından gelir. |
| `path-link-target` | Aynı gövde adı başka klasörde de varsa yol hedefini yazar; benzersiz ad kısa kalır. |
| `root-path-link-target` | Kasa kökündeki varlığı baştaki `/` ile yazar. |
| `unrepresentable-path-target` | Temsil edilemeyen yol hedefinde anmayı düz bırakır ve diğer kesin anmaları bağlar. |
| `escaped-code` | Kaçışlı wikilink düz metin kalır. |
| Korunan metin ailesi | E-posta, alan adı, etiket, kimlik, Markdown bağlantısı, sözdizimi komşuları ve frontmatter örnekleri değişmeyen baytları denetler. |
| `table-crlf` | Bağlayıcı, tabloda görünen metin ayırıcısını kaçırır. |
| `custom-book` | `@` anmasının özel tip wikilink'ine dönüşümü |
| `digit-names` | Tamamı rakam olan adlar: `12`, `2026`, `7`, `34`, `1907`. `Sayılar` ve `Rakamlar` sentetik varlıklarının rakam takma adları da aynı kurala uyar. |
| `digit-names`, düz kalanlar | Tek başına sayı, parantez ve tırnak içi, cümle sonu, `12'de`, `12 Ekim 2026`, `1. Elma`, telefon numarası, `12—14`, `12+5`, saat, tarih, ondalık, binlik ve aralık |
| `digit-names`, bağlananlar | `@12`, `(@12)`, `@12'de`; `@12:30` → `[[12]]:30`; `@30` → `[[Sayılar\|30]]`; `Sayılar 30` → `[[Sayılar]] 30` |
| `digit-names`, öteki içerik | Arap-Hint ve tam genişlik rakamlar, karışık ad `Daire 12:30`, NFD komşu metin, var olan bağlantının yanındaki sayı (`[[12]]:30`, `[[Deniz]]:12`) |
| `task-fields` | Tasks, Events ve Diary bölümlerindeki görev satırlarını taşıyan tam bir gün gövdesi. Tanıyıcı satırın yapısını ve görev alanlarını taramaz. |
| `task-fields`, sentetik varlıklar | Adı alan yazımıyla çakışan `2026-10-12` (takma adlar `12:30 Vapuru`, `⏫`) ve `Takvim` (takma adlar `📅`, `⏳`, `every`, `week`, `1`). Tanıyıcı bunları yalnız metinde geçtiklerinde bağlar. |
| `task-fields`, okunamayan kural | Kural sonraki alanda biter; ardındaki ad yine metindir: `🔁 her hafta ⏫ Deniz ile`. |
| `digit-names`, `task-fields` beklentisi | Fixture yazarı uygulamadan bağımsız, işaretli bir şablondan üretti. |
| `mixed-digit-names-baseline` | Rakam içeren ama tamamı rakam olmayan adlar: `Daire 12`, `3. Kat`, `2. Dünya Savaşı`, `7/24`, `1.250`, `12:30 Vapuru`, `R2-D2`. İlk 7 satır elle yazıldı; kalan 140 satırı tohumlu rastgele parçalar oluşturur. |

### Bağlanmamış anma sorguları

| Kasa | İçerik |
|---|---|
| `unlinked-mentions`, sorgunun kapsamı | Sorgu yalnız gün dosyalarındaki olay ve görev ilk satırlarının metnini tarar. Görev alt satırları, Diary paragrafı ve notlar listede yoktur. |
| `unlinked-mentions`, listelenmeyenler | Olay saati ve görev alanları (örnek: `📅 2026-10-12` içindeki `2026`), kod, var olan bağlantı, Markdown bağlantısı, URL, çitli kod. Var olan bağlantı başka varlığa bağlı aynı yazımı da kapsar. |
| `unlinked-mentions`, ad durumları | Türkçe ek (`Elif'le`, `İstanbul'da`), takma ad, iki varlığın ortak takma adı, yalnız harf büyüklüğüyle ayrışan yazım, aynı satırda iki geçiş, tireyle bitişik adlar |
| `unlinked-mentions`, ek durumlar | `@` ile açık anma, ayırt edicili varlık, emoji takma ad, NFD yazım, çift boşluklu çok sözcüklü ad |
| `unlinked-mentions`, Türkçe harf | `İSTANBUL` ve `istanbul`: ikisi de `İstanbul` okunur; `istanbul` harf boyu farkıyla öneridir. |
| `unlinked-mentions`, bayt | BOM, CRLF ve son satır sonu olmayan bir gün dosyası |
| `hostile`, ad yerleşimi | Aynı adın satırda 4 geçişi; biri ötekinin içinde geçen iki ad (`Ece`, `Ece Yalın`); 2 tür kesme işareti ve ek; noktalamaya bitişik ad |
| `hostile`, sözdizimi | Satır içi kod, köşeli parantez, takma adlı ve kapanmamış bağlantı, Markdown bağlantısı, URL, e-posta, etiket, HTML yorumu, tablo satırı, alıntı ve iç içe liste, saat biçimleri |
| `hostile`, özel varlık ve takma ad | Adı sayı ya da alan simgesi (`📅`, `🔁`, `x`) olan varlıklar; `^kimlik` ile ad çakışması; `\|`, `^`, `\`, `` ` `` içeren takma adlar |
| `hostile`, Unicode | Emoji ve birleşik karakter, NFC/NFD, Unicode satır ayırıcıları; `İ` ve `ı` takma adlı varlıkta `i` ve `I` yazımları |
| `hostile`, dosya ve kasa | Aynı dosya adlı iki varlık (yol hedefi), ayırt edicili varlık, çitli kod, ikiz satırlar, karışık satır sonlu bir gün |
| `hostile`, listelenmez | Görev alanının içi, yinelenen ikinci `📅` alanı ve `⏳ 2026-10-11` dahil. Okunamayan tekrar kuralının içi: `🔁 every week Elif ile`. Bağlantı içine yazılamayan yazım: `a]b`, `a[b`. |
| `hostile`, listelenmez | Çıplak rakam ad ve takma ad. `people/Sayı.md` adı `12`, takma adları `2026`, `7`, `30`. `12 kişi`, `- 12`, `12.30`, `2026-10-12` içindekilerin hiçbiri listelenmez. |
| `hostile`, listelenir | `people/Sayı.md` dosyasının rakam olmayan takma adı `09:05`; HTML yorumu içindeki olay, çünkü uygulamada da olaydır. |
| `hostile`, test | Testler bu kasada ve tohumlu rastgele satırlarda listedeki her anmayı tek tek bağlar. Sonuç ya yalnız o bağlantının eklendiği dosyadır ya da anma listede hiç yoktur. Sorgu, yazıcının reddettiği anmayı listelemez. |

### Takvim katılımcıları

Eşleme ad ya da takma adın tamamını [ad karşılaştırma anahtarıyla](vault-format.md#adlar-ve-karşılaştırma) karşılaştırır. `Irmak İnce` yalnız bu örnekte geçen kurgusal bir kişidir.

| Durum | Sonuç |
|---|---|
| Adla ya da takma adla (`Selin`) eşleşme; yalnız birinin takma adı (`Mert`) | Kesin |
| Aynı adı taşıyan ayırt edicili iki varlık (`Mert Aksu`) | Belirsiz |
| Bilinmeyen ad; noktalı küçük harfli `irmak ince`, çünkü varlığın anahtarı `ırmak ince` olur | Bilinmeyen |
| E-posta, boş, yalnız boşluk, cihaz sahibi | Hiçbir diziye girmez |
| NFD yazım `Baran Tunc` ve birleşen çengel; büyük harfli `IRMAK İNCE`: anahtarı `ırmak ince` | Eşleşir |
| Baştan sona boşluklu yinelenen ad | İkinci kez listelenmez |

## `index/` kümesi

| Örnek | Girdi | Beklenen |
|---|---|---|
| `index/sample/` | `vaults/sample/` | `expected.json`: kanonik indeks dökümü |
| `index/continuation/` | `input.md`: 3 satırlık tek görev bloğu | `expected.json`: kanonik döküm. Girintili başlık ayrı başlık ya da paragraf üretmez. |
| `index/entity-fields/` | `vaults/entity-fields/`, `changed.md`, `added.md`, `removed.md` | `expected.json`: `file`, `key`, `kind`, `value` satırları |
| `index/cadence/` | `vaults/cadence/` | `fields.json`, `anniversaries.json` |

**Tablo, kanonik döküm dizilerinin alanlarını ve sırasını verir.**

| Dizi | Zorunlu alanlar | İsteğe bağlı alanlar | Sıra |
|---|---|---|---|
| `files` | `path`, `kind`, `readable` | `date` | NFC yolun kod noktası sırası |
| `entities` | `file`, `kind`, `name`, `comparisonKey` | `qualifier`, `goalKey`, `period`, `goalKind`, `target`, `unit` | Dosya yolu |
| `aliases` | `file`, `ordinal`, `name`, `comparisonKey` | | Dosya yolu, `ordinal` |
| `blocks` | `file`, `ordinal`, `kind`, `firstLine`, `lastLine`, `text`, `section`, `ownsIdentifier` | `time`, `status`, `rawStatus`, `identifier`, `headingLevel`, `dueDate`, `startDate`, `doneDate`, `priority`, `project` | Dosya yolu, `ordinal` |
| `links` | `file`, `ordinal`, `line`, `byteStart`, `byteEnd`, `target`, `targetKey`, `embedded` | `block`, `key`, `entry`, `anchorKind`, `anchor`, `displayText`, `resolvedFile` | Dosya yolu, `ordinal` ya da hedef anahtarı |
| `goalLogs` | `file`, `key`, `date`, `kind`, `value` | | Dosya yolu |
| `entityFields` | `file`, `key`, `kind`, `value` | | Dosya yolu, anahtarın bayt sırası |

**Tablo, döküm değerlerinin yazım kurallarını verir.**

| Konu | Kural |
|---|---|
| Eksik isteğe bağlı alan | JSON anahtarı yazılmaz |
| `ordinal` | Sıfır tabanlı kaynak sırası |
| `line`, `firstLine`, `lastLine` | Bir tabanlı, iki ucu dahil |
| `byteStart`, `byteEnd` | Sıfır tabanlı, sonu hariç |
| `headingLevel` | `heading` bloğunda 1–6 |
| `priority` | Kaynak emoji |
| `project` | İlk proje adı |
| Görev `text` | Alanları çıkarılmış sadeleştirilmiş metin |
| `goalLogs.value` | Metin: boolean standart `true`/`false`, sayı özgün yazım, diğer tür ham yazım |
| `entityFields.kind` | `date`, `number` ya da `boolean`; `value` özgün yazımdır |
| Dökümün dışı | Değişiklik zamanı, boyut ve içerik özeti |

| Konu | Ayrıntı |
|---|---|
| `index/sample/` sayıları | `expected.json` dizilerinin uzunluğudur; belge yinelemez. `templates/`, `conflicts/` ve `.app/` dosyaları dökümde yoktur. |
| Tam döküm | Paragraf metinlerini, kod çitlerini ve frontmatter bağlantılarını da denetler. |
| Sentetik kasalar | Testler bunları geçici dizinlerde kurar. |

### Varlık alanları

| Grup | `vaults/entity-fields/` içeriği |
|---|---|
| İndekslenen | Kişi: boşluklu, Türkçe karakterli ve tırnaklı anahtar, satır sonu yorumu, büyük harfli `Name` |
| İndekslenen | BOM ve CRLF taşıyan kişi, konum, `date` alanlı özel kitap tipi |
| Metin olarak okunan, dışarıda | Tırnaklı değer, `2026-13-40`, `2026-02-29`, `2026-1-2`, zaman damgası, `1e3`, `012`, `0x1F`, `.5`, `yes`, `off`, `tRue` |
| Dışarıda | Boş, liste, eşlem, ham ve kimlik alanları; çözülemez frontmatter; hedef, gün ve not dosyaları |
| `changed.md` | Alan değişimi ve silme |
| `added.md` | Alan ekleme |
| `removed.md` | Tüm alanların silinmesi |

Tam ve artımlı eşdeğerlik, dosya silme ve yeniden kurulum aynı kasayı kullanır. Eski sürümlü indeksin silinip doldurulması da aynı kasayı kullanır. Güncel şema sürümü `Schema.swift` içindedir.

### Ritim alanları

| Dosya | İçerik | Dışarıda kalan |
|---|---|---|
| `index/cadence/fields.json` | Kişi dosyalarındaki ritim alanlarının indeks satırları | Metin ve geçersiz tarih yazımları; kitabın `cadence_snoozed_until` alanı, çünkü kitap kişi değildir |
| `index/cadence/anniversaries.json` | Önemli tarih sorgusunun beklenen satırları: doğum günü ve `bitirme` | 3 ritim anahtarı |

## Tek dosyalı uygulama kümeleri

| Örnek | Girdi | Beklenen | Denetim |
|---|---|---|---|
| `diary/edit/` | `input.md`: gün dosyası | `expected.md`: Diary bölümü değiştikten sonraki tam dosya | Frontmatter ve Events bölümü bayt bayt aynı kalır. |
| `diary/weekly-review/` | `input.md`: incelemeden önceki gün dosyası | `expected.md`: soru kartları yazıldıktan sonraki tam dosya | Her dolu kart tek serbest not satırıdır: "Ne iyi gitti: …". Görev gibi görünen cevap yazı olarak kalır. |
| `entities/fields/` | `input.md`: kurgusal kişi dosyası | `value.md`: alan değeri değişti. `aliases.md`: takma ad listesi yazıldı. | Yalnız hedef anahtarın satırı değişir. |

## `entity-types/` kümesi

| Örnek | Girdi | Beklenen | Ne sınar |
|---|---|---|---|
| `valid` | `input.json` | `expected.json`: `ids`, `issue` | Geçerli tanım |
| `invalid` | `input.json` | `expected.json` | Bozuk JSON |
| `collision` | `input.json` | `expected.json` | Ayrılmış id; örnekte `person` |
| `duplicate` | `input.json` | `expected.json` | Yinelenen id |
| `create` | `operation.json` | `expected.md` | Oluşturma için tam Markdown çıktısı |
| `preserve` | `input.json`, `operation.json` | `expected.json` | Bir tanım değişirken hedef dışındaki JSON baytları kalır |
| `reserved-related` | `input.json` | `expected.json` | Şemada ayrılmış `related` alanını reddeder |

| Kasa | İçerik | Denetim |
|---|---|---|
| `vaults/typed/` | Kitap tipi, 2 kurgusal kitap ve bir şablon. `.app/types.json` text, date, number, boolean ve link alanlarını tanımlar. | Tip tanımı kalkınca uygulama kitapları not olarak indeksler; dosya baytları değişmez. |
| `vaults/gallery/` | Hazır tip galerisinin 10 tipi. `.app/types.json` galerinin tanımlarıdır. `templates/<id>.md` uygulamanın yeni tip için yazdığı şablondur. | Testler Core galerisini bu dosyalarla karşılaştırır. Testler her tipi boş kasada oluşturur ve aynı baytları bekler. |
| `vaults/gallery/`, `Örnek <Ad>.md` | O şablondan oluşturulan varlığın tam baytları: `type`, `name` ve tanımdaki sırayla boş alanlar. | Aynı karşılaştırma |

Kural kaynağı: [Varlık tipleri](vault-format.md#varlık-tipleri).

## `rename/` kümesi

| Davranış ailesi | Örnek vaka | Sınanan ayrıntı |
|---|---|---|
| Gövde bağlantıları ve bayt özelliği | `body-mixed-line-endings-bom-no-final-newline` | Hedef çevresindeki boşluk, çapa, görünen metin, `\|` tablo ayırıcısı, `.md` ve yol önekleri, gömme, kod koruması |
| Frontmatter bağlantıları | `frontmatter` | Scalar, liste ve eşlem bağlantıları, YAML kaçışı, ham alan bildirimi |
| Ayırt edici ve aynı dosya adı | `qualifier`, `same-filename` | `same-filename` yalnız metadata yazar. |
| Geçersiz UTF-8 kaynak | `read-only-invalid-utf8` | Kısmi başarı |
| Aynı satırda tırnaklı çoklu bağlantı | `list-2-grows`, `list-2-shrinks`, `list-3-grows`, `list-3-shrinks` | İç içe tırnaklı 2 ya da 3 bağlantı güncellenir. Tırnaksız ve tırnaklı blok öğeleri ve komşu değerler kalır. |
| Hedef taşımayan alanlar | `unrelated-fields`, `empty-list-item` | BOM, kaçışlı tırnak, yorumlar, ham, eşlem ve liste alanları bayt bayt kalır. Boş blok liste öğesi yerinde kalır. |

**Tablo, örnek dosyalarını ve `case.json` alanlarını verir.**

| Dosya ya da alan | Anlam |
|---|---|
| `input/`, `expected/` | Küçük girdi kasası; tam beklenen dosyalar |
| `path`, `name`, `qualifier`, `newPath` | Yeniden adlandırılan dosya, yeni ad, isteğe bağlı ayırt edici, beklenen yeni yol |
| `failures`, `failureDetails[]` | Beklenen bildirim sayısı ve ayrıntısı: `path`, `kind`, `detail`. `detail` ham alan adı ya da hata mesajının beklenen parçasıdır. |
| `updatedFiles` | Sıralı güncellenen dosyalar |
| `afterIndex` | İsteğe bağlı: `path` ve ham bayt dizisi `bytes`. İndeksten sonra diskte değişen kaynak dosyayı modeller. |

Test dosya listesini, tüm baytları ve artımlı indeksin sıfırdan üretimle eşdeğerliğini denetler. Kural kaynağı: [Yeniden adlandırma](vault-format.md#yeniden-adlandırma).

## `import/` kümesi

| Örnek | Girdi | Beklenen sonuç |
|---|---|---|
| `empty` | Boş klasör | 6 kasa klasörü, 2 şablon ve `.app/vault.json` oluşur |
| `obsidian-days-only` | Yalnız gün dosyası olan Obsidian kasası | `.obsidian/` kalır; kök ve `daily/` günleri taşınmaz |
| `untyped-entities` | `type` alanı olmayan varlık dosyaları; CRLF ve yorumlu dosya | `type` alanı eklenir |
| `already-prepared` | Zaten hazır kasa | Bayt değişmez |
| `case-variant-diary` | Harf farkıyla `Diary/` | Eksik sayılmaz; `diary/` oluşmaz |
| `unreadable-frontmatter` | Okunamayan frontmatter | Dosya atlanır; uygulama dosyaya dokunmaz |
| `newer-format-version` | Desteklenmeyen `vault.json` sürümü | Hazırlama yazmaz |

**Tablo, örnek dosyalarını, `case.json` alanlarını ve test adımını verir.**

| Dosya ya da alan | Tür | Anlam |
|---|---|---|
| `before/` | klasör | Girdi kasası. Test geçici köke kopyalar. |
| `expected/` | klasör | Hazırlama sonrası dosya ağacı. Test dosya baytlarını karşılaştırır. Ağaç eşitliği için yer tutucu dosya taşır. |
| `options` | nesne | Yazıcıya verilen onay seçenekleri: `folders`, `settings`, `types` |
| `apply` | boolean | `false` ise test yalnız taramayı karşılaştırır ve yazmaz. |
| `emptyBefore` | boolean | Doğruysa girdi boştur ve test `before/` klasörünü kopyalamaz. Git boş klasör tutmaz. |
| `report` | nesne | `VaultImportScanner.inspect` özeti: `missingFolders`, `caseVariantFolders`, `missingTemplates`, `needsSettings`, `canPrepare`, `markdownCount`, `diaryDays`, `externalDays`, `typed`, `candidates`, `skipped` |
| `result` | nesne | `VaultImportWriter.apply` özeti: `created`, `typed`, `skipped`, `failures`. `created` içinde sonu `/` olan öğe klasördür. |
| `expectedDirectories` | dizi | Hazırlama sonrası var olması gereken klasör adları |
| `generatedTemplates` | eşlem | Yolu `person` ya da `place` değerine eşler. Şablon baytları süreç diline bağlıdır; test içeriği `VaultImportBootstrap.template` ile üretir. |

Kural kaynağı: [Var olan kasayı açma ve hazırlama](vault-format.md#var-olan-kasayı-açma-ve-hazırlama).

## `dates/` kümesi

| Dosya | İçerik |
|---|---|
| `cases.json` | Doğal tarih ayrıştırmanın dilden bağımsız sözleşmesi |
| `regression-inputs.md` | Tarih, miktar ve gelecek hafta günü düzeltmelerinin kurgusal ham girdileri; beklentileri `cases.json` içinde |
| `quick-entry.json` | Hızlı giriş görev çözümlemesinin beklenen sonuçları |
| `quick-entry-inputs.md` | `quick-entry.json` vakalarının ham girdileri |
| `recurrence.json` | Tekrar kuralından sonraki görev tarihinin hesabı |
| `birthday.json` | Kişi dosyasındaki doğum günü alanının okunması |
| `birthday-person.md` | Kurgusal kişi dosyası; ilk okunabilen doğum günü alanı ikincisidir |

**NOT:** `regression-inputs.md` ve `quick-entry-inputs.md` dosyalarını yalnız gidiş dönüş testi okur; tarih testleri girdiyi JSON dosyasından alır.

| Dosya | Alan | Anlam |
|---|---|---|
| `cases.json` | `language`, `input` | Sıralı `tr`/`en` listesi; ham girdi |
| `cases.json` | `expectedDate`, `remainder` | ISO gün ya da `null`; ham kalan metin. Tarih yoksa metin aynen kalır. |
| `cases.json` | `confidence` | `exact`, `assumed` ya da `null` |
| `cases.json` | `expression`, `weekStartsOnMonday` | İsteğe bağlı: beklenen özgün ifade; hafta başı (varsayılan `true`) |
| `quick-entry.json` | `language`, `input`, `remainder` | `cases.json` ile aynı anlam |
| `quick-entry.json` | `suppressed` | Özgün UTF-8 `[başlangıç, bitiş)` çiftleri |
| `quick-entry.json` | `tokens[]` | `range`, `expression`, `kind` (`recurrence`, `priority`, `date`), `value` (tekrar kuralı, öncelik adı ya da ISO gün), `confidence` <!-- sır değil --> |
| `birthday.json` | `key`, `value` | Alanın anahtarı ve değeri |
| `birthday.json` | `expected` | `{month, day, year}`; yılsızda `year` `null`, okunamayan değerde `expected` `null` |
| `recurrence.json` | `rule` | Tekrar kuralı: `every month`, `every monday`, `every month when done` |
| `recurrence.json` | `after`, `completedOn` | Görevin önceki tarihi; tamamlama günü |
| `recurrence.json` | `expected` | Beklenen sonraki tarih; hesap taşarsa `null` |

| Dosya | Vaka aileleri | Ek denetim |
|---|---|---|
| `cases.json` | Göreli, haftalık ve mutlak tarih; geçersiz günler; yıl ve artık yıl sınırları; dil sırası; Türkçe harfler; sözcük sınırı; anma, kod ve bağlantı koruması; saatlerin korunması; silmede boşluk baytları | Test ifade aralığını özgün ifadenin UTF-8 baytlarıyla bağımsız karşılaştırır. |
| `quick-entry.json` | Türkçe ve İngilizce zincirler; Türkçe bayt ofsetleri; iki uçtaki ünlemler; miktar ve gelecek hafta günü; kod, bağlantı ve anma koruması; tam ve kısmi bastırma; çıkarma sonrası birleşen tarih parçaları | Test özgün aralıkları çıkarır ve kalan metni yeniden kurar. 2.000 belirlenimci rastgele girdi mevcut zincirle değer ve metin eşitliğini denetler. |
| `birthday.json` | Anahtar yazımları, harf boyu, yıllı ve yılsız biçim, artık gün, geçersiz değerler | Yok |
| `recurrence.json` | Ay sonu, artık gün, `when done`, yıl geçişi; son 2 vaka tarih sınırını ve sayı taşmasını sınar | Yok |

Kural kaynağı: [Tekrarlayan görevler](vault-format.md#tekrarlayan-görevler), [Hızlı girişte öncelik ve tekrar](vault-format.md#hızlı-girişte-öncelik-ve-tekrar), [Tarih ifadesindeki ekler](vault-format.md#tarih-ifadesindeki-ekler), [Doğum günü alanı](vault-format.md#doğum-günü-alanı).

## `goals/` kümesi

| Parça | Girdi | Beklenen |
|---|---|---|
| `cases.json` | Hedef tanımı ve günlük kayıtlar | Hesap sonucu |
| `series.json` | Günlük değerler ve dönem tanımı | Günlük seri, hareketli ortalama, hafta ve ay toplamları |
| `writes/` | `cases.json` ve aynı klasördeki Markdown çiftleri | Yazma sonrası tam baytlar |
| `creation/` | Boş `input.md` | `boolean-expected.md`, `number-expected.md`, `milestone-expected.md` |

**Tablo, JSON alanlarını verir.**

| Dosya | Alan | Anlam |
|---|---|---|
| `cases.json` | `definition` | `id`, `key`, `name`, `period`, `kind`, `target` |
| `cases.json` | `logs[]` | ISO `day` ve boolean ya da sayı `value` |
| `cases.json` | `heatmapFrom`, `heatmapTo` | İki ucu dahil harita aralığı |
| `cases.json` | `expected` | `done`, `target`, `streak`, `longestStreak`, `isPendingToday`, `score`, `yearDone`, `periodStart`, `periodEnd`, `heatmap` |
| `cases.json` | `expected.score` | Günlük hedefte 0–100 tam sayı. Haftalık, yıllık, kilometre taşı ve ölçülen günü olmayan günlük hedefte `null`. |
| `cases.json` | `expected.heatmap` | ISO günü `none`, `partial`, `full`, `forgiven` ya da `forgivenPartial` değerine eşler. |
| `series.json` | `daily[]` | Girdi: `span`, `target`, `logs`. Beklenti: `values`, `indices`, `segments`, `average`, `metCount`, `peakIndex`, `averages` (`index`, `value`, `segment`). |
| `series.json` | `periods[]` | Girdi: `period`, `kind`, `target`, `count`, `logs`. Beklenti: `totals`, `starts`, `pace`, `total`, `peakIndex`. |
| `series.json` | `logs[].value` | `"nan"`, `"inf"` ve `"-inf"` dizgileri bu sayıları gösterir; JSON NaN taşımaz. |
| `writes/cases.json` | `day`, `key`, `value` | Gün, hedef anahtarı, değer (boolean, sayı ya da `null`) |
| `writes/cases.json` | `input`, `expected` | Aynı klasördeki Markdown yolları; eksik girdi için `input` `null` |
| `creation/cases.json` | `input`, `expected`, `name`, `period`, `kind` | İsteğe bağlı `target` ve `unit`; kilometre taşı vakası `target` taşımaz. |

**Tablo, vaka ailelerini verir. Vakaların açıklaması dosyada yoktur; `id` vakayı adlandırır.**

| Parça | Vaka aileleri |
|---|---|
| `cases.json`, temel | Günlük, haftalık ve yıllık boolean ve sayı hedefleri; eşik, boşluk, bugün ve dönem bekliyor durumları; pazartesi ve pazar, yıl ve artık yıl |
| `cases.json`, bozuk veri | Yinelenen gün, tür uyuşmazlığı, gelecek kayıtları |
| `cases.json`, günlük af | [Zincir](vault-format.md#zincir) tablosundaki dizilerin her biri; ek olarak art arda 2 kaçırma ve baştaki ile sondaki kaçırma |
| `cases.json`, bekleme | Dün kaçmış ve bugün bekleyen hedef; 2 gün kaçmış ve bugün bekleyen hedef |
| `cases.json`, en uzun zincir | Gün aşırı geçmiş (en uzun 2); iki af tek koşuda (en uzun 5) |
| `cases.json`, öteki af | Bugün yapılınca süren zincir; hedefin ilk ve ikinci günü; katkısız ve kısmi katkılı affedilen gün |
| `cases.json`, skor | 30 günden uzun geçmiş; paydaya girmeyen bugün; ölçüm günü olmayan hedef; skora girmeyen eşik altı gün |
| `cases.json`, uç tarih | Çok eski tek kayıt; geçmişte kalan af almış en uzun seri; yaz saati gün sınırı; yıl ve artık gün sınırı |
| `series.json`, `daily` | Boş, seyrek ve dolu seri; görünür aralıktan önceye uzanan 7 günlük pencere; üç kayıt eşiği; çizgi kırılması; eşit hedef; son, gelecek ve türü uymayan kayıt; negatif ve NaN; sıfır; eşit tepede en yeni gün |
| `series.json`, `periods` | Her iki dönemde boş, süren dönem sınırı ve dolu veri; haftada pazartesi ve pazar; yılda yıl geçişi, ilk kova ve bugün; haftalıkta negatif ve NaN; özel dönem sayısı; grafik gösterilmeyen türlerde `expected: null` |
| `writes/` | Örnek kasanın 31 kaydı ve Spor, Kitap, Su tanımları korunur. Spor 14 ve 21 Eylül 2026 haftalarında üçer günle başarılıdır. `milestone-*` kilometre taşının tamamlanmasını ve geri alınmasını sınar. |
| `creation/` | Her `*-expected.md` yeni hedef dosyasının tam baytlarıdır ve bir vakaya bağlıdır. |

| Konu | Kural ya da denetim |
|---|---|
| Beklentinin kaynağı | Swift hesapları değil, sözleşmeden bağımsız sabitler. Haftalık ve yıllık zincir afsız kurala uyar. |
| Seri hesabı | Kayıtsız gün sıfır sayılmaz. Bir günün son kaydı geçerlidir. Türü uymayan ya da geçersiz son kayıt o günü 0 yapar; kural `GoalProgress` ile aynıdır. |
| `writes/` testi | Tam çıktı baytları ve artımlı indeksin yeniden üretimle eşitliği |
| `creation/` testi | Test her vakayı boş kasada oluşturur; tam baytları ve indeksin okuduğu tanımı sınar. |

Kural kaynağı: [Hedef dosyası](vault-format.md#hedef-dosyası), [Zincir](vault-format.md#zincir), [İlerleme skoru](vault-format.md#i̇lerleme-skoru), [Isı haritası](vault-format.md#isı-haritası).

## `goal-chain/` kümesi

| Alan | Anlam |
|---|---|
| `start`, `sequence` | İlk ISO gün ve gün başına `1` (yapıldı), `0` (yapılmadı), `?` (kayıt yok) dizisi. Son gün bugündür. |
| `period`, `kind` | Hedef tanımını seçer. Sayı hedefinde hedef 2, yapılmış katkı 2, kaçırılmış katkı 1'dir. |
| `expected` | Zincir, en uzun zincir, bekleme bayrağı, skor, bakiye ve kesinleşmiş ISO harcama tarihleri |
| `summary` | `true` ise test dönem özetinin zincirini de sınar. |

| Parça | İçerik |
|---|---|
| `cases.json` | [Zincir günü](vault-format.md#zincir-günü) kuralının elle sayılmış beklentileri. `id` vakayı adlandırır: `seventh-reward`, `cap-three`, `pending-exhausted`, `weekly-no-grace`. |
| `summary-ended-spends` | 31 Ağustos–20 Eylül geçmişinden bitmiş 14–20 Eylül haftasının zincirini sınar. |
| `query/` | `two-consecutive-spends` vakasının gerçek Markdown hedefi ve gün dosyaları. İndeks sorgusu bakiyeyi ve harcama listesini döndürür. |
| `query/` denetimi | Dosya baytları sorgudan önce ve sonra aynıdır. `sample` kasası değişmez. |

## `summaries/` kümesi

| Dosya | Kasa | Ne sınar | Vaka açıklaması |
|---|---|---|---|
| `weekly-review-text.json` | yok | Haftalık gözden geçirme metni | `id` |
| `cases.json` | `vaults/sample/` | Dönem özeti | Aşağıdaki tablo |
| `cadence.json` | `vaults/cadence/` ve satır içi | Görüşme ritmi | Aşağıdaki tablo |
| `important-dates.json` | `vaults/anniversaries/` | Önemli tarihler | `id` ve aşağıdaki tablo |
| `on-this-day.json` | `vaults/history/` | Bu gün geçmişte | `id` ve aşağıdaki tablo |
| `period-rhythm.json` | `vaults/rhythm/` | Yıl dönemi, aynı tarihe kadar karşılaştırma, ritim birimleri, ilk kez geçenler, boş dönemde açık görevler | Aşağıdaki tablo |
| `year-writing.json` | `vaults/rhythm/` ve satır içi | Özetler'in yazılan günler haritası | Aşağıdaki tablo |
| `weekly-rhythm.json` | `vaults/rhythm/` ve satır içi | Haftalık incelemenin kısa ritmi | Aşağıdaki tablo |
| `task-flow.json` | yok | Açık görev eğrisi: birim sonu envanteri, başlangıç, bitiş ve en yüksek birim | Aşağıdaki tablo |
| `entity-density.json` | yok | 12 takvim ayı çubuğu ve 90 günlük şerit hesabı | Dosyadadır: `description` |
| `weekday-distribution.json` | `vaults/rhythm/` ve satır içi | Özetler'in haftanın günleri yazma oranı | Aşağıdaki tablo |

Fixture yazarı bütün beklentileri elle saydı. Sayıların tanımı [Ekranlar](screens.md) "Özetler" bölümündedir. `period`, `containing`, `today`, `vault` ve `days` alanları "Ortak alanlar" tablosundadır.

**Tablo, her dosyanın kendine özgü alanlarını verir.**

| Dosya | Girdi alanları | Beklenti alanları |
|---|---|---|
| `cases.json` | Ortak alanlar | `range`, `previousRange`, `counts`, `previous`, `change`, `people`, `places`, `goals`, `empty` |
| `cases.json`, `people`, `places` | — | İlk 5 öğe: yol kimliği, görünen ad, `count`, `change` |
| `cases.json`, `goals` | — | `done`, `target`, `contribution`, `streak`, `change`, `streakChange`, `score`, `completionDate` |
| `period-rhythm.json` | Ortak alanlar | `cases.json` alanları, ölçülen aralıklar, `isRunning`, `units`, `previousUnits`, `firstPeople`, `firstPlaces`. Birim: `start`, `end`, `events`, `writtenDays`, `measuredDays`, `writing`. |
| `year-writing.json` | `year` | `measuredEnd` (ölçümün son günü; `null`: yıl başlamadı), `monthDays`, `monthWritten`, `writtenDays`, `eventDays`, `diaryDays` (yalnız günlük yazısı olan günler) |
| `weekday-distribution.json` | Ortak alanlar | Pazartesi'den Pazar'a 7 elemanlı `totalDays`, `writtenDays`, `events`; `leadingWeekday` (0 Pazartesi, 6 Pazar; `null`: yazılan gün yok) |
| `weekly-rhythm.json` | `range`, `previousRange` | Gün başına `date`, `events`, `previousEvents`, `writing` (`full`, `none`, `notStarted`); toplam `events`, `previousEvents`, `change`, `isRunning` |
| `task-flow.json` | `tasks[]`: `created`, `status`, `due`, `done` | `units` ve `previous` için `id`, `range`, `measuredEnd`, `open`; ayrıca `unitCount`, `opening`, `closing`, `peak` (ilk en yüksek birimin kimliği) |
| `entity-density.json` | `days` | `months` (`month`, `count`, `isCurrentMonth`), `totalYearDays`, `busiestMonth`, `busiestMonthCount`, `recentDays` (`date`, `isMentioned`, `isToday`), `recentDayCount`, `averageInterval`, `hasHistory` |
| `weekly-review-text.json` | `title`, isteğe bağlı `summaryLines`, `selectedLines`, `note` | `[String]`: önce hazır yerel özet satırları, sonra seçili satırlar ve not |
| `cadence.json` | `spellings`; vakada `source`, `threshold` | Sıralı `overdue` (`id`, `elapsedDays`, `overdueDays`) ve ad sıralı `never` |
| `important-dates.json` | Ortak alanlar | Tarih, `daysUntil`, `year`, `file` ve `key` satırları |
| `on-this-day.json` | Ortak alanlar | `null` ya da `day`, `people` (en çok 2: yol kimliği ve ad), `place` (`null` olabilir), `otherYears` |

**Tablo, hesap kurallarını ve ek denetimleri verir. Kurallar bu belgeye ait değildir; asıl kaynakları yazılana kadar burada durur.**

| Dosya | Kural ya da denetim |
|---|---|
| `cases.json` | Test bir vakada yalnız taşınan alanları karşılaştırır. `summaryTasks()` sorgusu aynı dört görev sayısını aynı beklentilerle sınar. |
| `cases.json`, skor | Günlük skor dönemin son günüyle biten 30 günün hesabıdır. Son gün kaçırılmışsa paydaya girer. İlk 4 beklenti bugünsüz, dönemi bitmiş sayarak yazıldı. |
| `cases.json`, ek testler | Core testleri pazartesi, yıl ve artık ay sınırlarını, geçmiş görev envanterini, yıllık ve kilometre taşı katkısını da sınar. Sentetik geçici kasa frontmatter bağlantısının dışlanmasını ve artımlı indeks eşitliğini kanıtlar. |
| `task-flow.json` | Önceki seri bütün dönemi ölçer. Süren birim bugünde kesilir; başlamamış birim yoktur. Açık sayımı dönem özetiyle ortak koşulu kullanır. Bitiş tarihi gelecekte olan görev de envantere girer. |
| `weekday-distribution.json` | Süren dönemde payda bugüne kadarki günlerdir. Eşit oranda olayı çok olan gün seçilir. Yine eşitse haftanın ilk günü seçilir. |
| `weekly-rhythm.json` | Aralığın N. günü önceki aralığın N. günüyle karşılaştırılır. Toplamlar yalnız bugüne kadarki günleri sayar. Önceki günün çubuğu bugünden sonraki gün için de durur. |
| `weekly-review-text.json` | Test çıktıyı gerçek ayrıştırıcıyla yeniden okur; çıktı görev, olay, bölüm ve frontmatter üretmez. Günlük ekleme yazıcısı satırları değiştirmeden yazar. |
| `cadence.json`, `spellings` | `cadence_days` yazımının pozitif tam sayıya dönüp dönmediği: `30` ve `+30` döner. `0`, negatif, kesir (`30.0` dahil), başı sıfırlı, başı boşluklu, `Int` sınırını aşan ve metin dönmez. |
| `cadence.json`, sıra | Sıra eşiğin ne kadar aşıldığına bakar. Eşitlikte yol sırası geçerlidir ve girdi sırasından bağımsızdır. Taşan ritim yazımı genel eşiğe düşer. |
| `cadence.json`, hiç görüşülmemiş | Kişi ritmi olsa da ayrı gruptadır; önce ad, sonra yol sırasındadır. Duraklatma ya da erteleme taşıyan kişi orada da görünmez. |
| `important-dates.json` | Sıra tarih, alan adı, dosya yoludur. Pencere bugün dahil 7 gündür. |

### Vakalar

**Tablo, açıklaması fixture dosyasında olmayan vakaların ne sınadığını verir.**

| Dosya | Vaka | Ne sınar |
|---|---|---|
| `cases.json` | `week-14-20`, `monday-21-27` | Pazartesi haftaları: 19 ve 21 olay, 7'şer yazılan gün |
| `cases.json` | `september` | 40 olay ve 14 gün. Spor hedefi 15'tir, çünkü Eylül 5 pazartesi haftasına değer; Kitap 600, Su 240. |
| `cases.json` | `october-transition-empty` | Boş Ekim: 0 olay ve 0 gün; dönem sonu taşınan geciken görev 11, tarihsiz açık görev 1 |
| `cases.json` | `october-running-source-less` | Ekim 11 Ekim'de süren aydır. Proje dosyasındaki 2 görev bugün açıktır: tarihsiz sayısı 3. Önceki dönem bu 2 görevi aynen taşır: önceki tarihsiz 2, fark 1. Vaka yalnız aralık ve sayı alanlarını taşır. |
| `cases.json` | Kitap zinciri | 17 ve 18 Eylül art arda kaçtığı için zincir biter. |
| `cases.json` | Su zinciri | 17 ve 24 Eylül af alır ama zincire katkı vermez. 19 Eylül af almaz: önündeki 17 Eylül affedilmiş gündür. Zincir 20 Eylül'de 1, 23 Eylül'de 4, 27 Eylül'de 6'dır. |
| `task-flow.json` | `empty`, `running-week`, `finished-leap-month`, `running-year`, `future-period`, `calendar-lower-bound` | Boş veri; bugüne kadar süren hafta; artık yıldaki bitmiş Şubat; süren yıl; başlamamış dönem; takvimin alt sınırı |
| `task-flow.json` | `running-month` | Önceki ayından daha fazla dilimi olan süren ay |
| `task-flow.json` | `inventory-exclusions` | İptal ve tamamlanma tarihsiz görevler. `today` `null` olduğu için kaynak günü olmayan görev sayılmaz. |
| `task-flow.json` | `source-less-opens-today` | Kaynak günü olmayan görev bugünden itibaren açıktır: 7 Ekim noktası 3, önceki günler 1; önceki hafta değişmez. |
| `period-rhythm.json` | `year-running-to-same-date` | 2026 yılı 7 Ekim'de sürer: 1 Ocak–7 Ekim arası 10 olay, 7 yazılan gün. Önceki yıl 7 Ekim 2025'e kadar sayılır: 3 olay. 9 Ekim'in 4 olayı sayıya girmez. Kasım ve Aralık başlamamış birimdir. |
| `period-rhythm.json` | `week-running-to-same-weekday` | 5–11 Ekim haftası çarşamba sürer: 4 olay. Önceki hafta çarşambaya kadar sayılır: 3 olay. Bütün önceki haftanın değeri 6'dır. |
| `period-rhythm.json` | `month-slices-from-the-first` | Ekim 2025: 1–7, 8–14, 15–21, 22–28, 29–31. Eylül 2025 dilimlerinin sonuncusu 29–30'dur. İlk kez geçen kişi Nehir Ak, konum Rüzgâr Kafe'dir. |
| `period-rhythm.json` | `empty-week-carries-open-tasks` | 10–16 Ağustos 2026 boştur. 3 Ağustos'tan 1 devreden ve 1 tarihsiz açık görev kalır. |
| `year-writing.json` | `running-year-ends-today` | 2026 yılı 7 Ekim'de sürer: Ekim'in 7 günü ölçülür, Kasım ve Aralık boştur. 4 Ekim yalnız günlük yazısıdır. 3 Ağustos'ta yalnız görev vardır; gün yazılmamıştır. 9 Ekim sayılmaz. |
| `year-writing.json` | `ended-year-counts-every-day` | 2025 bitmiştir: 365 gün ölçülür, 2 olaylı gün. |
| `year-writing.json` | `year-not-begun` | 2027 başlamamıştır: hiçbir gün ölçülmez. |
| `year-writing.json` | `empty-leap-year-without-today` | `today` yoksa bütün yıl ölçülür; 2024'te Şubat 29 gündür. |
| `year-writing.json` | `first-day-adds-rows-of-one-date` | 1 Ocak'ın iki satırı toplanır ve gün olaylıdır. 2025 satırı ve bugünden sonraki 2 Ocak sayılmaz. |
| `year-writing.json` | `last-day-ends-the-year` | 31 Aralık bugündür ve yıl biter. 29 Şubat yalnız günlük yazısıdır. Eksi olay sayısı ve boş dosya yazılmış gün değildir. |
| `weekday-distribution.json` | `empty-month` | Ağustos 2026'da yazılan gün yoktur: 31 gün ölçülür (Pazartesi, Cumartesi ve Pazar 5'er). `leadingWeekday` `null` olur. |
| `weekday-distribution.json` | `running-month-ends-today` | Ekim 2026 çarşamba 7 Ekim'de sürer: her günden 1 gün ölçülür. Beş gün 1/1'dir; Cuma 3 olayla öndedir (`leadingWeekday = 4`). |
| `weekday-distribution.json` | `ended-month-higher-ratio-beats-higher-events` | Ekim 2025: Pazartesi 1/4 ve 1 olay, Çarşamba 1/5 ve 2 olay. Oran olaydan önce gelir: `leadingWeekday = 0`. |
| `weekday-distribution.json` | `running-year-ends-today` | 280 gün ölçülür (her günden 40), 7 yazılan gün. Pazartesi ve Çarşamba 2/40 ile eşittir; Pazartesi 3 olayla Çarşamba'yı (2 olay) geçer. |
| `weekday-distribution.json` | `tie-on-ratio-and-events-picks-earlier-weekday` | Şubat 2026: Çarşamba ve Cuma 1/4 ve 2 olayla eşittir; erken gün seçilir (`leadingWeekday = 2`). Eksi olay 0 sayılır. Dönem dışındaki 31 Ocak ve 1 Mart sayılmaz. |
| `weekday-distribution.json` | `period-not-begun` | Bugün dönemden öncedir: her günde `totalDays` 0 ve `leadingWeekday` `null` olur. |
| `weekly-rhythm.json` | `monday-week-running-to-wednesday` | 5–11 Ekim 2026 haftası çarşamba sürer: 4 olay, önceki haftanın pazartesi–çarşambası 3 olay. 9 Ekim'in 4 olayı sayılmaz; arkadaki çubukta 2 Ekim'in 3 olayı durur. |
| `weekly-rhythm.json` | `sunday-week-ended-on-saturday` | 4–10 Ekim pazar haftası bugün biter: 8 olay, önceki pazar haftası 6 olay. 4 Ekim yalnız günlük yazısıyla yazılmıştır. |
| `weekly-rhythm.json` | `week-not-begun`, `empty-week` | Bugün haftadan öncedir: her gün başlamamıştır. 10–16 Ağustos boştur: her gün yazılmamıştır. |
| `weekly-rhythm.json` | `rows-of-one-date-add-up-without-today` | `today` yoksa her gün ölçülür. Aynı günün satırları toplanır; eksi olay sayısı 0'dır. |
| `cadence.json` | `source: vault`, 2 gün | Erteleme günü (2026-10-11) Fela'yı gizler. Ertesi gün Fela ve süresi dolan Sera döner; eşiğe eşit Eda listeye girer. Gizem, daha uzun süredir görülmeyen Tuna'dan önce gelir. |
| `cadence.json` | `source: inline` | Test kasadan okumaz: eşik günü, hiç görüşülmemiş kişi ve eşitlikte yol sırası |
| `important-dates.json` | 10 vaka | Bugün, yarın, 7. ve 8. gün, yıl sonu, gelecek yıl, 0. yıl, henüz gelmemiş ilk yıl dönümü. 29 Şubat artık olmayan yılda 28 Şubat beklenir. |
| `on-this-day.json` | 9 vaka | En yakın yıl ve bir yıl daha; bağlantısız gün; yalnız konumlu gün; artık gün ve artık olmayan yıl; dosyası olmayan gün |

**Tablo, özet kasalarının içeriğini verir.**

| Kasa | İçerik |
|---|---|
| `vaults/rhythm/` | 3 kişi, 1 konum, 1 günlük hedef ve gün dosyaları |
| `vaults/cadence/`, kişi dosyaları | Ritim, erteleme, duraklatma ve yok sayılan yazımlar: `0`, `-4`, `7.5`, `+30`, `TRUE`, `aylık`, `yes`, `2026-13-40` |
| `vaults/cadence/`, özel dosyalar | `people/Zeki Mor.md` 3 ritim anahtarına tarih yazar. `books/Fable.md` kayıtlı kitap tipindedir; `cadence_snoozed_until` yanında `bitirme` tutar. |
| `vaults/cadence/`, gün dosyaları | Son görüşmeyi olay satırında kurar. `diary/2026-10-10.md` içindeki görev `[[Ada Kaya]]` anması son görüşmeyi değiştirmez. |
| `vaults/anniversaries/` | Geçersiz, tırnaklı ve kısa yazımlar. `books/Fable.md` pencereye girer; `places/Kıyı.md` aynı gündeki tarih alanıyla dışarıdadır. |
| `vaults/history/`, 20 Eylül | 4 yılda vardır. 2023 bağlantısızdır: not bağlantısı, çözülemeyen bağlantı ve frontmatter kişi bağlantısı. 2024 ve 2025 bağlantılıdır. 2025'te 3 kişi, 2 konum ve yinelenen kişi vardır. |
| `vaults/history/`, öteki günler | 2026 ve 2027 "bugün ve sonrası" içindir. 21 Eylül 2025 bağlantısız, 22 Eylül 2025 yalnız konumlu, 28 Şubat 2026 yalnız kişili, 29 Şubat 2024 artık gün örneğidir. |

## `vaults/` kümesi

Her kasanın amacı ve testi [Fixture ve test eşlemesi](#fixture-ve-test-eşlemesi) tablosundadır. Bu bölüm kasaların içeriğini ve beklenti dosyalarını verir. Özel tip kasaları [`entity-types/` kümesi](#entity-types-kümesi), özet kasaları [`summaries/` kümesi](#summaries-kümesi), `entity-fields` kasası [`index/` kümesi](#index-kümesi) bölümündedir.

### `sample`

`vaults/sample/` tam ve tutarlı kurgusal örnek kasadır. Kasa ayrıştırıcıyı, modelleri, indeksleyiciyi, Obsidian uyumluluğunu, arayüzü ve aramayı uçtan uca sınar. Kadro "Kurgusal adlar" tablosundadır.

| Klasör | İçerik |
|---|---|
| `diary/` | 2026-09-14 ile 2026-09-27 arası gün dosyaları |
| `people/`, `places/`, `goals/` | Kadrodaki kişiler, konumlar ve hedefler |
| `notes/` | `Proje Fikirleri.md`, `Okuma Listesi.md`, `Toplantı Notları.md` |
| `templates/` | `person.md`, `place.md` |
| `conflicts/` | 1 eşitleme çakışmasının saklanan sürümü |
| `.app/` | `vault.json`: format sürümü |

**Tablo, örnek kasaya bilerek konmuş 6 özel durumu verir.**

| No | Durum | Ayrıntı |
|---|---|---|
| 1 | Aynı adlı iki kişi | `people/Mert Aksu.md` ve ayırt edicili `people/Mert Aksu (iş).md` (`qualifier: iş`). Bağlantılar: `[[Mert Aksu]]` ve `[[Mert Aksu (iş)\|Mert]]`. |
| 2 | Var olmayan hedefe bağlantı | `diary/2026-09-18.md` içinde `[[Henüz Yazılmamış Not]]`; kasada hedef dosyası olmayan tek bağlantı |
| 3 | Frontmatter'sız not | `notes/Proje Fikirleri.md` frontmatter taşımaz. Not, blok kimliği olmayan 2 görev satırı (`- [ ]`) ve bağlantılar içerir. |
| 4 | Kod bloğu içindeki bağlantı ve başlık | `notes/Toplantı Notları.md` içinde çitli kod bloğunda `[[Deniz Arıkan]]` ve `## Events`. Ayrıştırıcı bunları bağlantı ya da bölüm başlığı saymamalıdır. |
| 5 | Saklanan sürüm | `conflicts/2026-09-20 (conflict 20260920T183000Z).md`, `diary/2026-09-20.md` dosyasının bir olay metni farklı sürümüdür. İndekse girmez. |
| 6 | Çok satırlı `aliases` | `people/Deniz Arıkan.md` dosyasında blok liste biçiminde. Diğer varlıklarda tek satırlı liste (`[Selin]`) biçiminde. |

### Sorgu ve ad kasaları

| Kasa | İçerik | Kanıtladığı |
|---|---|---|
| `backlinks` | Hedef gün `diary/2026-10-02.md` kendi içine, `diary/2026-10-01.md` hedefe bağlantı verir. `notes/Proje Fikirleri.md` 2 ayrı satırda hedefe bağlantı verir. Bir satırda 2 yinelenen bağlantı, kod içi bağlantı ve çözülmeyen hedef vardır. `people/Deniz Arıkan.md` ve `places/Liman Ofis.md` hedefe bağlantılıdır. | Günün kendisi, kod içi bağlantı ve çözülmeyen hedef dışarıda kalır. Aynı kaynaktan 2 satır 2 ayrı satır olarak listelenir. |
| `placeholder` | Gün, kişi, hedef ve kök klasördeki not için indirilmemiş yer tutucular; bildirilmeyen `.app/.types.json.icloud`. Bir gün hem yer tutucusunu hem yerel özgün dosyasını taşır. Diğer dosyalar sıradan gizli Markdown ve kişi yeniden adlandırma kaynağıdır. | Uygulama oluşturma ya da taşıma işlemini reddedince tüm kasa ve SQLite baytları aynı kalır. |
| `placeholder`, dosyalar | `expected.json` bekleyen ve indekslenen yolları tanımlar; bekleyen liste indirme isteğinin de beklentisidir. `names.json` düşman adlar, boşluk ve NFD baytlarını koruyan saf ad eşlemesidir. | Uygulama testleri kasayı iCloud kasası, yerel kasa ve seçilen klasör olarak açar. |
| `nfd-names` | `people/Baran Tunç.md` ve `places/Çınaraltı Kafe.md` adı ve takma adı NFD baytlarıyla yazar. `diary/2026-10-01.md` 3 bağlantı taşır: NFD `[[Baran Tunç]]`, NFD ve küçük harfli `[[places/çınaraltı kafe]]`, NFC `[[Baran Tunç]]`. | Ayrışmış yazım indekste birleşik (NFC) karşılaştırma anahtarına döner. |
| `nfd-names`, test | Git ayrışmış dosya adlarını birleşik biçime döndürür. Test her yol parçasını NFD biçimiyle geçici kasada oluşturur. Test baytları karşılaştırır, çünkü Swift `==` NFC ve NFD yazımını eşit sayar. | Diskteki ad NFD kalır. NFD yolla silinen ve geri eklenen kişinin gelen bağlantıları yeniden çözülür. |
| `nfd-names`, `expected.json` | NFC yollar, varlık ve takma ad anahtarları; her bağlantının satırı, `targetKey` değeri ve çözülen dosyası | — |
| `turkce-buyuk-harf` | `people/Deniz.md`, `people/Işık.md` (takma ad `Irmak`), `people/Ian.md`, `places/İstanbul.md`. `diary/2026-10-05.md` elle yazılmış bağlantılar ve düz yazımlar taşır. | [Ad karşılaştırma anahtarı](vault-format.md#adlar-ve-karşılaştırma) ve ad çakışması denetimi |
| `turkce-buyuk-harf`, bağlantılar | `[[DENİZ]]`, `[[IŞIK]]`, `[[işık]]`, `[[istanbul]]`, `[[ISTANBUL]]`, `i` + U+0307 yazımlı `[[i̇stanbul]]`, `[[IAN]]`, `[[ian]]` | — |
| `turkce-buyuk-harf`, düz yazımlar | `DENİZ`, `IŞIK`, `İSTANBUL'a`, `IRMAK`, `irmak` | — |
| `turkce-buyuk-harf`, test | Ad çakışması iki okumayı sınar: Türkçe anahtar (`DENİZ`, `ışık`, `istanbul`) ve varsayılan küçük harf eşlemesi (`ian`, `.SELIN KAYA.md.icloud`). Her oluşturma ve yeniden adlandırma kasanın ayrı kopyasında çalışır. | Reddedilen işlem kasanın baytlarını değiştirmez. Eski şema sürümlü, eski anahtarlı indeks açılışta silinir. |

**Tablo, `turkce-buyuk-harf/expected.json` dizilerini verir.**

| Dizi | İçerik |
|---|---|
| `keys` | Ad ve beklenen anahtar; NFD yazımlar dahil |
| `files`, `entities`, `aliases` | İndekslenen yollar ve NFC anahtar baytları |
| `links` | Bir tabanlı satır, hedef, `targetKey` ve çözülen dosya; çözülmeyen hedefte `null` |
| `named` | `entities(named:)` sorgusu ve dönen dosyalar |
| `mentions` | Varlık başına bağlanmamış anmalar: sıfır tabanlı satır, UTF-8 `byteRange`, yazım, harf boyu farkı |
| `creations`, `renames` | Oluşturma ya da yeniden adlandırma ve sonucu: yeni yol ya da `nameTaken` |
| `placeholders` | Testin kasaya yazdığı yer tutucu, oluşturulan ad ve `awaitingDownload` yolu |

### Kopya kasaları

**Gün kopyası**, iCloud'un `diary/` içinde bir gün dosyasının yanına ayırdığı `2026-10-02 2.md` biçimindeki dosyadır. Kural kaynağı: [Gün kopyası adları](vault-format.md#gün-kopyası-adları) ve [Çakışma kopyası](vault-format.md#çakışma-kopyası).

| Kasa | Dosya | İçerik |
|---|---|---|
| `day-copies` | `source/` | Başlangıç kasası |
| `day-copies` | `expected/` | Bildirilen bütün kopyalar sırayla birleştikten sonraki kasanın tamamı, bayt bayt |
| `day-copies` | `cases.json` | Her dosyanın değişiklik zamanı (UTC saniyesi), beklenen `dayCopies` sırası, indekslenen yollar, her kopyanın sonucu |
| `day-copies` | `cases.json`, sonuç | `renamed`, `identical` ya da `merged`; saklanan sürüm yolları ve `fellBack` değeri |
| `day-copies` | `names.json` | Saf ad kuralının tablosu: yol, gün (kopya değilse `null`) ve `mergeOrder` sırası |
| `conflict-copies` | `expected.json`, `names` | Saf ad kuralının tablosu: yol ve gün dosyası (kopya değilse `null`) |
| `conflict-copies` | `expected.json`, `conflictCopies` | Diskteki liste: gün, addaki zaman, sonra sayı sırasıyla kopyalar. Gün dosyası olmayan `2026-09-30` kopyası da listededir. |
| `conflict-copies` | `source/conflicts/` | Aynı benzer adlar, `eski/` alt klasörü ve bir `.icloud` yer tutucusu. Kökteki benzer adlı dosya sıradan nottur ve indekse girer. |

**Tablo, `day-copies` kasasındaki gün durumlarını verir.**

| Gün | Sonuç | Ayrıntı |
|---|---|---|
| `2026-10-01` | `merged` | Ana dosya ve kopya farklı olaylar ve farklı yönde değişmiş günlük yazısı taşır. Olaylar birleşir; eski sürüm olan ana dosya saklanır. `conflicts/` içinde o ad başka bir nota aittir; kopya `… 20261001T090000Z 2).md` adını alır. Var olan not değişmez. |
| `2026-10-02` | `merged`, iki kez | Kopyanın kopyası: önce `2026-10-02 2.md`, sonra `2026-10-02 3.md` birleşir. İkincisi yalnız `## Tasks` bölgesi getirir. |
| `2026-10-03 2.md` | `renamed` | Ana dosya yok; kopya onun adını ve değişiklik zamanını alır. |
| `2026-10-04` | `identical` | İki sürüm bayt bayt aynı; kopya silinir, `conflicts/` yazılmaz. |
| `2026-10-05` | Saklanır | Eski kopya UTF-8 olarak çözülemez ve salt okunurdur. Ana dosya değişmez; kopya bayt bayt saklanır. |
| `2026-10-08` | `merged` | Gün kopyadan yenidir. Kopya ayrı bir olay getirir; gün yazılır ve günün zamanı artı 1 saniyeyi alır. |
| `three-versions/` | İki sıra, aynı gün | X/Y/Z aynı olayı değiştirir. `source/` üç sürümü, `expected.md` beklenen günü taşır. `case.json` zamanları, iki sırayı ve her sıranın beklenen `conflicts/` adlarını taşır. |
| Benzer adlar | Değişmez | `2026-10-02 2 2.md`, `2026-10-02-2.md`, `2026-10-02 02.md`, `2026-13-40 2.md`, `diary/eski/…`, `notes/…` sıradan not olarak indekse girer. |

| Konu | Ayrıntı |
|---|---|
| `names.json`, kopya sayılmayan adlar | Ayrışmış (NFD) işaret, tam genişlikli ve Arap-Hint rakam, bölünmez boşluk; büyük harfli klasör, yer tutucu ve alt klasör adları |
| `conflict-copies`, kopya sayılmayan adlar | Sayısı 1 ya da başı sıfırlı; geçersiz gün, saat ya da takvim günü; eksik `Z`; büyük harfli `Conflict`; tam genişlikli rakam; alt klasör, kök dizin ve yer tutucu adları |
| NFD adlar | Git ayrışmış adları birleşik biçime döndürür; test o dosyaları geçici kasada oluşturur. |
| Harf boyu | Yalnız harf boyu farklı iki ad koyma. Harf boyuna duyarsız birim ikisini tek dosya sayar; biri ötekinin üzerine yazılır. |
| `day-copies` testleri | Testler zamanları kasanın geçici kopyasına uygular. Her adımda gün dosyasını ve `conflicts/` dosyasını `ConflictMerge` sonucuyla karşılaştırırlar. |
| `day-copies` uygulama testi | `source/` kasasını iCloud kasası olarak açar ve birleştirme bayrağını açar. Kasa sonunda `expected/` ile bayt bayt aynıdır. |
| `conflict-copies` uygulama testi | Kasayı iCloud Drive yolu altına kopyalar. Sahte sürüm kaynağıyla `IndexStore.computeConflictedFiles` sorgusunu sınar. |

### `graph`

| Dosya | İçerik |
|---|---|
| `expected.json` | Elle sayılmış `totals` ve tarih sıralı `days` (`date`, `mentions`) |
| `day-graph.json` | Tek gün sorgusunun beklentisi: `kinds` (kişi, konum, kitap) ve tarih başına elle sayılmış `mentions` |
| `relations.json` | Açık ilişki beklentileri: yönlü giden ve gelen sorgular, yönsüz tekilleştirme. `RelationsIndexTests` sınar. |

| Konu | Kasadaki durum |
|---|---|
| Gün dosyasının başlık ve frontmatter bağlantıları | O günün anmasına girer. 2026-10-02'de Selin'in başlıktaki anması 4'e, Liman Ofis'in frontmatter ve başlık anmaları 3'e katılır. |
| Gün kopyası | İndekse girmez. |
| Varlık dosyalarının frontmatter bağları | `totals` içinde anma sayılır, gün anması olmaz: `related`, `eşi`, kitabın `yazar` alanı. Selin 8 + 3 ile 11, Deniz 7 + 2 ile 9 olur. |
| Özel kitap tipi | Kendi tür sorgusunda yalnız tekil anması vardır. Ana Graph'ta tipi süzgeçte açılınca düğüm olur. |
| `diary/2026-10-04.md` | Boş satırsız tek Diary paragrafı. Madde, devam satırı, alıntı ve numaralı madde satırlarındaki her bağlantı anmaya girer. Baran, Ece, Mert ve Ev ikişer anma alır. |
| `day-graph.json` günleri | Kasada dosyası olmayan boş bir gün; kitabın tek başına anıldığı 2026-10-01; 2026-10-04. Kitap yalnız gün sorgusunda o güne girer. |

## `migration/` kümesi

**Tablo `legacy-vault` kasasındaki geçiş durumlarını verir.**

| Kaynak: `source/` | Beklenen: `expected/` | Sınanan kural |
|---|---|---|
| `journal/2026-10-01.md` | `diary/2026-10-01.md` | Başlık ve `type` değeri çevrilir; öteki baytlar aynı |
| `journal/2026-10-02.md`: BOM, CRLF, sondaki boşluklu başlık, çitli ve ikinci başlık | `diary/2026-10-02.md` | Yalnız ilk tanınan başlık çevrilir; tırnaklı `type` tek alan kuralıyla yazılır |
| `journal/2026-10-03.md`: UTF-8 değil | `diary/2026-10-03.md` | Bayt bayt taşınır |
| `journal/2026-10-04.md`: eski ad yok | `diary/2026-10-04.md` | Bayt bayt taşınır |
| `journal/2026-10-05.md` ve farklı `diary/2026-10-05.md` | `diary/2026-10-05 2.md` | Var olan dosya korunur; kaynak gün kopyası olur |
| `journal/2026-10-06.md` ve `journal/2026-10-06 2.md` | `diary/2026-10-06.md`, `diary/2026-10-06 2.md` | Önce gün dosyası, sonra gün kopyası |
| `journal/notlar.md`, `journal/eski/2026-10-07.md` | Yerinde | Gün dosyası olmayan ad kalır; klasör silinmez |

`outcome.json` geçişin raporunu taşır: `moved`, `copies`, `leftInPlace`, `removedLegacyFolder`. Test kaynağı geçici klasöre kopyalar ve her dosyaya sabit zaman verir. Yarım kalan geçiş, yer tutucu ve `Diary/` durumlarını test kodda kurar.

Kural kaynağı: [Eski adlar ve geçiş](vault-format.md#eski-adlar-ve-geçiş). Eski başlık örnekleri `parse/section-legacy-heading/` ve `write/*-legacy-heading/` klasörleridir.

## İlgili belgeler

- [Kasa biçimi](vault-format.md): ayrıştırıcı ve yazıcı kuralları.
- [Mimari](architecture.md): Core modülleri.
- [Geliştirme](development.md): test katmanları ve CI.
- [Ekranlar](screens.md): özet sayılarının tanımı.
