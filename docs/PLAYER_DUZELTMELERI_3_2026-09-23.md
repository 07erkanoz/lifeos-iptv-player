# Player 3. paket — decoder, tampon ve Linux release denemesi

Tarih: 23 Eylül 2026. Önceki iki player paketinin üzerine uygulanmıştır.

**Takip:** İlk Linux release denemesinden sonra kullanıcının bildirdiği VOD görüntü takılması için ek GPU bağlam düzeltmesi uygulandı. Aşağıdaki ilk ölçümler yazılımsal görüntü aktarımı kullanan sürüme aittir; son sonuçlar `LINUX_VOD_AKICILIK_DUZELTMESI_2026-09-23.md` dosyasında tutulur.

## Değişiklikler

- mpv artık GPU markasına göre zorlanmıyor. Masaüstü/iOS için `auto-safe`, Android telefon için `mediacodec-copy`, donanım hızlandırma kapalıysa `no` kullanılıyor. Codec beyaz listesi kaldırılmıyor; desteklenmeyen donanım yollarından mpv'nin kendi geri dönüşü kullanılabiliyor.
- VOD'a uygulanan genel düşük gecikme profili, zorunlu GPU API'si ve üreticiye özel ölçekleyiciler kaldırıldı. Ses zamanlaması korunuyor. Açılıştaki senkron GPU taraması kaldırıldı.
- Canlı tampon 5–30 saniye/32 MiB, VOD tampon 5–120 saniye ve mobilde 64 MiB, masaüstünde 128 MiB ile sınırlandı. Geri sarma önbelleği ayrıca sınırlı. Bunlar hedef/üst sınırdır; her yayında bu kadar veri doldurma garantisi değildir.
- HLS kalite tercihi varyant bitrate seçimine bağlandı. Sabit kaliteli MP4/MKV kaynağı yeniden kodlanmaz. Yapay çözünürlük sınırı kaldırıldı.
- Android TV için `video_player_android 2.9.5` kaynakları lisansı ve yerel testleriyle `packages/video_player_android` altında tutuluyor. Yeni kanal, ExoPlayer yaratılmadan önce tampon, kalite ve decoder ayarlarını uygular. Decoder başlangıç hatasında alternatif decoder denemesi etkin. Donanım kapalıyken yalnız yazılım MediaCodec seçilir; cihazda olmayan codec desteği eklenmez.
- TV'de 20 saniyelik oynatma tampon beklemesi görünür hataya dönüşür; yeniden deneme düğmesi ve kumanda Enter/OK yeni controller açar. Başlangıç zaman aşımı 25 saniyedir. Arka plana geçince duraklatma ve ilerleme kaydı yapılır; arka planda tamamlanan başlangıç oynatmayı başlatmaz. Yerel hata metinlerindeki hesap bilgileri ekrana taşınmaz.
- Player bilgi ekranında kullanılan donanım decoder'ı, tampon süresi ve A/V farkı gösterilir.
- Linux GTK3'ün üstte tutma ve mutlak pencere konumlandırma işlemleri için X11/XWayland mevcutsa tercih edilir. Kullanıcının açık `GDK_BACKEND` tercihi korunur; XWayland olmayan sistemde Wayland kullanılabilir fakat üstte tutma desteği garanti edilmez.

## Doğrulama

Ortam: Flutter 3.47.2 / Dart 3.13.2, Linux x64, GNOME Wayland oturumu, AMD RX 590, Mesa 26.2.3. Son Linux denemesi XWayland penceresiyle yapıldı.

