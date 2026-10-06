# Ajan kuralları

Bu dosya Claude Code ve diğer CLI ajanları için tek talimat kaynağıdır. `CLAUDE.md` yalnızca bu dosyayı içe aktarır.

## Proje özeti

iPhone ve Mac için SwiftUI ile yazılan kişisel günlük uygulaması. Kullanıcı gün içinde kısa olaylar yazar; uygulama metindeki kişi ve konumları tanıyıp otomatik bağlar. Üstüne görevler, hedefler (zincir), widget'lar, kanban ve zaman çizelgesi eklenir. Gerçek veri kaynağı Obsidian uyumlu Markdown dosyalarıdır.

## İşe başlamadan önce

1. `docs/roadmap.md` içinden **aktif aşamayı** oku ve o aşamanın maddeleri üzerinde çalış.
2. Dosya okuyan ya da yazan her iş için `docs/vault-format.md` belgesine uy.
3. Arayüz işi için `docs/screens.md` başlangıç noktasıdır: neyin nerede olacağını tarif eder, nasıl görüneceğini değil.
4. Mimari sorular için `docs/architecture.md`, gerekçeler için `docs/decisions.md`.

## Serbest olduğun alanlar

Aşağıdaki "değişmez kurallar" dışındaki her şey senin kararındır. Belgeler neyin yapılacağını ve hangi sınırların aşılmayacağını söyler; nasıl yapılacağını sen belirlersin.

- **Kodun iç yapısı:** modül ve tip tasarımı, adlandırma, algoritmalar, veri yapıları, indeks şemasının ayrıntıları, performans iyileştirmeleri.
- **Arayüz ayrıntıları:** görsel tasarım, yerleşim, animasyon, etkileşim, erişilebilirlik. `screens.md` bir taslaktır; daha iyi bir çözüm görürsen uygula ve PR açıklamasında nedenini yaz.
- **Araç ve kütüphane seçimi:** işi belirgin biçimde iyileştiren bir bağımlılık ekleyebilirsin; gerekçesini PR açıklamasına yaz.
- **Test yaklaşımı:** zorunlu olanların ötesinde neyi nasıl test edeceğin.

Belgelerde hata, çelişki ya da daha iyi bir yol görürsen körü körüne uygulama: söyle ve öner. Belgeler de değişebilir. Bir kuralın gerekçesi o durumda geçerli değilse bunu belirt.

## Değişmez kurallar

Bunlar zevk değil, ürünün temel vaatleridir (veri kullanıcınındır, hiçbir şey kaybolmaz, başka platforma taşınabilir).

- **Markdown gerçek kaynaktır.** SQLite yalnızca indekstir; silinince dosyalardan eksiksiz yeniden üretilebilmelidir. Dosyada olmayan bilgi indekste tutulmaz.
- **Önce dosyaya yaz, sonra indeksi güncelle.** Tersi yapılmaz.
- **Tanımadığına dokunma.** Uygulama bir dosyada yalnızca kullanıcının işleminin hedeflediği satırı ya da alanı değiştirir; geri kalan içerik bayt düzeyinde korunur.
- **Core paketi Apple'a bağımsızdır.** `Core` içinde SwiftUI, UIKit, AppKit, EventKit, CoreLocation, WidgetKit ya da iCloud API'si kullanılmaz. Yalnızca Foundation ve SQLite katmanı.
- **Format değişikliği önce belgede yapılır.** `docs/vault-format.md` güncellenmeden ayrıştırıcı ya da yazıcı davranışı değiştirilmez.
- **Sonraki aşamaların özelliklerini erken yazma.** Aktif aşamayı bitirmeden ileriki özellikler eklenmez. Onları kolaylaştıracak tasarım tercihleri ise serbesttir ve teşvik edilir.
- **Arayüz metinleri koda gömülmez.** String Catalog kullanılır (Türkçe ve İngilizce).

## Belge kuralları

