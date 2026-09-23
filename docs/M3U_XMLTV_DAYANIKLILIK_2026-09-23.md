# M3U / XMLTV dayanıklılığı — 23 Eylül 2026

Bu paket B06, B24 ve B25’i, B21’in M3U kısmını ve B23/B26’nın bir bölümünü uygular. İlk rapordaki bulgular tarihsel kayıt olarak korunur. M3U dizi/sezon/bölüm akışı henüz tamamlanmadı.

## Değişiklikler

- Şema **27**: hesap kapsamında `m3u_identities` tablosu. Kimlik yalnız hash’e güvenmez; tam kaynak anahtarı karşılaştırılır, çakışan aday için boş ID seçilir ve eşleme kalıcı saklanır. 52 bit adaylar JSON’da kesin temsil edilir. Kaynaktan geçici olarak kaldırılan yayınların eşlemeleri silinmez.
- Kaynak kimliği, tür içinde tek URL’ye ait `tvg-id`; yoksa tam URL’dir. Birden fazla URL’nin paylaştığı `tvg-id` URL bazında ayrılır. URL sorgu parametreleri gelişigüzel kaldırılmaz. Aynı tür/kaynak anahtarının tekrarları tek kayda iner.
- Mevcut katalogdaki URL eşleşmesinde eski stream ID korunur; ad değişimi yeni içerik sayılmaz. Tekil `tvg-id` varsa imzalı URL değişimi de kimliği korur. Daha önce çakışma yüzünden üzerine yazılan kaydın geçmişi kendiliğinden kurtarılamaz.
- Yedek **v4**, kalıcı eşlemeleri içerir. v1–v3 okunmaya devam eder. Katalog içermeyen eski yedeklerde favori/geçmiş/watchlist ID’si, yeni listedeki eski URL+ad hash’i tekil eşleşiyorsa yeniden kullanılır. Belirsiz çakışmalar yanlış içeriğe bağlanmaz.
- LAN içerik kayıtları M3U kaynak anahtarından yerel ID’ye çevrilir. Sadece gönderilen kayıtlara ait eşlemeler taşınır. Otomatik aktarımda bilinmeyen kimlik atlanır; manuel aktarım eşleşmeyen kimlikte açıklamalı hata verir. İki cihazın da güncel uygulama ve senkronlanmış katalog kullanması gerekir; eski karşı uçların yeni eşlemeyi uygulaması garanti edilmez.
- M3U indirme sonrası decode/parse ve sınıflandırma/kimlik hazırlığı ayrı isolate’ta; XMLTV decode/parse da ayrı isolate’ta çalışır.
- M3U/XMLTV indirmelerine **64 MiB** yanıt sınırı; sırasıyla **90/120 saniye** toplam HTTP süresi ve en çok iki deneme. Sınır aşımı yeniden denenmez; Dio bağlantısı işlem sonunda kapatılır.
- Parser: tırnak içi virgül/apostrof, büyük harfli ve tırnaksız alanlar, BOM/CRLF, URL’siz EXTINF sonrası toparlanma, yönlendirme sonrası gerçek URL’ye göre bağıl yayın/EPG adresleri ve query içeren VOD uzantıları düzeltildi. HTTP 200 ile gelen HTML/JSON hata gövdesi katalog sayılmaz.
- M3U yenilemesi upsert kullanır; detay metadata’sı ve kategori gizliliği korunur. Kimlik, kategori, kanal ve temizleme tek transaction içindedir.
- Temizleme, tüm kataloğu tek `NOT IN` sorgusuna bağlamak yerine eski ID’leri okuyup **500 ID’lik** silme grupları kullanır. Geçerli ve boş olmayan M3U listesinden tamamen kaldırılan tür de temizlenir. Xtream’de önceki boş yanıt koruması devam eder.
- Xtream ve XMLTV EPG değiştirmesi kanal başına atomiktir. Boş/geçersiz program listesi önceki rehberi silmez; insert hatası delete’i de geri alır. XMLTV’de geçersiz takvim tarihi ve ters aralık atlanır; ağdan alınan programlar geçmiş 6 saat / gelecek 7 gün penceresinde tutulur.
- XMLTV RAM önbelleğinde **6 saat TTL** ve tam URL anahtarı, aynı URL için ortak bekleyen istek, clear/force sonrasında eski yanıtın cache’i tekrar doldurmamasını sağlayan nesil kontrolü vardır. Tek bitmiş sonuç saklanır. Büyük ham XML artık SharedPreferences’e yazılmaz; uygulama yeniden açıldığında ağdan yüklenir. `clearCache` eski disk anahtarlarını da temizler.

