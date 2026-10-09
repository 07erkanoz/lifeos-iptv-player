# Linux player takip düzeltmesi

Kullanıcı `b4df487` sonrasında Linux'ta yalnız sesin kesilmesini, pause paneli açıldığında alt düğmelerin yükselmesini ve uygulama çökmesini bildirdi.

**Son kullanıcı denemesi: ses hâlâ kesiliyor.** Yeni Linux release açılarak aynı bölümde denenmesi istendi; kullanıcı ses sorununun devam ettiğini bildirdi. Bu değişiklik ses kesilmesinin çözümü olarak kabul edilmemeli. Son talep üzerine çalışma durdurulup mevcut düzeltmeler GitHub'a aktarılıyor. Gerçek kaynakta pause yerleşiminin düzeldiği ayrıca doğrulanmadı; yerleşim testi geçti.

Devralacak kişi için: `lib/utils/mpv_config.dart`, son `b4df487` commit'inde değişmemiştir; `video-sync=audio`, decoder `auto-safe` ve cache politikası korunuyor. Linux ses çıkışı PipeWire üzerindeki PulseAudio, varsayılan cihaz analog stereo/48 kHz. Çalışan uygulama son kontrol sırasında kapanmıştı; bu yüzden sorun anında sink-input/underrun ölçümü alınamadı. Sıradaki inceleme gerçek kaynak oynarken MPV audio-output/decoder loglarını ve PipeWire underrun durumunu birlikte yakalamalı. Bu aşamada ses backend'i, örnekleme veya decoder ayarlarına yeni müdahale yapılmadı.

**Kesin bulunan iki hata:** Pause yerleşimindeki Spacer/Flexible birleşimi boş alanın bir bölümünü footer altında bırakıyordu. Native çökme günlüğünde `GetFfiCallbackMetadata called after shutdown` ve libmpv core → Flutter abort zinciri vardı: engine kapanırken native callback hâlâ çağrılıyordu.

- Kontroller `PlayerControlsLayout` ile alta sabitlendi; bilgi paneli kalan alanda kaydırılıyor. 320/770 genişlik ve 240/360/720 yükseklikte, gerçek responsive toolbar ve üç panel boyuyla konumu doğrulandı.
- Desktop kapanışı engellenip tüm media_kit player'larının cleanup future'ları bekleniyor; bundan sonra pencere/Flutter engine kapanıyor. Ana player için ilerleme kaydı ve mevcut sıralı PlaybackSession kapanışı kullanılıyor. Başlamış dispose işlemleri de izleniyor; kapanırken yeni player oluşturulamıyor.
- Sessiz hero/poster/detay önizlemelerinde yalnız volume=0 kullanmak yerine audio track `no` seçiliyor. Ana oynatma sırasında önizlemeler pause oluyor; geç tamamlanan kaynak açma da otomatik başlamıyor. Hero'nun gizli rotasyonu duruyor. Sesli fullscreen fragman bu sınırlamaya dahil değil.
- Değişmeyen duration/volume olayları tüm player ağacını yeniden build etmiyor.

`289733c` ve `f2bd1e6` geçmiş düzeltmeleri incelendi. Önceki GPU/EGL/GLX düzeltmeleri, render-thread senkron sorgu yasağı, decoder/cache ayarları ve arka plan işlerini playback sırasında durdurma politikası korundu. Ses kesilmesinin tek nedeninin önizleme yükü olduğu kanıtlanmış değil; gerçek sağlayıcı kaynağında kullanıcı denemesi ayrıca gerekli.

**Doğrulama:** 15 hedefli regresyon testi geçti. Değişen kod analizinde hata/uyarı yok; 7 bilgi düzeyinde lint var. Yerel H.264/AAC fixture ve gerçek libmpv ile native Linux debug testi: iki önizlemede `aid=no`, ana oynatmada ikisi paused, 6 saniyede 6000 ms ilerleme, 48 kHz ana ses, seek/pause/reopen başarılı; üç player disposed. Üretimde kullanılan desktop shutdown listener ile gerçek GTK pencere kapanışı exit 0; FFI shutdown abort oluşmadı. Flutter kapanışında implicit-view/messenger uyarıları görüldü; işlem normal çıktı. Bu test duyulan sesin dalga biçimi veya gerçek IPTV akışındaki kesintileri ölçmez. Uygulamanın Linux release paketi de derlendi.

Native callback kapandıktan sonra onu çağırmak geçersizdir; [Dart NativeCallable sözleşmesi](https://api.dart.dev/dart-ffi/NativeCallable/NativeCallable.listener.html). Hesap/profil/veritabanı kullanmadan tekrarlanabilir kontrol `tool/linux_audio_lifecycle_smoke.dart` altında; kanıtlar `linux-player-regression-2026-10-09/` dizininde. GitHub Actions ve dağıtım çalıştırılmadı.