- Önce mevcut belgelere bak: bilgi oradakilerden birine aitse oraya ekle, aynı konuyu iki yerde anlatma.
- Mevcut belgelere sığmayan ayrı bir konu varsa (örneğin bir aşamanın ayrıntılı spec'i) `docs/` altında yeni belge aç ve `README.md` içindeki belge tablosuna ekle.
- Yeni belge yalnızca `docs/` altında açılır; kök dizine ya da kod klasörlerine `.md` dağıtılmaz.
- Rapor, denetim çıktısı, geçici plan ya da not dosyalarını repoya koyma.
- Bir karar verildiğinde `docs/decisions.md` karar tablosuna tek satır ekle; açık soru kapandıysa oradan sil.
- Bir aşama maddesi bittiğinde `docs/roadmap.md` içindeki kutuyu işaretle.

## Kod kuralları

- Dil: Swift (güncel kararlı sürüm), SwiftUI. Kod, tip ve dosya adları İngilizce; kullanıcıya görünen metinler yerelleştirilmiş.
- Ayrıştırıcı ve yazıcı için her davranış `Fixtures/` altında bir örnek Markdown dosyası ve beklenen çıktı ile test edilir. Bu dosyalar dilden bağımsızdır ve ileride başka platformlarda yeniden kullanılır.
- Gidiş dönüş testi zorunludur: bir dosya okunup hiçbir değişiklik yapılmadan yazıldığında birebir aynı kalmalıdır.
- İndeks şeması değiştiğinde şema sürümü artırılır; eski indeks silinip dosyalardan yeniden kurulur, göç yazılmaz.
- Belge biçim denetimleri (karar tablosu, README belge tablosu, String Catalog) CI'da koşar.

## Git kuralları

### Dallar

- `main`: Yalnızca yayınlanmış sürümler. Her birleştirme bir sürümdür.
- `dev`: Geliştirme dalı ve reponun varsayılan dalı. Her zaman derlenir ve testleri geçer.
- İş dalları `dev` üzerinden açılır: `feat/...`, `fix/...`, `docs/...`, `test/...`, `chore/...`
- Acil düzeltme: `hotfix/...` dalı `main` üzerinden açılır, `main`'e PR ile girer, ardından `main` `dev`'e geri birleştirilir. Bu geri birleştirme squash ile değil merge commit ile yapılır; squash iki dalın ortak geçmişini koparır.

### Akış

1. `dev`'den iş dalı aç.
2. Değişikliği yap; bir PR tek bir yol haritası maddesini kapsar.
3. `dev`'e PR aç. Birleştirme squash ile yapılır.
4. Karar ya da format değiştiren PR, ilgili belgeyi aynı PR içinde günceller.

### Sürüm

- Sürüm numarası kök dizindeki `VERSION` dosyasında durur (tek satır, `X.Y.Z`); Xcode projesi ve iş akışları numarayı oradan okur.
- Sürüm, `dev`'den `main`'e açılan PR ile kesilir. Bu PR `VERSION` dosyasını yükseltir ve merge commit ile birleştirilir (squash değil).
- `main`'e birleşince `.github/workflows/release.yml` `VERSION` içindeki numarayla `vX.Y.Z` etiketini ve GitHub Release'i oluşturur; etiket zaten varsa atlar.
- Numaralandırma (SemVer): 1.0 öncesinde `0.<aşama>.<yama>`. Aşama 1 tamamlanınca `v0.1.0`, o aşamadaki düzeltmeler `v0.1.1`. İlk mağaza yayını `v1.0.0`.
- Sürüm kesme kararı kullanıcınındır. Ajan `main`'e PR açmaz ve birleştirmez; yalnızca istendiğinde sürüm PR'ını hazırlar.

### Commit

- Conventional Commits: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`
- Önek İngilizce, açıklama Türkçe: `feat: olay satırı ayrıştırıcısı`
- Küçük ve tek amaçlı commit'ler.
- Commit mesajına ve PR açıklamasına yapay zeka imzası eklenmez: `Co-Authored-By`, "Generated with" ve benzeri satırlar yazılmaz. Hangi ajan çalışırsa çalışsın geçerlidir.

### Yasaklar

- `main` ve `dev` dallarına doğrudan push yok; her şey PR ile.
- Force push yok.
- Testler geçmeden birleştirme yok.

## Gizlilik

Repo herkese açıktır. Gerçek kişilere, konumlara ya da kişisel günlüğe ait hiçbir veri repoya girmez. `Fixtures/` altındaki örnek kasa tamamen kurgusal adlarla yazılır.

## Onay gerektiren işler

Aşağıdakileri yapmadan önce dur ve kullanıcıya sor:

- Kendi oluşturmadığın dosya ya da klasörleri silme, toplu yeniden adlandırma
- Sekme yapısı gibi uygulamanın ana gezinme düzenini değiştirme
- Kasa formatını geriye uyumsuz değiştirme
- Bundle kimliği, iCloud kapsayıcı kimliği, App Group kimliği gibi sonradan değiştirmesi zor değerleri belirleme

## Planlanan dizin yapısı

```
App/                 iOS ve macOS SwiftUI uygulaması (App/Support: entitlements, plist ekleri)
Widgets/             WidgetKit hedefi (henüz yok)
Packages/Core/       Ayrıştırıcı, modeller, indeksleyici (Apple'a bağımsız)
Fixtures/            Örnek kasa ve test dosyaları
Tests/JournalTests/  Uygulama katmanı birim testleri (macOS ve iOS simülatörü)
Tests/JournalUITests/ XCUITest duman testi ve erişilebilirlik denetimi (iOS)
docs/                Belgeler
.github/             CI iş akışları ve denetim betikleri (.github/scripts)
project.yml, VERSION  XcodeGen tanımı ve sürüm numarası; Journal.xcodeproj üretilir, repoya girmez
```
