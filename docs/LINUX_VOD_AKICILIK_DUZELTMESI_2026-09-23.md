# Linux VOD görüntü takılması — takip düzeltmesi

Kullanıcı ilk release denemesinde sesin akıcı, görüntünün kesik kesik olduğunu bildirdi. Kısa oynatma testi bu sorunu dışlamaya yeterli değildi.

## Bulgular ve değişiklik

`media_kit_video 2.0.1` Linux eklentisi, platform kanalının çalıştığı iş parçacığında EGL bağlamının hazır olduğunu varsayıyordu. Bu makinede GTK/Flutter GLX kullanabildiğinden GPU renderer açılamıyor; video `vaapi-copy` ile çözülürken görüntünün renk dönüşümü ve aktarımı CPU yoluna düşüyordu.

Eklentinin Linux tarafında native X11/Wayland ekranından EGL başlatılması, GLX/EGL bağlamlarının geçişlerde saklanıp geri yüklenmesi ve grafik kaynaklarının bağlamdan önce temizlenmesi düzeltildi. Ayrıca render iş parçacığındaki senkron `mpv_get_property` sorguları kaldırıldı. Boyutlar zaten Dart tarafındaki `videoParams` olayından gönderiliyor; artık bu boyutlar atomik okunuyor. mpv'nin render API kurallarına aykırı senkron sorgular, oynatıcı kapanırken core/render bekleşmesine yol açabiliyordu.

Kaynaklar `packages/media_kit_video` altında, MIT lisansı korunarak tutuluyor. Değişen upstream dosyalar yalnız `linux/video_output.cc` ve `linux/texture_gl.cc`; yeni bağlam koruyucusu `linux/graphics_context.h`. Diğer platform kaynakları ve Dart API upstream 2.0.1 ile aynıdır. Ayrıntılar paketin `LIFEOSTV_CHANGES.md` dosyasında.

## Son doğrulama

- Linux x64/GNOME/AMD RX 590 üzerinde GPU renderer gerçekten açıldı. Hem H.264 hem HEVC 10-bit için `hwdec-current=vaapi`; önceki `vaapi-copy` ve CPU görüntü aktarımı artık kullanılmıyor.
- XWayland testinde her codec donanım açık ve kapalı çalıştırıldı. Her aşamada sarma sonrası 15 saniye izlendi; son ölçümlerde düşen kare sayısı 0 oldu. Başlangıç anlarında birkaç kare düşebildiği için bütün oturumun sıfır kayıpla oynadığı iddia edilmiyor.
- İleri/geri sarma, üç tam ekran giriş/çıkışı, küçük pencere ve tam ekrana dönüş geçti. Dört player açma/kapatma döngüsü tamamlandı.
- Gerçek pencere kareleri alındı ve görsel olarak kontrol edildi. Üç saniye aralıklı H.264 karelerinde 64.211, HEVC karelerinde 159.289 piksel değişti; görüntünün yalnız decoder sayacında ilerlemediği doğrulandı.
- Native Wayland ile de iki codec/dört player döngüsü geçti. Wayland altında “üstte tut” garantisi verilmez; varsayılan XWayland tercihinde gerçek `_NET_WM_STATE_ABOVE` ayrıca doğrulanmıştır.
- 279 Flutter testi geçti; bütün `lib test tool` analizinde 0 hata, önceden bulunan 6 uyarı/21 bilgi var. Normal Linux release yeniden derlendi ve açıldı.

GPU üzerindeki doğrudan VAAPI karelerinde mpv'nin ham ekran görüntüsü komutu libswscale dönüşüm hatası üretti. Bu test yolu doğrudan GPU karelerinde kullanılmıyor; bunun yerine işletim sisteminden gerçek pencere görüntüsü alınıyor. Uygulamanın player akışına böyle bir screenshot çağrısı eklenmedi.

Kanıtlar: `player-fixes-3-2026-09-23/gpu-final.log`, `gpu-final.json`, `gpu-wayland.log`, `gpu-wayland.json`, `gpu-window-*.png`. İlk release'in yazılımsal renderer ölçümleri aynı klasörde geçmiş kayıt olarak durur.

## Kullanıcı kontrolü

Güncel çalıştırıcı `tool/run_linux_release.sh`; güncel paket `dist/lifeostv-linux-x64-player-fixes-2026-09-23.tar.gz`. Otomatik testler üretilen yerel videolarla yapıldı. Kullanıcı güncel release denemesinin ardından olumlu geri bildirim verdi ve düzeltmelerin GitHub’a gönderilmesini istedi. Uzun süreli/4K oynatma, farklı sağlayıcılar ve diğer platformlarda gerçek cihaz doğrulaması açık kalıyor. Güncel iş sırası: [Kalan işler](KALAN_ISLER_2026-09-23.md).
