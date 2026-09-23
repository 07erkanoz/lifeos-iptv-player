# Player düzeltmeleri sonrası kalan işler — 23 Eylül 2026

Bu belge [ilk incelemenin](PROJE_INCELEME_RAPORU_2026-09-23.md) güncel takip listesidir. İlk rapor tarihsel bulguları korur; bütün maddelerin hâlâ açık olduğu anlamına gelmez. GitHub’dan gelen [arayüz ve performans raporu](../duzeltme.md) da aşağıdaki sıraya dahil edilmiştir.

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

- Hesap değişiminde diğer profillerin favori/geçmiş kayıtlarının silinmesini engelle (B03).
- Yeni hesap ile varsayılan hesap seçimini tutarlı yap (B04).
- Yedek geri yüklemede hesap/profil kimliklerini eşle; eksik tabloları ve güvenli geri dönüşü ele al (B05).
- M3U kimlik çakışmalarını ve dizi/bölüm geçmişi kimlik kapsamını düzelt (B06, B07’nin kalan kısmı).
- AI üzerinden oynatmada profil PIN ve görünürlük kurallarını uygula (B20).

Kabul: iki hesap/iki profil arasında geçiş ve yedek geri yükleme veri kaybettirmemeli; 100 bin M3U kaydında kimlik çakışması satır silmemeli; kilitli içerik AI yoluyla açılamamalı.

### 2. Senkronizasyon doğruluğu ve süresi

- Timeout tekrarlarını toplam deneme/süre bütçesiyle sınırla; başarısız senkronu tamamlandı olarak işaretleme (B01, B02).
- Manuel/otomatik/ilk giriş senkronunu hesap bazlı ortak koordinatörde birleştir (B22).
- Tam yenilemede mevcut detay metadatasını koru (B21).
- Büyük M3U/XMLTV ayrıştırmasını ana isolate dışına taşı; bellek, EPG temizleme ve cache ömrünü sınırla (B23–B25).

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
- M3U etiket/virgül/format varyasyonlarında veri kaybını düzelt (B26).
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

- LAN senkronunda hesap/profil sınırlarını ve kimlik eşlemesini koru (B34).
- Kriptografik rastgele eşleme anahtarı, süre/deneme sınırı ve doğrulanmış şifreli aktarım ekle; sır paylaşımını açık seçime bağla (B35).
- Hatırlatıcı kaydetme ile gerçek işletim sistemi bildirimi arasındaki eksik akışı tamamla (B37).

### 8. Platform entegrasyonu ve yayın kontrolleri

- iPhone mikrofon/konuşma izinleri, gerçek PiP ve Bonjour tanımlarını tamamla (B17, B18).
- Android’in hedef SDK tam ekran davranışını cihaz üzerinde düzelt/doğrula (B19).
- Apple CI ve Android release imzalama yolunu düzelt; kritik akışların platform testlerini genişlet (B40, B41).
- `ONEMLI.md` içindeki eski/yarım şema geçişleri, şema doğrulaması ve geçiş öncesi yedek teknik borcunu tamamla.

İlk başlanacak paket: veri kaybını engelleyen 1. başlık ve ardından senkronizasyon. Player için gerçek cihaz/uzun oynatma testleri cihaz erişimi oldukça aynı takvimde yürütülebilir.
