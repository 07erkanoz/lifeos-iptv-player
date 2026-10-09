# LifeOS TV — F03 sonrası düzeltmeler ve doğrulama

9 Ekim 2026. Bu belge [yayın öncesi incelemedeki](YAYIN_ONCESI_INCELEME_2026-10-09.md) bulgulara uygulanan düzeltmeleri anlatır. Önceki rapor tarihsel inceleme olarak korunmuştur. Dağıtım, GitHub Actions ve imzalama işleri kullanıcının isteğiyle ertelendi. Yerel Linux/Android release paketleri dağıtım onayı anlamına gelmez.

## Uygulanan değişiklikler

| Bulgu | Yapılan düzeltme | Kalan doğrulama |
|---|---|---|
| F03–F04 | Metin görevleri ortak taşıyıcıyla `gemini-3.8-flash` kullanıyor; embedding ayrı kalıyor. LOW/MEDIUM düşünme ayarları, header üzerinden anahtar, thought olmayan parçaların birleşimi, çağrı `id` eşlemesi ve turlar arasında araç/imza geçmişi eklendi. Paralel araçların gerçek yanıtları korunuyor. | Gerçek API anahtarıyla erişim, kota, gecikme ve Türkçe dahil yanıt kalitesi eval seti. |
| F05 | Dizi bölümleri immutable liste ve async geçiş kilidiyle aynı player route'unda açılıyor. Önce eski bölümün ilerlemesi kaydediliyor; yeni bölüm kimliği yayınlanmadan eski zamanlar temizleniyor. | Fiziksel cihazlarda sezon sınırı, bozuk kaynak ve farklı codec geçişleri. Masaüstünde Player korunuyor; Android TV backend'i kaynak başına native controller değiştirebilir. |
| F06 | Android TV'de kapsamlı intro marker desteği, kumanda ile işaretleme/atlama ve ayara bağlı tek seferlik completion/auto-next eklendi. | Gerçek TV kumandası ve decoder ile uzun oynatma. Cast sırasında yerel bölüm değiştirme düğmeleri sunulmuyor. |
| F07 | Film detay istekleri nesil ve hesap kimliğiyle korunuyor; kapanan veya başka içeriğe geçen detay eski async yanıtla güncellenmiyor. | Ağ gecikmeli gerçek UI denemesi. |
| F08 | Kürtçe uygulama çevirileri korunurken Flutter framework için eksik Material/Cupertino/Widgets delegeleri İngilizce fallback ile sağlandı. | Framework metinlerinin yerel Kürtçe çevirisi; tüm dillerde dilbilimsel inceleme. |
| F09–F10 | macOS dosya seçimi sandbox yetkisi, yerel ağ kullanım açıklaması ve kullanılan Bonjour servisleri eklendi. | İmzalı Mac uygulamasında izin reddi/yeniden izin, yedek içe/dışa aktarma ve keşif. |
| F11 | AI işlemi bütün HTTP ve araç await'lerini kapsayan iptal token'ı taşıyor. Timeout, yeni tur, kapanma ve hesap/profil değişimi eski işi iptal ediyor; mutasyon ve navigasyon öncesinde geçerlilik kontrol ediliyor. | Gerçek servis ve işletim sistemi izin gecikmeleri. |
| F13–F14 | Kör 90 saniye atlama kaldırıldı. Skip yalnız doğrulanmış bölüm marker'ı veya açık intro chapter sınırı varsa gösteriliyor. Hesap/dizi/sezon/bölüm kapsamı, süre sınırları, source/confidence ve silme kayıtları eklendi. | Görüntü/ses fingerprint analizi henüz yok. Chapter okumayı masaüstü/mobile media_kit backend'i yapıyor; TV'de manuel/senkron marker kullanılıyor. |
| F15 | Intro marker'ları LAN ilerleme kategorisine ve backup v5'e eklendi. Silme kaydı eski marker'ın dirilmesini engelliyor; M3U'da hem dizi hem bölüm gerçek kaynak kimliğiyle eşleniyor. | İki fiziksel cihazda öğren/düzelt/sil turu. Eski uygulama yeni marker alanlarını kullanamayabilir; iki cihaz da güncellenmeli. |
| F16 | UI ve AI için ortak çözülmüş sistem dili kullanılıyor. Öneri cache'leri hesap/profil/dil kapsamında; yedek dialog ve ilgili player mesajları çevriliyor. | Sekiz dilde bütün ekranların insan tarafından incelenmesi. |
| F17 | System/light/dark gerçek üç değerli ThemeMode eşlemesi kullanıyor. | Her işletim sisteminde sistem tema değişimi. |
| F18 | Gemini istemcisi yalnız anahtar değişiminde yenileniyor, dispose bağlantıları iptal edip kapatıyor. Kota/auth/timeout/network/blocked/truncated/tur sınırı ayrılıyor; ham AI yanıtı ve anahtar loglanmıyor. | Gerçek API başarısızlıkları ve telemetry UI incelemesi. |
| F19 | Sohbet öneri ve araç şemaları içerik türünü taşıyor; film/dizi/canlı aynı sayısal ID'yle ayrı çözülüyor. Masaüstüne çalışmayan hatırlatma aracı ilan edilmiyor. | Canlı AI önerilerinin katalogla eşleşme kalitesi. |
| F20 | Hero'nun yeni içerik havuzu SQL'de sayısal `added` sırasıyla seçiliyor; limit sıralamadan sonra uygulanıyor. | Büyük gerçek katalogda çeşitlilik ve yeni içerik eval'i. |

