# Player düzeltmeleri — ikinci paket

Tarih: 23 Eylül 2026

Bu paket VOD adresleri, sarma işlemleri ve M3U izleme ilerlemesini düzeltir. Önceki raporun B07, B09 ve B15 bulgularını; B10'un URL içindeki kimlik bilgilerinin kodlanması bölümünü kapsar. Hesap URL normalizasyonu ve diğer senkronizasyon sorunları bu paketin dışında kalmıştır.

## Uygulanan değişiklikler

- VOD senkronizasyonunun her iki tam senkronizasyon yolu artık `container_extension` ve `direct_source` bilgisini koruyor. Uzantı ayrı bir nullable katalog alanında tutuluyor; adres güncel hesap bilgileriyle oluşturuluyor. Böylece şifre değişikliğinde daha önce üretilmiş bir URL'ye bağlı kalınmıyor.
- Film, ana sayfa ve yapay zekâ üzerinden oynatma ortak adres çözücüsünü kullanıyor. Film detayındaki `movie_data` bilgisi, katalogdaki doğrudan adres ve uzantı değerlendiriliyor. Eski katalog kaydında bu bilgiler yoksa detay API'sine başvuruluyor. Detay beklemesi 10 saniyeyle sınırlı; bu süre alttaki HTTP isteğinin iptal edildiği anlamına gelmez.
- Sağlayıcı uzantı veya doğrudan adres bildirdiğinde sabit `.mkv` varsayımı kullanılmıyor. Bilgi alınamazsa önceki `.mkv` davranışı son çare olarak korunuyor; sağlayıcının eksik bilgisinden doğru dosya biçimi kesin olarak çıkarılamaz.
- Dizi bölümleri ortak URL kurucusundan açılıyor; bölüm uzantısı ve varsa `direct_source` kullanılıyor.
- Canlı, film, bölüm ve timeshift adreslerinde kullanıcı adı/şifre URI path segmenti olarak kodlanıyor. `#`, `?`, `/`, boşluk ve yüzde işaretleri adres yapısını bozmuyor. Verilen taban URL'nin yolu ve portu korunuyor; doğrudan medya URL'lerinin imzalı sorguları değiştirilmeden kullanılıyor.
- Tüm mevcut player route girişleri açık `streamId` taşıyor. Standart player ve Android TV, izleme kaydını ve devam et sorgusunu URL'den sayı çıkartarak değil bu katalog/bölüm kimliğiyle yapıyor. Kanal listesi olmadan açılan M3U canlı yayınların geçmiş kaydı da katalog kimliğini kullanıyor.
- Android TV, açık bir başlangıç konumu verilmemişse bitmemiş içeriğin kayıtlı konumunu okuyup devam ediyor. Açıkça verilen sıfır konumu baştan oynatma anlamını koruyor. Süre sınırı aşılmıyor; bekleyen eski açılışın yeni controller'a müdahalesi engelleniyor.
- Zaman çubuğunda sürükleme yalnızca önizlemeyi güncelliyor; bırakma tek seek gönderiyor. D-pad, ileri/geri düğmeleri ve mobil çift dokunmalar 400 ms içinde birleştiriliyor. Native seek çağrıları sıralanıyor, bekleyen eski hedefler atlanıyor. Bilinmeyen sürede seek gönderilmiyor; hedef sıfır ile medya süresi arasında tutuluyor.
- Medya değişikliği veya player kapanışı bekleyen sarma işlemlerini iptal ediyor. İzleme kaydı önizleme konumundan değil gerçek oynatma konumundan alınıyor. Geçersiz süre/negatif konum mevcut ilerlemeyi ezmiyor; süreyi aşan konum sınırlandırılıyor.

## Veritabanı güncellemesi

Şema v23 → v24: `channels.container_extension` nullable alanı eklendi. Birincil anahtarlar, katalog kimlikleri ve kullanıcı kayıtları değiştirilmedi. Sütunun daha önce eklenmiş olabileceği kurulumlar için eklemeden önce varlığı kontrol ediliyor. Projenin `ONEMLI.md` dosyasındaki composite-PK uyarısı dikkate alındı; bu değişiklik bir PK değişikliği değildir.

Geçiş testleri v23 şemasını temsil eden geçici SQLite dosyalarında çalışır. Normal v23 ve sütunun zaten var olduğu v23 durumları denenir; M3U adresi, katalog kimliği ve izleme konumu korunur. Gerçek kullanıcı veritabanı açılmamıştır.

## Doğrulama

- `flutter test --no-pub`: **269 test geçti**; bu paketle **30 test** eklendi.
- Yeni adres çözücüsü, URL kurucusu, sarma denetleyicisi, player dosyaları ve yeni testlerin hedefli analizi: **sorun yok**.
- `dart analyze lib test`: **0 hata, 6 önceden mevcut uyarı, 21 bilgi bildirimi**. Proje çapındaki analiz bu mevcut bildirimler nedeniyle temiz çıkış kodu üretmez.
- Linux release derleme sonucu: `player-fixes-2-2026-09-23/linux-build.log`.
- URL/senkronizasyon testleri sahte sağlayıcı cevapları; ilerleme testleri gerçek bellek SQLite veritabanı; geçiş testleri geçici SQLite dosyaları kullanır. Sarma testleri çağrı sayısını, birikimi, sıralamayı, hata sonrası toparlanmayı ve kapanışta iptali kontrol eder.
- Drift kodu yenilendi. Üreticinin bildirdiği SDK/analyzer sürüm farkı bir uyarıdır; üretim tamamlandı. Mevcut bağımlılık çözümü kullanıldı ve kullanıcıdaki `pubspec.lock` byte düzeyinde korundu. Çalıştırma sırasında çözülen kilit dosyası doğrulama klasörüne kaydedildi.

## Gerçek cihazda kabul kontrolü

1. Xtream hesabında MP4, MKV ve doğrudan URL bildiren farklı filmleri; ayrıca farklı uzantılı dizi bölümlerini aç.
2. Özel karakterli kullanıcı adı/şifre ile canlı yayın, VOD ve bölüm adreslerini doğrula.
3. M3U'da sayısal olmayan veya katalog kimliğinden farklı sayısal dosya adlı filmi izle, player'ı kapat ve yeniden aç; doğru içerikten devam etmeli. Android TV'de aynı kontrolü yap.
4. Zaman çubuğunu hızlıca sürükle; bırakmadan gerçek oynatma konumu değişmemeli. Art arda ileri/geri bas; önizleme birikmeli ve tek hedefe sarılmalı.
5. İlk/son saniyede ±10 tuşlarını kullan; aralık dışı seek oluşmamalı. Bekleyen sarma varken player'ı kapat veya kanal değiştir; yeni içeriğe eski hedef uygulanmamalı.

## Kalan sınırlar

M3U'nun mevcut 31-bit kimlik üretimi ve çakışma riski değiştirilmedi; bu paket mevcut katalog kimliğini doğru kullanır. Önceden yanlış URL kimliği altında kaydedilmiş ilerlemeler, hangi içeriğe ait oldukları kesin belirlenemediğinden otomatik taşınmaz. Dizi üst kaydı/bölüm kimliği çakışması ve M3U dizi gruplaması ayrı iş olarak kalır.

Gerçek IPTV hesabı, Android TV/iPhone/Windows/macOS cihazı ve H.265/HDR/4K decoder performansı bu çalışmada test edilmedi. Sonraki paket Android TV/MediaCodec, donanım hızlandırma ve tamponlama incelemesidir.
