# Player düzeltmeleri sonrası kalan işler — 23 Eylül 2026

Bu belge [ilk incelemenin](PROJE_INCELEME_RAPORU_2026-09-23.md) güncel takip listesidir. İlk rapor tarihsel bulguları korur; bütün maddelerin hâlâ açık olduğu anlamına gelmez. GitHub’dan gelen [arayüz ve performans raporu](../duzeltme.md) da aşağıdaki sıraya dahil edilmiştir.

Güncelleme: [1. paket](VERI_BUTUNLUGU_1_2026-09-23.md) aktif hesap otoritesi ve güvenli geri yüklemeyi; [2. paket](VERI_BUTUNLUGU_2_2026-09-23.md) hesap kapsamlı şema 26, veri koruyan hesap geçişi, yedek v3 ve eski arka plan yazıcılarının engellenmesini uyguladı. 325 Flutter testi, Linux release derlemesi ve yalıtılmış release açılış kontrolü geçti. B03’ün kod/otomatik test kısmı tamamlandı; gerçek hesaplarla platform kabul denemeleri açık.

Son ek: [Senkron dayanıklılığı](SENKRON_DAYANIKLILIK_2026-09-23.md) paketiyle sınırlı HTTP tekrarları, 5 dakikalık katalog iş bütçesi, ortak hesap koordinatörü, iptal ve gerçek hata bildirimi uygulandı. **353 Flutter testi, Linux release derlemesi ve ayrı veri dizininde açılış kontrolü geçti.**

Yeni ek: [M3U/XMLTV dayanıklılığı](M3U_XMLTV_DAYANIKLILIK_2026-09-23.md): kalıcı M3U kimlikleri, şema 27/yedek v4, ayrıştırma işçileri, 100 bin kayıt temizliği, atomik EPG değişimi ve XMLTV bellek TTL düzeltmesi. **373 Flutter testi geçti.**

Yeni paket: [Dizi, canlı TV, odak ve arama](DIZI_CANLI_TV_ODAK_2026-09-23.md). B07–08 dizi/bölüm geçmişi ve M3U sezon modeli uygulandı. B20 için ortak PIN ve görünür içerik çözümlemesi; B27 eski sorgu iptali; B29 tür çakışması ve kapsam koruması uygulandı. B28 indeks eksikleri/metadata geçersizliği kısmen düzeltildi; tam katalog arama sıralaması ve embedding güncelliği açık. EPG artık ortak iş, süre bütçesi, hata sonrası tekrar ve manuel XMLTV yenileme içeriyor. Odak/geri yönlendirmesi sayfa bazında, player→detay→grid ve ayarlar panel dönüşleri testli. Bu paket bütün platformların gerçek cihaz kabul testinin tamamlandığı anlamına gelmez.

## Tamamlanan ve doğrulanan bölüm

- Player oturumunda açma/kapatma/yeniden deneme işlemlerinin sıralanması; geciken sonuçların kapanmış player’a uygulanmasının engellenmesi.
- Tam ekran, küçük pencere ve eski pencere boyutuna dönüş; Linux XWayland altında gerçek üstte tutma durumu.
- VOD sürükleyerek ve tuşlarla sarma işlemlerinin birleştirilmesi, sınırlandırılması ve sıralanması.
- M3U doğrudan oynatma URL’si, Xtream uzantı/direct-source çözümü ve oynatma geçmişine açık içerik kimliği aktarımı. Şema 24 geçişi.
- Android TV codec tercihi ve buffer ayarlarının yerel oynatıcıya aktarılması; arka plan/yeniden deneme/zaman aşımı akışları.
- Linux GPU renderer için EGL/GLX bağlam yönetimi ve render iş parçacığından kilitlenmeye yol açabilen senkron mpv sorgularının kaldırılması. [Takılma düzeltmesi](LINUX_VOD_AKICILIK_DUZELTMESI_2026-09-23.md).

Son doğrulamalar: 279 Flutter testi, 60 Android yerel testi, Linux release ve Android debug derlemesi. Linux’ta H.264/HEVC 10-bit, donanım açık/kapalı, sarma ve pencere geçişleri denendi. Kullanıcı güncel Linux release için olumlu geri bildirim verdi. Android testleri gerçek cihaz testi değildir; Windows, macOS ve iPhone için bu değişikliklerin cihaz doğrulaması tamamlanmadı.