F12 bu pakette ertelendi: mevcut PIN eşleştirmesi korunuyor, ek kullanıcı şifresi yok. Bu değişiklik aktarımı şifreli hale getirmedi; önceki rapordaki taşıma güvenliği bulgusu açıktır. F01 imza materyali ve F02 dağıtım hattı da dağıtım aşamasına kaldı.

## Boyuta göre player kontrolleri

Alt çubuk yatayda kırpılmıyor. Geniş alanda etiketler gösteriliyor; daralınca ikonlara geçilip düğme/gap ölçüleri küçülüyor. Sığmayan kontroller ikinci/üçüncü sıraya yerleşiyor. İkonların açıklaması tooltip ve erişilebilirlik etiketiyle korunuyor. Sabit action kimliği yeniden boyutlandırmada klavye odağını koruyor. Telefonda dokunma hedefi en az 44 piksel; alt SafeArea iPhone home indicator alanını koruyor. Pause bilgi paneli kısıtlı yükseklikte kaydırılabiliyor.

240–1400 piksel, masaüstü/dokunmatik, 2× yazı, Arapça yönü ve resize sırasında odak testleri eklendi. Gerçek widget'ın 320/770/1000/1400 piksel render'ları kontrol edildi. Bunlar izole toolbar görüntüleridir; tam uygulamanın fiziksel cihaz ekran görüntüleri değildir.

## iPhone için yapılanlar ve açık sınırlar

- Eksik CocoaPods Podfile, Pods xcconfig ve workspace bağlantıları tamamlandı. Deployment target ve App framework minimum sürümü **iOS 15** olarak hizalandı.
- Yerel ağ, mikrofon ve speech permission açıklamaları sekiz dilde string catalog'a eklendi. Xcode kaynak bağlantıları ve native yapılandırma kontrolleri eklendi.
- AVAudioSession kurulum hatası Dart'a gerçek hata olarak dönüyor. Telefon/sistem ses kesintisi ve kulaklık çıkarma olayları player'a aktarılıyor. Yalnız önceden oynayan aynı medya, uygulama öndeyken ve sistem izin veriyorsa otomatik devam ediyor. Kullanıcının duraklatması ve arka plana geçiş otomatik devamı iptal ediyor.
- Player aktifken uygulama yeniden build/resume olduğunda root sistem çubuğu ayarı fullscreen durumunu bozmuyor. Player çıkışında uygulama modu geri yükleniyor.

Linux üzerinde Xcode, CocoaPods kurulumu, Swift derlemesi veya gerçek iPhone codec testi yapılmadı. Plist/entitlement XML, privacy catalog ve Podfile syntax kontrolleri geçti; RunnerTests bu ortamda çalıştırılmadı. Bunlar iOS release derlemesinin geçtiği anlamına gelmez.

Mevcut iOS renderer texture/libmpv; native PiP uygulanmış değil, düğmesi gizli. Yerel video arka plana geçince duraklıyor. iOS DLNA/SSDP multicast için Apple onaylı capability ve doğru provisioning ayrıca gerekebilir; bu yetki eklenmiş/onaylanmış sayılmıyor. HTTP IPTV uyumluluğu için mevcut ATS istisnası korunuyor; Apple yayın değerlendirmesinde incelenmeli. [Apple yerel ağ rehberi](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy), [multicast yetkisi](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast).

## Test ve performans kanıtları