| Kontrol | Sonuç |
|---|---|
| Flutter testleri | 279 geçti; bu pakette 10 yeni test |
| Android eklentisi yerel testleri | 60 geçti |
| Android debug APK | Son kaynakla derlendi; fiziksel Android/TV cihaz testi yapılmadı |
| İlgili kaynaklar ve testlerin statik analizi | Temiz |
| Tüm `lib test tool` analizi | 0 hata; önceden bulunan 6 uyarı ve 21 bilgi |
| Normal Linux release | Derlendi ve masaüstünde açıldı; player görüntüsü gözlendi |
| H.264 1080p30 / HEVC 10-bit 1080p30 | İkisinde de donanım açık ve kapalı oynatma geçti |
| İleri/geri sarma | Duraklatılmış videoda 12. ve 2. saniyeye geçiş doğrulandı |
| Tam ekran | 3 giriş/çıkış döngüsü geçti |
| Küçük pencere | Tam ekrandan 380×230 pencereye geçiş ve tam ekrana dönüş geçti; oturum sonunda normal pencere geri geldi |
| Üstte tut | `xprop` ile gerçek `_NET_WM_STATE_ABOVE` eklenmesi/kaldırılması doğrulandı |

Üretilen yerel 24 saniyelik test videolarında, açılıştan pozisyonun en az 500 ms ilerlemesine kadar geçen süre H.264 donanımda 925 ms/yazılımda 677 ms, HEVC donanımda 737 ms/yazılımda 1026 ms oldu. Bunlar ağ veya uzun yayın performans ölçümü değildir. Sarma sonrası kısa örneklerin sonunda `frame-drop-count=0` okundu. Donanım açıkken gerçek decoder `vaapi-copy`, kapalıyken `no` idi. Sessize alınmış test sesi nedeniyle işitilebilir ses kalitesi ölçülmedi.

Test giriş noktası `tool/linux_player_smoke.dart`; gerçek Player, pencere, oturum, seek ve mpv yapılandırma sınıflarını kullanır. Uygulama hesabı/veritabanı yerine geçici yerel dosyalarla çalışır. Ana player ekranındaki bütün düğmelere otomatik tıklama testi değildir. Tam test kayıtları ve test penceresi görüntüsü `player-fixes-3-2026-09-23/` altında.

## Açık kalan performans sınırı

Bu makinede `media_kit_video 2.0.1`, EGL bağlamı bulunamadığı için **görüntü aktarımını yazılım yoluna düşürüyor**. Video çözmenin VAAPI üzerinde olması, görüntü aktarımının da GPU'da olduğu anlamına gelmez. Hem Impeller hem Skia ile bu durum görüldü; faydası doğrulanmayan Skia zorlaması bırakılmadı. Kısa 1080p testleri geçti, fakat bu native texture yolunun iyileştirilmesi ayrı bir takip işidir. 4K, uzun süreli canlı yayın, HDR, gerçek ağ kesintileri ve diğer işletim sistemlerinde cihaz doğrulaması hâlâ gereklidir. Bu paket için bütün platformlarda kusursuzluk iddiası yoktur.

## Release ve kullanıcı denemesi

- Çalıştırıcı: `tool/run_linux_release.sh`.
- Uygulama: `build/linux/x64/release/bundle/lifeostv`. Yanındaki `lib` ve `data` dizinleriyle birlikte kullanılmalıdır.
- Arşiv: `dist/lifeostv-linux-x64-player-fixes-2026-09-23.tar.gz` (yaklaşık 14 MiB). Bu makinede derlenen x64 pakettir; her Linux dağıtımı için bağımsız/evrensel paket değildir.
- Önce bir canlı kanal ve bir VOD açıp tam ekran → ESC → küçük pencere → geri dönüş, üstte tut ve hızlı ileri/geri sarmayı deneyin. Ardından Xtream ve M3U kaynaklarında içerikten çıkıp yeniden açarak kaldığı yerden devamı kontrol edin.

Android fork dışında paket sürümü yükseltmesi hedeflenmedi. Flutter SDK çözümlemesinin zorunlu kıldığı yedi yardımcı paket sürümü lock dosyasında ve doğrulama kopyasında kayıtlıdır; testlerde doğrudan kullanılan iki platform arayüzü dev dependency olarak tanımlandı. Kullanıcının diğer mevcut değişiklikleri korunmuştur. GitHub'a push/yayın yapılmadı.