## Doğrulama

- **373 Flutter testi geçti.** Bilinen `799436981` çakışması; zorlanmış yeni hash çakışması; 100 bin kayıtta sıralama/ad değişimi; eski ID ve imzalı URL korunması; yedek round-trip; farklı cihaz ID eşlemesi; hesap izolasyonu; v26 → v27 ve önceden oluşmuş tablo ile açılış kapsandı.
- Gerçek bellek SQLite’ında 100 bin M3U satırı senkronlandı, sonraki listede 3 kayıt bırakılarak 99.997 eski satır temizlendi. Kalıcı eşlemeler korundu.
- SQL hata enjeksiyonunda katalog/eşleme işlemi geri alındı; EPG insert hatasında önceki rehber kaldı. Boyut sınırı, XMLTV TTL/clear/force ve parser varyasyon testleri geçti.
- `dart analyze lib test tool`: **0 hata**, önceki **6 uyarı / 17 bilgi** devam ediyor.
- **Linux release derlemesi ve 12 saniyelik yalıtılmış açılış kontrolü geçti**: şema 27, varsayılan profil ve 19 hesap kapsamlı tablo doğrulandı. Sonuç `playlist-fixes-2026-09-23/linux-startup.json` dosyasında. Bu kontrol gerçek VOD/codec veya diğer platformların cihaz kabul testi değildir.

## Ayrıştırma ölçümü

Aynı güncel parser, aynı sentetik veri ve bu Linux test makinesinde ana isolate ile işçi isolate karşılaştırıldı. Her hücre üç tekrarın medyanıdır. Ağ, DB yazımı ve M3U kimlik hazırlığı bu ölçüme dahil değildir. Zamanlayıcı aralığı **Flutter frame süresi değildir**; ana isolate’ın yanıt verebilirliği için göstergedir.

| Veri | Kayıt | Ana: işlem ms | Ana: en uzun timer aralığı ms | İşçi: işlem ms | İşçi: en uzun timer aralığı ms |
|---|---:|---:|---:|---:|---:|
| M3U | 10,000 | 49.1 | 59.2 | 69.9 | 13.2 |
| M3U | 50,000 | 244.8 | 254.7 | 246.9 | 13.7 |
| M3U | 100,000 | 439.0 | 449.0 | 475.6 | 14.3 |
| XMLTV | 10,000 | 154.4 | 164.4 | 164.1 | 11.8 |
| XMLTV | 50,000 | 704.8 | 714.8 | 712.5 | 16.8 |

İşçiye taşıma toplam işlem süresini her veri boyutunda düşürmez; esas kazanım uzun CPU işinin arayüzü bloke etmemesidir. Ham ölçümlerde RSS de vardır; test çalıştırıcısı, GC geçmişi ve XML DOM’u bu değere dahildir. Belleğin düştüğü iddia edilmez.

Tekrar: `flutter test tool/playlist_benchmark_test.dart`.
Ham sonuç: [parser-benchmark.json](playlist-fixes-2026-09-23/parser-benchmark.json).

## Açık sınırlar ve sonraki işler

1. M3U dizi → sezon → bölüm modeli ve dizi/bölüm geçmişi (B07–08).
2. EXTVLCOPT/KODIPROP gibi sağlayıcı başlıklarını player’a aktarma (B26’nın kalanı).
3. XMLTV streaming parser ve düşük RAM’li cihaz ölçümü. 64 MiB ağ sınırı, DOM’un/RSS’in 64 MiB ile sınırlanması anlamına gelmez.
4. CPU işçisini kullanıcı iptalinde gerçekten sonlandırma. Mevcut iptal eski sonucun DB’ye yazılmasını engeller, başlamış parse tamamlanana kadar CPU çalışabilir.
5. EPG işlemlerinin ortak toplam süre/iptal ve görünür hata politikası; `force` API’sini manuel EPG yenileme UI akışına bağlama. XMLTV kanal eşlemesindeki büyük katalog maliyeti.
6. Kalıcı kimlik tablosunun uzun dönem büyümesi ve sağlayıcının `tvg-id` vermediği sürekli değişen URL’ler. Kaynak kimliği belirsizken kullanıcı verisini yanlış yayına taşıyan tahmin yapılmaz.
7. Android/TV, Windows, macOS ve iPhone gerçek cihaz testleri; Linux uzun VOD/codec oynatma testi bu pakette tekrarlanmadı.