| Kontrol | Sonuç |
|---|---|
| `flutter analyze lib test tool --no-pub --no-fatal-infos` | Hata/uyarı yok; 90 bilgi düzeyinde lint. |
| `flutter test --no-pub --reporter expanded` | **518 test geçti**; önceki 482 teste 36 regresyon kontrolü eklendi. |
| Toolbar render + intro/cache ek kontrolleri | 13 kontrol geçti; render testi geçici test dosyasından çalıştırıldı. |
| Sentetik katalog/embedding benchmark | 2 kontrol geçti. |
| Linux release | Son kaynaklarla yeniden derlendi; binary bağımlılık kontrolünde eksik kütüphane bulunmadı. |
| Android release | Son kaynaklarla yeniden derlendi; universal APK yaklaşık 125.9 MB. |
| Apple dosya kontrolleri | 5 plist/entitlement belgesi parse edildi, privacy catalog 3×8 dil, Podfile Ruby syntax başarılı. Swift/Xcode testleri yapılmadı. |

Derlemeler tamamlandıktan sonra yapılan 10 bin içerik fixture'ında indeksli arama **5.0 ms**, indekssiz doğru yazım **622 ms**, indekssiz yazım hatalı arama **1047 ms** sürdü. İndekssiz yol hâlâ daha yavaş; başlangıç/senkron sonrası indeksin hazır olması önemlidir. Worker yolunda ana timer'ın en uzun aralığı 24–35 ms; aynı kataloğu ana isolate'da tarayan karşılaştırmada 184 ms ölçüldü. 10 bin × 768 boyutlu semantic fixture'da worker toplam 180 ms, ana timer aralığı 33 ms; ana isolate karşılaştırması toplam 128 ms ve timer aralığı 129 ms. Worker toplam sürenin mutlaka kısa olmasını sağlamaz; UI işinin daha uzun bloklanmasını azaltır. Bunlar önceki release'e karşı FPS kazancı iddiası değildir.

Android build mevcut Gradle 8.14 / AGP 8.11.1 / Kotlin 2.2.20 için Flutter'ın gelecekte destek kaldırma uyarısını ve SDK XML sürüm uyarısını veriyor. Toolchain geçişi yayın hazırlığında ayrı plugin uyumluluk kontrolüyle yapılmalı. İlk Linux build'inde üçüncü taraf SQLite C kaynaklarında const-pointer uyarıları görüldü; derleme başarılıydı. Testlerde hesap kapsamlı ortak executor görünümleri için Drift'in multiple database bildirimi bulunur; test logları korunmuştur.

Güncel sonuçlar ve sentetik benchmark verileri [doğrulama dizininde](f03-validation-2026-10-09/) tutulur. Benchmark gerçek video FPS, dropped-frame, GPU tüketimi veya fiziksel TV performansı ölçmez. SQLite fixture/test süreci RAM'i içerir. Gerçek yayına çıkmadan önce aşağıdaki cihaz matrisi tamamlanmalı.

Eski `docs/audit-2026-09-23/` probe dosyaları önceki API'leri kullanan tarihsel testlerdir; kök dizinde sınırsız `flutter analyze` onları da kapsar. Uygulama için analiz kapsamı `lib test tool` olarak seçildi. Mevcut bilgi düzeyindeki lint'ler yayın onayı olarak yorumlanmamalı.

## Yayın öncesi kalan cihaz kontrolleri

| Platform | Zorunlu deneme |
|---|---|
| Android TV | D-pad/Back detay→player→detay→grid, hata veren canlı kanalda geçiş, H.264/HEVC/MPEG-2, ses/altyazı, intro/auto-next ve ilk kurulum LAN. |
| Android telefon | Dokunmatik kontroller, yön değişimi, arka plan/PiP, cast, izin reddi ve yedek. |
| Linux | Küçük/tam ekran dönüşleri, her zaman üstte, VOD seek/bölüm geçişi, GPU decoder ve uzun oynatma. |
| macOS | İmzalı sandbox build, dosya/yerel ağ izinleri, fullscreen ve Apple Silicon/Intel medya. |
| Windows | Gerçek release, pencere/fullscreen, codec ve driver matrisi, LAN firewall ve kurulum/güncelleme. |
| iPhone | Xcode build/native testler, fiziksel notch/SafeArea ve rotation, telefon kesintisi/kulaklık, AirPlay/cast/LAN izinleri, restore ve uzun HEVC/H.264 oynatma. |

Gerçek Gemini hesabıyla küçük bir eval setinde doğru katalog kimliği, Türkçe cevap kalitesi, araç eylemi doğruluğu, gecikme ve kota ölçülmeli. Android TV AI hâlen ürünün mevcut platform politikasına göre kapalıdır; bu paket onu etkinleştirmiyor. Bütün platformlarda “kusursuz” veya “yayına hazır” onayı verilmedi.
