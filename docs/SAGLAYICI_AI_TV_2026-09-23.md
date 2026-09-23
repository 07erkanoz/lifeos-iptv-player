# Sağlayıcı, AI iş yükü ve TV kontrolleri — 23 Eylül 2026

Bu paket önceki veri bütünlüğü ve odak paketlerinin devamıdır. Bütün özelliklerin veya bütün cihazların kabul testinin tamamlandığı anlamına gelmez.

## Uygulanan düzeltmeler

- **Sağlayıcı uyumluluğu:** M3U EXTVLCOPT/KODIPROP HTTP başlıkları kanal ve bölümle saklanır; doğrudan URL sonundaki VLC başlıkları oynatma öncesi ayrılır. User-Agent, Referer ve Cookie masaüstü/TV player’a, kanal değişimine ve bölüm geçişine ulaşır. Katalog kimliği için özgün URL korunur. Başlıklar görsel/EPG/AI isteklerine eklenmez. Şema 28 nullable `playback_headers` alanını veri kaybetmeden ekler.
- **Xtream adresleri:** alt dizin ve IPv6 korunur; get.php bağlantısı ancak başarılı Xtream doğrulamasıyla dönüştürülür. API başarısızsa özgün M3U kaynağı kullanılır. Rastgele username/password parametreleri artık hesap türünü değiştirmez.
- **Ortak oynatma girişi:** arama ve program rehberi ortak URL çözümleyicisini kullanır; dashboard diziyi bölüm seçimine açar.
- **TV kumandası:** film ve dizide aşağı/yukarı ile oynat düğmesine, ardından ses parçası seçimine erişilir. Menü/bilgi tuşu canlı yayındaki kontrolleri açar. Ses menüsü zaman aşımı ve oturum kontrolü içerir; kapanınca oynatma odağı geri gelir. Gizlenen kontroller ana oynatıcı odağına döner. Üst geri simgesi tıklanabilir düğmedir.
- **Arka plan yükü:** AI zenginleştirme ve embedding işleri başlangıçta, HTTP sonrasında ve yazımdan önce oynatma/iptal kontrolü yapar. Hesap sağlayıcısı kapandığında eski iş iptal edilir. Arama indeksi parçalar arasında durur. Başlamış HTTP isteği anında kesilmez; sonuç yazılmaz ve yeni parti başlamaz.
- **AI doğruluğu:** model yanıtları `(tür, ID)` ile doğrulanır. Uydurma tür/ID, tekrar, sonlu olmayan veya 0,65 altı güven değerleri metadata olamaz. Düşük güvenli kayıtlar yeniden sürekli sorgulanmaması için boş işaretleyici olur. Bu eşik ürün politikasıdır; ölçülmüş model doğruluğu oranı değildir.
- **Embedding:** Float32 alt dizi kodlaması, boyut eşleşmesi, NaN/sıfır vektör kontrolü düzeltildi. Tüm vektörleri bir anda yüklemek yerine anahtar sıralı sınırlı sayfalar işçide sıralanır. Sorgu/belge görevleri ayrılır; sürüm hesabın kendi anahtarında tutulur. Metadata değişikliği ilgili embedding ve arama indeksini geçersiz kılar. Dönen vektör sayısı/sırası doğrulanır. Görev türleri kullanılan `gemini-embedding-001` için [Google API belgesine](https://ai.google.dev/api/embeddings) dayanır.
- **Cast ve altyazı:** Chromecast LOAD mevcut VOD konumunu taşır; kontrol komutları receiver mediaSessionId’sini kullanır. Dönüş/kopmada son bildirilen remote konumundan yerel oynatma sürer. Altyazı dosyası 2 MiB ve toplam 20 saniye indirme sınırıyla, API anahtarını taşımayan ayrı istemciden alınır.
- **LAN:** yeni eşleme/cihaz anahtarları kriptografik rastgele üretilir. PIN beş dakika ve on hatalı denemeyle sınırlıdır. Eşleme ekranı kapanırken Riverpod dispose hatası ve geç açılan sunucu sızıntısı giderildi. **Aktarım hâlâ HTTP; bu değişiklik TLS veya PAKE sağlamaz.**
- **Arayüz/platform:** film/dizi detayı dar masaüstü penceresinde de kompakt düzene geçer. Bildirim izni reddedilirse başarı dönmez; Android planlı bildirim/boot receiver’ları eklendi. iOS mikrofon/konuşma ve LAN Bonjour tanımları eklendi. CI macOS/iOS imzasız derlemelerini kapsar; Android signing dosya yolları düzeltilir ve release etiketi eksik sırlarla debug imzaya düşemez.

## Doğrulama

Son sayısal sonuçlar [validation.json](provider-ai-tv-2026-09-23/validation.json) dosyasındadır. Otomatik testler gerçek sağlayıcı/TV/iPhone denemesi değildir.

10.000 × 768 vektörlük sentetik Linux ölçümünde toplam arama 130,891 → 129,628 ms; en uzun ana zamanlayıcı aralığı 128,956 → 11,955 ms. [Ham ölçüm](provider-ai-tv-2026-09-23/embedding-benchmark.json). Bu değer video kare süresi değildir. RSS 359 → 377 MiB; test altyapısı ve SQLite girdileri dahildir, bellek tasarrufu kanıtı olarak kullanılamaz.

Dizi detayında 360×780, 412×850, 800×900 ve 900×500 yüzeyler, player→detay→grid odağıyla birlikte test edilir. TV ses seçiminde yalnız yön/Enter tuşları kullanılır. 27→28 geçişi katalog ve izleme konumunu koruyan fixture ile doğrulanır.

## Açık kalan kapsam

Native TV altyazı görüntüleme/seçimi, TV içi kanal/EPG paneli ve Cast eşliği tamamlanmış değildir. DLNA konum aktarımı ve gerçek Cast alıcısında kesinti/tek bağlantılı sağlayıcı denemesi açıktır. LAN doğrulanmış şifreli aktarım ve sır paylaşımı için açık seçim hâlâ gerekir. iOS gerçek PiP, tam lazy bölüm listesi, tüm katalog arama sıralaması, AI kalite veri seti ve platform cihaz matrisi ana takip belgesinde açık kalır.
