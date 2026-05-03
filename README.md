
# LifeOS IPTV Player
Flutter ve media_kit (libmpv) altyapısı üzerine kurulu, performans odaklı çapraz platform IPTV oynatıcı. Proje, şişirilmiş ve reklam barındıran uygulamalara karşı hafif, hızlı ve yüksek uyumluluk sunan bir alternatif olarak geliştirilmiştir.

## Platform Durumu
 * **Linux & Windows:** Masaüstü ortamlarında stabil çalışma. Yerel pencere yönetimi, akıcı liste kaydırma, in-app PiP (Windows + macOS) deneyimi.
 * **Android Mobil:** Dokunmatik arayüz desteği ve donanım hızlandırmalı video oynatma sorunsuz çalışmaktadır. Native PiP (Android 8+) ve auto-PiP (Android 12+) tam entegre.
 * **Android TV:** Uygulama çalışmaktadır ancak D-Pad (kumanda) navigasyon ve odaklanma (focus) yönetimi şu an için sorunludur.
 * **iOS:** HTTP IPTV stream'leri, mDNS Chromecast keşfi ve background audio için Info.plist + AppDelegate Method/EventChannel'ları yapılandırıldı. AVPictureInPictureController entegrasyonu (gerçek PiP) gelecek sprint.
 * **macOS:** Sandbox network entitlements (Release dahil) yapılandırıldı; HTTP IPTV stream'leri Release build'lerde de çalışır.

## Desteklenen Özellikler
 * **Xtream Codes API:** Tam destek. Kullanıcı girişi, kategori çekme, VOD/series detay info'su, EPG sorunsuz çalışır. Sunucu-dostu API kuyruğu (queue + cache + exponential backoff + günlük limit) ile sağlayıcıların `1-connection ban` politikalarına uyumlu.
 * **M3U Playlist:** İndir, parse et, kategorilere ayır. Re-sync sonrası kanal id'leri stabil (FNV‑1a hash) — favoriler / izleme geçmişi referansları korunur.
 * **EPG (Elektronik Program Rehberi):** Tam entegre. Xtream API + XMLTV (4 fazlı kanal eşleştirme + Türkçe `.com.tr` suffix tolere) çift kaynak.
 * **Video Motoru:** media_kit (Native libmpv backend) sayesinde geniş codec ve format desteği, kasmayan canlı yayın deneyimi. Per-GPU adaptive ayarlar (NVIDIA / AMD / Intel / Adreno / Mali / Apple).
 * **Watchlist (Listem):** "Daha sonra izle" — favorilerden ayrı liste. Dashboard'da kendi carousel'i.
 * **Continue Watching:** Otomatik kaldığın yerden devam (95% eşik ile "izlendi" işaretlenir).
 * **YouTube Fragman Fallback:** Sunucu trailer URL'si yoksa, "VOD adı + yıl + trailer" ile YouTube arama. Hiçbir VOD fragman butonsuz kalmaz.
 * **Stream Stats Overlay:** Player'da `i` tuşu / butonu → resolution, codec, bitrate, fps, dropped frames.
 * **Sıralama:** Movies/Series gridlerinde "En Yeni" / "Puana göre" / "Ada göre" — her ekran kendi modu hatırlar.
 * **Backup / Restore:** Hesaplar + favoriler + watchlist + history + ayarlar tek JSON dosyasında ihraç/ithal. Atomik (başarısızlık DB'yi yarı uygulamış halde bırakmaz).
 * **OpenSubtitles:** API key ile altyazı arama + indirme + SRT→VTT dönüşümü.
 * **Chromecast:** mDNS keşfi (Android + iOS), Default Media Receiver üzerinden cast.
 * **Lokalizasyon:** 8 dil tam çeviri — Türkçe, English, Deutsch, Français, Español, العربية, Русский, Kurdî.
 * **Tema:** Material 3 dark / light, Inter font.
 * **Sleep Timer:** Süre veya bölüm sonu.
 * **Subtitle Search Overlay (VOD):** OpenSubtitles entegre arama + indirme + uygulama.

## Bilinen Sorunlar
 * Android TV için D-Pad navigasyon (focus) mantığının henüz sağlıklı çalışmaması. Bu konu üzerinde geliştirmeler devam etmektedir (Veya katkıda bulunmak isteyenler için öncelikli konudur).
 * iOS PiP (`enterPipMode`) şu anda no-op döner — gerçek `AVPictureInPictureController` entegrasyonu sonraki sprint'te.
 * Çoklu kullanıcı profili henüz yok (tek kullanıcı varsayımı).

## Kurulum ve Çalıştırma
Projeyi yerel ortamınızda derlemek için:
```bash
flutter pub get

# Hedef platformun derleme gereksinimlerini (örn: Linux/Windows için libmpv) karşıladığınızdan emin olun.
flutter run
```

## Geliştirme

### Codegen
Drift (SQLite ORM) ve Riverpod generated dosyaları için:
```bash
dart run build_runner build --delete-conflicting-outputs
```
Tablo, repository veya provider eklediğinizde / değiştirdiğinizde yeniden çalıştırın.

### Lokalizasyon
ARB dosyalarını düzenledikten sonra:
```bash
flutter gen-l10n
```

### Test
Tüm unit testleri çalıştır:
```bash
flutter test
```
Mevcut kapsama: M3U / XMLTV parser, sıralama, YouTube trailer fallback, stream URL builder, içerik filtresi, AccountInfo, ApiCache (TTL + SWR), srtToVtt — toplam **87 test**.

### Lint
```bash
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
```
Sadece hatalarda fail eder; mevcut style suggestion'ları (info/warning) bloklamaz.

## CI/CD
GitHub Actions workflow'u (`.github/workflows/build.yml`):
* `test` job: `flutter analyze` + `flutter test` — her push ve PR'da çalışır, build'leri **gate'ler**.
* `build-linux` (.deb), `build-windows` (.zip), `build-macos` (.zip), `build-ios` (unsigned), `build-android` (.apk) — testler geçtikten sonra paralel çalışır.
* `release`: tag push'unda (`v*`) tüm artifactler bir GitHub Release'e bağlanır.

## Katkıda Bulunma
Özellikle Android TV focus sorunları konusunda katkılarınızı veya PR'larınızı memnuniyetle kabul ederim. PR açmadan önce `flutter analyze` ve `flutter test` çıktılarının yeşil olduğundan emin olun (CI zaten engelleyecek).

**Lisans:** MIT