## Önerilen uygulama sırası

### 1. Hesap, profil ve veri bütünlüğü

- B03 uygulandı: hesap değişiminde katalog, favori ve geçmiş korunur; aynı sağlayıcı ID’leri hesap/profil anahtarıyla ayrılır. Gerçek hesaplarla kabul denemesi açık.
- Yeni hesap ile varsayılan hesap seçiminde DB otoritesi sağlandı (B04); katalog ve kullanıcı verisinin hesap izolasyonu 2. pakette uygulandı.
- Yedek v3, profil/hesap kimlikleri, kullanıcı tabloları, ön doğrulama ve kurtarma günlüğü tamamlandı (B05). Restore eski yazıcıları geçersiz kılar; tüm senkron yollarının ortak koordinasyonu B22 ve gerçek cihaz testleri açık.
- B06 uygulandı: tam kaynak anahtarını doğrulayan kalıcı eşleme, çakışma çözümü ve eski katalog kimliğini koruma. Dizi/bölüm geçmişi kapsamı ve M3U sezon/bölüm modeli açık (B07–08).
- AI üzerinden oynatmada profil PIN ve görünürlük kurallarını uygula (B20).

Kabul: iki hesap/iki profil arasında geçiş ve yedek geri yükleme veri kaybettirmemeli; 100 bin M3U kaydında kimlik çakışması satır silmemeli; kilitli içerik AI yoluyla açılamamalı.

### 2. Senkronizasyon doğruluğu ve süresi

- B01/B02 katalog akışında uygulandı: sınırlı GET tekrarı, toplam iş süresi, iptal, bozuk yanıt reddi ve hata sonrası güncellik koruması. EPG/XMLTV hata/iptal politikası açık.
- B22 katalog giriş yollarında uygulandı: ilk giriş, manuel ve kademeli yenileme hesap bazlı tek işi paylaşır. EPG/LAN işleri ayrı kapsamda.
- B21 Xtream liste yenilemesinde uygulandı: eksik detay alanları ve kategori gizliliği korunur. M3U metadata ve kategori gizliliği de yeni pakette korunuyor.
- B23 kısmen uygulandı: M3U parse/sınıflandırma/kimlik ve XMLTV parse işçide, indirme başına 64 MiB sınır, EPG zaman penceresi. XMLTV streaming parser, gerçek cihaz frame/tepe bellek ölçümü ve çalışan işçiyi iptal etme açık.
- B24 uygulandı: 500 ID’lik silme grupları, geçerli M3U’da tamamen kaybolan türün temizlenmesi, kanal bazında atomik EPG değişimi.
- B25 uygulandı: RAM’de altı saat TTL, tam URL eşlemesi, ortak bekleyen istek ve eski isteğin cache’i yeniden doldurmasının önlenmesi. Force API var; EPG manuel yenileme UI bağlantısı açık.

Kabul: ağ kesintisi ve hesap değişiminde eski sonuçlar yeni hesaba yazılmamalı; eşzamanlı çağrılar tek senkron çalıştırmalı. Büyük kataloglarda süre, bellek ve arayüz kare süreleri önce/sonra ölçülmeli.

### 3. Player’ın kalan özellikleri ve dayanıklılığı

- Android TV’de ses/altyazı seçimi, kanal/EPG, kalite ve Cast özelliklerinin masaüstüyle farklarını kapat (B16).
- Cast’e VOD konumunu aktar; altyazı indirme boyutu, süre ve hata sınırlarını ekle (B36, B39).
- Oynatma sırasında AI arka plan işlerinin gerçekten durakladığını doğrula ve kalan koordinasyon sorununu düzelt (B33).
- Uzun süreli 4K/yüksek bitrate/HDR, çoklu ses ve altyazı, HLS/canlı yayın, ağ kopması ve yeniden bağlanma senaryolarını çalıştır.
- Android telefon/TV, Windows, macOS ve iPhone’da gerçek cihaz testleri; Linux’ta farklı GPU/sürücüler. Native Wayland’da pencere yöneticisinin üstte tutma kısıtını ayrıca değerlendir.

