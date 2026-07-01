# 📺 Android TV — Yapılan Çalışmalar (Değişiklik Günlüğü)

Bu dosya, `lifeos-iptv-player` uygulamasının **Android TV** sorunları için yapılan
tüm çalışmaların kronolojik ve alan-bazlı özetidir. Amaç: TV'de çökme/donma/
yavaşlık sorunlarını gidermek ve deneyimi TiViMate seviyesine yaklaştırmak.

> Detaylı ilk analiz: `androidtv_sorun_analizi.md`. Bu dosya ise **ne yaptığımızı**
> takip eder.

---

## 🔑 Temel kararlar
- **TV yalnızca `PlatformHelper.isTV` ile ayrışır.** Mobil / Windows / Linux /
  macOS / iOS davranışına dokunulmaz — kullanıcı bu platformlarda sorun yaşamıyor.
- **Oynatıcı bölünmesi:** Android **TV** → ExoPlayer (`video_player`); diğer her
  şey → media_kit (mpv). Runtime'da `/player` route'unda seçilir.
- Tek **universal APK** (arm64-v8a + armeabi-v7a + x86_64), release imzalı
  (`android/keystore/lifeostv-release.jks`).

---

## 🗂️ Alan bazlı özet

### 1) Çökme sınıfı (OOM / kararsızlık)
- **Görsel decode sınırlama (RC-A):** ~31 `CachedNetworkImage` çağrısına kutu-uygun
  `memCacheWidth` eklendi; `main.dart`'ta global image-cache TV'de düşürüldü
  (100 / 40MB). Aramadaki OOM çökmesi ve logo birikimi çökmeleri hedeflendi.
- **Seri detay OOM:** aktif sezonun TÜM bölümleri lazy-olmayan `Column`'da birden
  kuruluyordu → 30'luk pencere + "daha fazla göster" (`_kEpisodeWindow`).
