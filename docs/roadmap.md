# Yol haritası

**Aktif aşama:** 0

Kural: Bir aşamanın çıkış ölçütü sağlanmadan sonrakine geçilmez. Her modül gerçek kullanımda sınanır.

## Aşama 0: Temel

Kullanıcıya görünen bir şey yok; her şey bunun üstüne kurulur.

- [ ] Xcode projesi: iOS ve macOS hedefleri, `Core` Swift paketi
- [x] CI (GitHub Actions): her PR'da derleme, `Core` testleri, biçim ve lint denetimi
- [ ] Sürüm otomasyonu: `main`'e birleşince etiket ve GitHub Release
- [x] Dal koruması: `main` ve `dev` için PR ve geçen test zorunluluğu
- [ ] Ayrıştırıcı ve yazıcı: frontmatter, bölümler, olay satırı, görev satırı (durum, metin, kimlik), wikilink, blok kimliği
- [ ] Gidiş dönüş testi ve `Fixtures/` örnek kasası
- [ ] SQLite indeksi (GRDB, FTS5) ve dosyalardan yeniden üretme
- [ ] Kasa konumu: iCloud kapsayıcısı, yerel yedek seçenek
- [ ] Dosya değişikliklerini izleme ve artımlı yeniden indeksleme
- [ ] Senkronizasyon çakışmalarını birleştirme

**Çıkış ölçütü:** Örnek kasa okunuyor, indeksleniyor, değişiklikler yansıyor, tüm testler geçiyor.

## Aşama 1: Günlük

- [ ] Bugün sayfası ve hızlı giriş kutusu
- [ ] Olay ekleme (saat damgalı satır) ve serbest günlük yazısı
- [ ] `@` ile kişi, konum için öneri listesi; yeni varlık oluşturma
- [ ] Bilinen adların ve takma adların otomatik tanınması
- [ ] Belirsiz eşleşmede bağlama göre sıralama; emin değilse kullanıcıya sorma
- [ ] Aynı adlı varlık oluştururken ayırt edici sorma, dosya adını otomatik üretme
- [ ] Varlık adını değiştirme ve tüm bağlantıları güncelleme
- [ ] Geçmiş güne olay ekleme, saatsiz olay
- [ ] Kişi ve konum sayfaları: şablon alanları, serbest ek alanlar, zaman akışı
- [ ] Günler arasında gezinme
- [ ] Tam metin arama ve hızlı geçiş
- [ ] Mac'te kenar çubuklu, telefonda sekmeli düzen
- [ ] Mac'te sistem genelinde kısayolla açılan hızlı giriş penceresi

**Çıkış ölçütü:** İki hafta boyunca her gün bununla günlük tutuluyor.

## Aşama 2: Görevler

- [ ] Görev ekleme, tarih verme, tamamlama; hızlı girişte olay / görev geçişi
- [ ] Görevler sekmesi: yaklaşan, tarihsiz, tamamlanan
- [ ] Doğal dille tarih ("yarın", "cuma", "5 ekim")
- [ ] Bugün ekranında günün ve geciken görevler
- [ ] Görevlerin kişi ve konumlara bağlanması; varlık sayfasında açık işler
- [ ] Cihaz takvimindeki etkinliklerin bugün ekranında görünmesi (EventKit, salt okunur)
- [ ] İleri tarihli ajanda listesi

**Çıkış ölçütü:** Günlük işler yalnızca buradan takip ediliyor.

## Aşama 3: Hedefler ve widget'lar

- [ ] Hedef tanımlama: dönem (gün, hafta, yıl), tür (evet/hayır, sayı), miktar
- [ ] Zincir, en uzun seri, ısı haritası; yıllık hedefte ilerleme çubuğu
- [ ] Geçmiş günlerin hedef kaydını düzeltme
- [ ] Ana ekran widget'ı: zincir ve tek dokunuşla işaretleme; yapılmamışlar vurgulu
- [ ] Widget yenilenmesinin güvenilirlik testi
- [ ] Kilit ekranı widget'ı: takvim etkinlikleri ve günün görevleri
- [ ] Hızlı giriş widget'ı
- [ ] Mac widget'ları

**Çıkış ölçütü:** Alışkanlık uygulaması ve Lockday telefondan silindi.

## Aşama 4: Otomasyon

- [ ] Görev ve hedef bildirimleri, akşam günlük hatırlatması; bildirimlerin güvenilirlik testi
- [ ] Olay yazarken GPS ile konum önerisi
- [ ] Konuma girince hedefi otomatik işaretleme ya da tek dokunuşluk bildirim
- [ ] Kısayollar ve Siri ile giriş (App Intents)

**Çıkış ölçütü:** İki hafta boyunca hatırlatmalar kaçmadan geliyor; konuma bağlı hedefler elle işaretlemeden kaydediliyor.

## Aşama 5: Proje görünümleri

- [ ] Kanban: duruma, projeye ya da kişiye göre
- [ ] Zaman çizelgesi: başlangıç ve bitiş tarihli görevler (ağırlıklı Mac)
- [ ] Proje etiketi ve proje sayfaları; sayılamayan yıllık hedefler
- [ ] Tekrarlayan görevler, öncelikler

**Çıkış ölçütü:** Notion kanban ve zaman çizelgesi için açılmıyor.

## Aşama 6: Geri bildirim

- [ ] Haftalık ve aylık özetler (sayılara dayalı, yapay zekasız): kimlerle, nerelerde, hedef ve görev durumu
- [ ] Kişi sayfasında son görüşme özeti; uzun süredir görüşülmeyenler
- [ ] Graph ve harita görünümleri
- [ ] İsteğe bağlı yapay zeka (karar açık):
  - Haftalık ve aylık değerlendirme: dönemin günlüklerini, görevlerini ve hedeflerini inceleyip yazılı geri bildirim verme (örüntüler, iyi gidenler, aksayanlar, öneriler)
  - Yeni varlık önerisi ve olgu çıkarımı
  - Notlara soru sorma

**Çıkış ölçütü:** Haftalık özet dört hafta üst üste okunuyor.

## Aşama 7: Genişleme

- [ ] App Store hazırlığı: ilk kullanım akışı, Obsidian kasasından içe aktarma, uygulama kilidi
- [ ] CD: TestFlight'a otomatik gönderim (Xcode Cloud ya da fastlane, o aşamada seçilecek)
- [ ] Özel varlık tipleri (kitap, proje, vb.)
- [ ] Şirket şema paketi
- [ ] Talep olursa Android ve Windows
