# TV player panelleri ve oturum yönetimi — 23 Eylül 2026

Android TV player içinde sol ok kanal listesini, sağ ok EPG panelini açar. Geri önce paneli kapatır ve odağı oynat düğmesine döndürür. Alttaki kontroller açık panelin arkasında odak alamaz. Filtrelenen kanal listesinde gizlenen eski seçimin yanlışlıkla oynatılması engellendi; boş sonuçta OK işlem yapmaz. EPG, kanal değişince eski içeriği temizler, yeni kanala abone olur ve ortak istek kapısıyla yenilenir.

Kalite, ses ve altyazı seçimleri kumandayla kullanılabilir. Kalite değişimi oynatma konumunu ve duraklatılmış durumu korur. Native kalite sınırları 480/720/1080p ve otomatik modda sınırsız yüksekliğe uygulanır; kaynakta olmayan kalite üretmez. Android Media3 altyazı parçasını taze manifest kimliğiyle doğrular. Engine içinde URL tek bir oturuma karşılık geliyorsa native player çözülür; belirsiz veya kapanmış oturum kabul edilmez. Media3 SubtitleView metin/bitmap cue'larını doğrudan gösterir, odak almaz ve kapanınca dinleyicisini bırakır. Altyazı kapalıyken ek platform görünümü kurulmaz. Tercih edilen ses/altyazı dili native yapılandırmaya taşınır.

Arka plana geçiş ve dönüş artık player route tarafından yönetilir. Kullanıcının duraklattığı video kendiliğinden başlamaz. Oynat/duraklat/sarma işleri sıralanır ve controller kapanmadan tamamlanır; eski controller'ın gecikmiş komutu yeni oturuma uygulanmaz. Opsiyonel altyazı oturumu çözümlemesi video başlangıcını bekletmez.

Uygulama dayanağı: [Media3 track selection](https://developer.android.com/media/media3/exoplayer/track-selection), [TrackSelectionOverride](https://developer.android.com/reference/androidx/media3/common/TrackSelectionOverride), [SubtitleView](https://developer.android.com/reference/androidx/media3/ui/SubtitleView). Mevcut Flutter migrator'ın Android builtInKotlin/newDsl uyumluluk bayrakları derlemede korundu.

## Doğrulama

- 425 Flutter testi; 65 Android native testi başarılı.
- Analyzer: 0 hata, 0 uyarı, 46 bilgi/stil bildirimi.
- Linux release ve Android debug APK derlemeleri başarılı.
- Kanal seçimi/sağlayıcı başlıkları, EPG/geri akışı, kalite sonrası konum/duraklama, ses/altyazı menüsü ve odak dönüşü widget testli.
- Native testler eski altyazı parçasının reddini, benzersiz oturum eşlemesini, altyazıyı kapatmanın ses parçasını etkilememesini ve platform görünümünün odak/dinleyici davranışını doğrular.
- [Makine çıktısı](tv-controls-2026-09-23/validation.json), [izole Linux açılışı](tv-controls-2026-09-23/linux-startup.json).

GitHub Build & Release workflow'u `disabled_manually` durumunda bulundu; kapatılmış workflow yeniden etkinleştirilmedi. Apple/Windows CI çalıştığı iddia edilmez. Fiziksel TV'de metin/bitmap altyazı görünümü, HDR/codec ve uzun süreli akıcılık kabulü açık. TV Cast ve catch-up eşliği bu pakette tamamlanmadı. TiViMate'in birebir doğrulanmış davranış eşliği veya tüm cihazlarda kusursuzluk iddiası yoktur.