- **`_selectSimilarContent` ANR:** her detay rebuild'inde tüm liste ana isolate'te
  tokenize ediliyordu → başlık başına memoize + aday cap (TV'de 400)
  (`_memoSimilarMovies` / `_memoSimilarSeries`).
- **Sistemik OOM:** TV'de ExoPlayer kullanıldığı halde `MediaKit.ensureInitialized()`
  libmpv+ffmpeg native kütüphanelerini boşuna yüklüyordu → **TV'de media_kit init
  atlanıyor** (main.dart, TV önce tespit edilip). `largeHeap="true"` zaten vardı.

### 2) Arama (donma + sonuçta çökme)
- **Sanal olmayan sonuç grid'i:** 3 shrinkWrap GridView 180 kartı birden kuruyordu
  → tek `CustomScrollView` + lazy `SliverGrid` (`_buildResultSlivers`).
- **Ana-isolate tarama:** `searchChannelsByType` tüm kataloğu çekip Dart'ta
  normalize/fuzzy yapıyordu → **kalıcı `channels.searchText` indeksi** (schemaVersion
  22→23, additive `addColumn`). Sorgu artık SQL'de `LIKE + LIMIT`; ıskalarsa sınırlı
  legacy tarama. `SearchNormalizer.buildHaystack()` indeks + sorguda ortak.
- **İndeks backfill:** `refreshSearchIndex()` NULL satırları chunk chunk,
  `Isolate.run` ile ana-isolate DIŞINDA doldurur; TV'de açılıştan 20s sonra + LAN
  sync sonrası, chunk arası 400ms nefes.
- **TV'de yaz-ara YOK:** arama artık **OK'a basınca** çalışıyor (`onSubmitted` →
  `_executeSearch`), yazarken rebuild/işlem sıfır. `textInputAction.search`.
- TV limitleri: sonuç 24/tür (60'tı), debounce 800ms, scan cap düşürüldü.

### 3) Poster grid & hero
- TV grid yoğunluğu: `PlatformHelper.gridColumns` TV'de ~135px poster hedefiyle
  **7-9 sütun** (5'ti).
- Grid ekranı hero'su TV'de **170px** (280'di).

### 4) D-pad focus yönetimi
- Canlı EPG'ye D-pad Sağ ile giriş (`onRightEdge` ×3 site).
- `TvIndexedListController`'a deferred-focus (yavaş yüklemede focus kaybı biter);
  `_focusContent` controller'a taşındı.
- Player kontrolleri gizlenince focus video yüzeyine döner (görünmez butonda kalmaz).
- Player overlay'lerinde ok-tuşu kapısı (EPG/kanal/altyazı arkasında hayalet
  seek/kanal biter) + EPG program listesi ve kanal-listesi arama alanı D-pad ile
  gezilebilir.
- Kategori sidebar reopen focus: `_focusSidebarItem` node'lar mount olana kadar
  ~4 frame retry eder (çıplak scope'a düşmez).
- Detayda benzer-rail kartları focuslanabilir yapıldı (`_FocusableSimilarCard`) →
  D-pad ile detay aşağı kayıyor + benzer öğeler seçilebiliyor.

### 5) Kategori sidebar
- Ana sidebar gibi **focus çıkınca kapanma** (collapse-on-blur, 3 ekran, TV-kapılı).
- Live TV'de kategori seçince kapanma (Movies/Series ile tutarlı, TV-kapılı).

### 6) Efektler (TV'de kaldırıldı — "kamyon gibi çalışıyor")
- `PlatformHelper.noAnimations / focusAnim / anim()` yardımcıları.
- TV'de anlık (Duration.zero) / gölgesiz: sidebar genişlik tween + öğeler, poster
  kartı + tüm gölgeler, grid focus glow, hero crossfade + butonlar + noktalar,
  player kontrol fade, kanal/EPG overlay slide, live-tv tile'ları, brand splash,
  AiSimilar kart + scale; detay poster blur-40 gölgesi.
- AI rail'leri (greeting/digest/personalized/mood) TV'de kapalı; detayda AI ✨
  ikonları gizli (`AiSimilarSection` TV'de düz fallback).

### 7) İlk açılış / sync
- Startup EPG sync TV'de 90s ertelendi (12s'ti); `syncAllLiveEpg`'deki N-sorgu
  döngüsü tek `COUNT(DISTINCT)` aggregate'e indirildi.

### 8) Player (ExoPlayer geçişi)
- **Android TV oynatıcısı ExoPlayer'a alındı** (`video_player`). Yeni ayrı ekran
  `tv_video_player_screen.dart` (media_kit ekranı dokunulmadı). Çekirdek oynatma +
  D-pad (OK oynat/duraklat, ←/→ 10sn seek VOD, ▲▼ kanal canlı) + devam-izleme kaydı
  + buffering/hata + wakelock. HLS/DASH/TS format ipuçları, VLC User-Agent, init
  timeout→hata.
- media_kit döneminden kalan (artık TV'de media_kit kullanılmıyor): mediacodec-copy,
  HW-accel toggle'ı TV'de çalışır hale getirme, 720p texture cap.

### 9) Cast (mobilden TV'ye ses gitmiyor)
- Stream-handoff casting; ses kodeği (AC-3/E-AC-3/DTS) Chromecast Default Media
  Receiver'da çözülemiyor → `CastState.loadError` + LOAD-hata tespiti + 8 dilde
  "format desteklenmiyor" SnackBar'ı. Tam çözüm (AAC transcode proxy) ayrı iş.

---

## 🧾 Commit geçmişi (Android TV)
| Commit | Özet |
|---|---|
| `ad58d28` | Kapsamlı ilk TV düzeltmeleri (focus, arama çökme/donma, perf, sidebar, cast) |
| `1bd8454` | VOD-detay çökme + arama donma; TV efektleri kaldırma; EPG ertele |
| `80dd480` | Kalıcı arama indeksi (`searchText`) + TV-lite detay/arama kapıları |
| `bccecee` | TV'de OK ile arama (yaz-ara kapatıldı) |
| `a7d47b6` | Player mediacodec-copy + kategori focus, yoğun grid, küçük hero |
| `c60660e` | Detay D-pad scroll + seçilebilir benzer, grid, 720p texture, AI ikon gizle |
| `d3dc8ad` | **Android TV için ExoPlayer** (video_player) — Aşama 1 |
| `9c71543` | Impeller kapat + TV'de media_kit init atla (sistemik) |
| `e37bcbf` | Impeller kapatmayı geri al (ExoPlayer video'yu bozdu) + init timeout→hata |

---

## 🔬 Öğrenilenler
- **Impeller (Flutter 3.27+ Android varsayılanı)** zayıf TV GPU'larında kararsızlık
  yapabiliyor; AMA kapatmak (Skia GL) bu Flutter sürümünde `video_player` texture
  render'ını bozdu → şimdilik AÇIK bırakıldı. Kesin karar için cihaz logu gerek.
- **media_kit** Android'de kareyi GL texture'a kopyalar (mpv shader zinciri) →
  zayıf TV'de takılma tavanı. ExoPlayer (MediaCodec→Surface) doğru yol.
- **ExoPlayer kodek/konteyner desteği mpv'den dar** — bazı VOD (ör. MKV+HEVC/AC3)
  mpv'de oynayıp ExoPlayer'da oynamayabilir. Teşhis için `adb logcat` şart.
- TV genelinde kararsızlıkta önce **renderer (Impeller)** ve **bellek (heap/native
  lib)**'e bak; widget-seviyesi semptomları sonra.

---

## ⏳ Bekleyen / sıradaki
- **Player teşhisi (öncelik):** TV'de ExoPlayer oynatma sorunu için `adb logcat`
  ile gerçek hata (ağ/kodek/render/OOM) alınıp noktasal düzeltme. Gerekirse VOD için
  media_kit'e geri + canlı için ExoPlayer (hibrit) veya native ExoPlayer+SurfaceView.
- ExoPlayer TV player **Aşama 2:** kanal listesi + EPG overlay + altyazı aç/kapa +
  cast (mevcut player-agnostik overlay'leri tekrar kullanarak).
- Cast tam ses: AAC transcode proxy.
- Flutter 3.44'e güncelleme (ayrı, test edilerek — Android bellek-sızıntısı
  düzeltmesi bonus).
- Gerçek cihazda `flutter run --profile` + DevTools ile kalan yavaşlıkların ölçümü.