Kabul: codec/cihaz matrisi ve ölçülen açılış süresi, düşen kare, A/V farkı, CPU/GPU/bellek değerleri kaydedilmeli. Linux’taki mevcut sonuç diğer platformların tamamı için başarı sayılmamalı.

### 4. M3U/Xtream sağlayıcı uyumluluğu

- M3U dizi → sezon → bölüm akışını tamamla (B08).
- B26 parser kısmı uygulandı: tırnaklı virgül/apostrof, büyük harfli/tırnaksız alan, BOM, URL’siz EXTINF sonrası toparlanma, bağıl URL ve token’lı VOD sınıflandırması. EXTVLCOPT/KODIPROP başlıklarını player’a taşıma açık.
- Xtream alt dizinli panel adreslerini ve M3U URL’sinin yanlış Xtream hesabına dönüştürülmesini ele al (B10’un kalan kısmı). Oynatma yolundaki özel karakter kodlaması tamamlandı.

### 5. Mobil ve dar pencere arayüzü

- Bölüm verisini ortak modelde normalize et; eksik başlık ve geçersiz ID’leri güvenli işle (B38 ve GitHub raporu).
- Genişliğe göre film/dizi detay düzeni; mobilde iki satırlı bölüm başlığı ve yatay sezon seçici.
- Bölüm listesini gerçek lazy listeye dönüştür; fragmana ayrılmış alan ve kontrollü otomatik oynatma ekle.
- Görünmeyen ekranların animasyon/abonelik yükünü durdur; blur/gölge yükünü ölçerek azalt.

Kabul: 360/412 px telefon, 800 px tablet ve 900×500 masaüstü penceresinde uzun başlık/çok sezon/fragman açık durumları taşmadan çalışmalı.

### 6. Arama ve yapay zekâ kalitesi

- Temizlenen sorgunun eski sonucunun geri dönmesini engelle (B27).
- Eksik/bayat arama indeksini ve güncel metadata eşleşmesini düzelt (B28).
- AI arama/oynatma sonuçlarında hesap, içerik türü ve görünürlük kapsamını koru (B29).
- Her sorguda bütün embedding’leri yüklemeyi bırak; vektör güncelliği ve sorgu/belge ayrımını kur (B30, B31).
- Düşük güvenli tahminleri gerçek metadata gibi kaydetme; doğruluk ve maliyet/gecikme ölçümlerini tamamla (B32, B42).

Kabul: Türkçe sorgu veri setinde tam başlık, yazım hatası, oyuncu/tür ve anlamsal sorgular karşılaştırılmalı; olmayan ID, yanlış hesap ve gizli içerik sonucu sıfır olmalı.

### 7. LAN eşleme, aktarım ve hatırlatıcılar

- LAN senkronunda hesap kimliği doğrulaması uygulandı; profil/cihazlar arası içerik kimliği eşlemesinin kalan kısmını tamamla (B34).
- Kriptografik rastgele eşleme anahtarı, süre/deneme sınırı ve doğrulanmış şifreli aktarım ekle; sır paylaşımını açık seçime bağla (B35).
- Hatırlatıcı kaydetme ile gerçek işletim sistemi bildirimi arasındaki eksik akışı tamamla (B37).

### 8. Platform entegrasyonu ve yayın kontrolleri

- iPhone mikrofon/konuşma izinleri, gerçek PiP ve Bonjour tanımlarını tamamla (B17, B18).
- Android’in hedef SDK tam ekran davranışını cihaz üzerinde düzelt/doğrula (B19).
- Apple CI ve Android release imzalama yolunu düzelt; kritik akışların platform testlerini genişlet (B40, B41).
- `ONEMLI.md` içindeki eski/yarım şema geçişleri, şema doğrulaması ve geçiş öncesi yedek teknik borcunu tamamla.

Sıradaki paket: sağlayıcı oynatma başlıkları (B26’nın kalanı), TV player kontrolleri (B16), Cast/altyazı sınırları (B36/B39), embedding ve AI iş yükü (B30–33). Player için gerçek cihaz/uzun oynatma testleri cihaz erişimi oldukça aynı takvimde yürütülebilir.
