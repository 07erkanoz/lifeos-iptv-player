# LifeOs TV - Detailed Product & Usage Guide (EN + TR)

## English

## 1) Product summary
LifeOs TV is a cross-platform IPTV player for users who already have their own provider access.
It supports both Xtream Codes and M3U playlists, and organizes content into Live TV, Movies, and Series with a TV-style experience.

Important:
- LifeOs TV is a player application.
- LifeOs TV does not host channels, does not sell subscriptions, and does not provide built-in media catalogs.

## 2) Who this app is for
- Users who want one modern interface for Live TV + VOD (movie/series).
- Users who want faster daily usage with favorites, continue watching, and rich detail screens.
- Desktop users who need keyboard/remote-friendly playback controls.

## 3) Account and onboarding
Supported account types:
- Xtream Codes: server URL + username + password.
- M3U playlist: URL/file-based source.

First run flow:
1. Add account.
2. Initial sync starts (categories, channels, VOD metadata).
3. Dashboard opens with personalized rows.

Sync behavior:
- Local database cache is used for fast opening.
- Background refresh updates categories/channels/metadata.
- EPG uses provider data first; XMLTV fallback is supported when needed.

## 4) Screen-by-screen features

### Dashboard
- Hero banner for highlighted content.
- Favorites row.
- Continue Watching row.
- Recently added Movies / Series / Live rows.
- Quick play, details, trailer actions from hero.

### Live TV
- Category navigation.
- Favorite Channels category.
- Watch History category.
- EPG timeline and current/next program context.
- Live playback with quick channel switching.

### Movies
- Category browsing.
- Detail page with poster, plot, cast/director/genre/year when available.
- Continue from saved position.
- Trailer (YouTube) and IMDb shortcuts when metadata exists.
- Similar content row.

### Series
- Category browsing.
- Detail page with season tabs and episode list.
- Continue from last watched episode.
- Trailer (when available) and IMDb shortcut.
- Similar series row.

### Search
- Global search across movie + series + live in parallel.
- Debounced search for large libraries.
- Opens detail/playback flow directly from results.

### Settings
- Account management.
- Player tuning (HW acceleration, stream quality, buffer, continue watching).
- Subtitle settings (OpenSubtitles API key, preferred language, appearance).
- Language selection.
- Adult content filter.
- Cache/data cleanup.

## 5) Player capabilities
Core playback:
- Unified player for Live TV, Movies, and Series.
- Resume progress for VOD.
- Continue watching tracking.
- Fullscreen mode.
- In-app desktop PiP/floating mode (platform/window-manager behavior may vary).
- Android native PiP integration.

Live-specific playback:
- Channel up/down behavior.
- Channel list overlay with category and search.
- EPG overlay with current/next program info.

Audio/subtitle/playback tools:
- Audio track picker.
- Subtitle track picker.
- OpenSubtitles search overlay for VOD.
- Playback speed options.
- Volume/mute controls.

Casting:
- Chromecast button on supported mobile flows.

## 6) Keyboard / remote controls (desktop)
- `ESC` / Back: closes overlays first, then exits fullscreen, then PiP/exit flow.
- `Space` / media play-pause: play/pause.
- `Left` / `Right`: seek -10s / +10s.
- `Up` / `Down`: channel up/down on live (or volume/control focus behavior).
- `M`: mute toggle.
- `C`: toggle live channel list overlay.
- `G`: toggle EPG overlay.
- `F`: fullscreen toggle.
- `Enter` / `Select`: reveals controls when hidden.

## 7) Personalization and recommendation logic
LifeOs TV builds "Similar" rows with a weighted score model.

Primary similarity signals:
- Same category.
- Genre token overlap.
- Director overlap.
- Cast token overlap.
- Same year.
- Rating contribution.

Personalization boost:
- User favorites and continue-watching items are used as preference seed.
- Genre/director/cast overlap with that seed increases recommendation score.

Fallback behavior:
- If score data is weak/missing, the app falls back to other available items.

## 8) Performance model
- Uses local DB caching for fast first paint.
- Heavy operations are backgrounded where possible (sync/search/update).
- Search uses debouncing and per-type parallel queries.
- EPG is read from cache first, then refreshed in background.

## 9) Limitations and expectations
- Metadata quality depends on provider data.
- Trailer links may be unavailable for some items.
- EPG completeness depends on provider/XMLTV quality.
- PiP/fullscreen behavior can differ by OS/window manager.

## 10) Flathub listing copy (ready to use)

### Short description (EN)
Modern IPTV player for Xtream Codes and M3U playlists with Live TV, EPG, Movies, Series, favorites, and continue watching.

### Long description (EN)
LifeOs TV is a cross-platform IPTV player that helps you watch your own provider content in a unified interface.

Main features:
- Xtream Codes and M3U playlist support.
- Live TV with EPG overlays and channel list search.
- Movie and series browsing with rich detail pages.
- Season/episode navigation for series.
- Favorites, watch history, and continue watching.
- Similar content recommendations based on metadata and user behavior.
- Subtitle tools including OpenSubtitles search integration.
- Desktop-friendly keyboard/remote controls and fullscreen/PiP playback.

Legal note:
LifeOs TV does not provide or host media content. Users are responsible for their IPTV sources and legal compliance.

---

## Türkçe

## 1) Ürün özeti
LifeOs TV, kendi IPTV sağlayıcı erişimine sahip kullanıcılar için geliştirilmiş çok platformlu bir IPTV oynatıcıdır.
Hem Xtream Codes hem M3U listelerini destekler; içerikleri Canlı TV, Film ve Dizi olarak TV benzeri bir deneyimde sunar.

Önemli not:
- LifeOs TV bir oynatıcı uygulamasıdır.
- LifeOs TV kanal/abonelik satmaz, içerik barındırmaz, hazır katalog sunmaz.

## 2) Hangi kullanıcılar için uygun?
- Canlı TV + VOD (film/dizi) için tek uygulama isteyen kullanıcılar.
- Favoriler, izlemeye devam et ve detay ekranlarıyla hızlı kullanım isteyen kullanıcılar.
- Klavye/kumanda odaklı masaüstü oynatma deneyimi arayan kullanıcılar.

## 3) Hesap ve ilk kurulum
Desteklenen hesap tipleri:
- Xtream Codes: sunucu URL + kullanıcı adı + şifre.
- M3U playlist: URL/dosya tabanlı kaynak.

İlk kullanım akışı:
1. Hesap eklenir.
2. İlk senkron başlar (kategori, kanal, VOD metadata).
3. Dashboard kişiselleştirilmiş satırlarla açılır.

Senkron davranışı:
- Hızlı açılış için yerel veritabanı önbelleği kullanılır.
- Arka planda kategori/kanal/metadata güncellenir.
- EPG önce sağlayıcı verisinden denenir; gerektiğinde XMLTV fallback kullanılır.

## 4) Ekranlara göre özellikler

### Dashboard
- Öne çıkan içerik hero alanı.
- Favoriler satırı.
- İzlemeye Devam Et satırı.
- Son eklenen Film / Dizi / Canlı TV satırları.
- Hero alanından hızlı oynat, detay, fragman aksiyonları.

### Canlı TV
- Kategori gezintisi.
- Favori Kanallar kategorisi.
- İzleme Geçmişi kategorisi.
- EPG zaman çizelgesi ve mevcut/sıradaki program bilgisi.
- Hızlı kanal geçişi ile canlı oynatma.

### Filmler
- Kategori bazlı gezinti.
- Poster, özet, oyuncu/yönetmen/tür/yıl gibi alanları içeren detay ekranı (veri varsa).
- Kaldığın yerden devam et.
- Metadata varsa YouTube fragman ve IMDb kısayolları.
- Benzer içerikler satırı.

### Diziler
- Kategori bazlı gezinti.
- Sezon sekmeleri ve bölüm listesi bulunan detay ekranı.
- Son izlenen bölümden devam et.
- Veri varsa fragman ve IMDb kısayolu.
- Benzer diziler satırı.

### Arama
- Film + Dizi + Canlı içeriklerde paralel global arama.
- Büyük kütüphaneler için debounce destekli arama.
- Sonuçtan direkt detay/oynatma akışına geçiş.

### Ayarlar
- Hesap yönetimi.
- Oynatıcı ayarları (donanım hızlandırma, kalite, buffer, izlemeye devam et).
- Altyazı ayarları (OpenSubtitles API key, öncelikli dil, görünüm).
- Dil seçimi.
- Yetişkin içerik filtresi.
- Önbellek/veri temizleme.

## 5) Oynatıcı yetenekleri
Temel oynatma:
- Canlı TV, Film ve Dizi için birleşik player.
- VOD içerikte kaldığın yerden devam.
- İzlemeye devam et takibi.
- Tam ekran modu.
- Masaüstünde uygulama içi PiP/floating akışı (platform/pencere yöneticisine göre değişebilir).
- Android tarafında native PiP entegrasyonu.

Canlı yayın özel:
- Kanal yukarı/aşağı geçiş.
- Kategori ve arama destekli kanal listesi overlay.
- Mevcut/sıradaki programı gösteren EPG overlay.

Ses/altyazı/oynatım araçları:
- Ses parçası seçici.
- Altyazı parçası seçici.
- VOD için OpenSubtitles arama katmanı.
- Oynatma hızı seçenekleri.
- Ses seviyesi/sessize alma kontrolleri.

Cast:
- Destekli mobil akışlarda Chromecast butonu.

## 6) Klavye / kumanda kısayolları (masaüstü)
- `ESC` / Geri: önce overlay kapatır, sonra tam ekrandan çıkar, sonra PiP/çıkış akışını uygular.
- `Space` / play-pause tuşu: oynat/duraklat.
- `Sol` / `Sağ`: -10 sn / +10 sn sarma.
- `Yukarı` / `Aşağı`: canlıda kanal geçişi (veya ses/kontrol odağı davranışı).
- `M`: sessize al/aç.
- `C`: canlı kanal listesi overlay aç/kapat.
- `G`: EPG overlay aç/kapat.
- `F`: tam ekran aç/kapat.
- `Enter` / `Select`: kontroller gizliyse görünür yapar.

## 7) Kişiselleştirme ve benzer içerik mantığı
LifeOs TV, "Benzer" satırlarında ağırlıklı puanlama modeli kullanır.

Ana benzerlik sinyalleri:
- Aynı kategori.
- Tür (genre) kesişimi.
- Yönetmen kesişimi.
- Oyuncu (cast) kesişimi.
- Aynı yıl.
- Puan (rating) katkısı.

Kişiselleştirme artırımı:
- Favoriler ve izlemeye devam et öğeleri tercih tohumu (seed) olarak kullanılır.
- Bu tohumla örtüşen tür/yönetmen/oyuncu adaylara ek puan verir.

Fallback davranışı:
- Puanlama yetersizse sistem diğer uygun içeriklerden liste üretir.

## 8) Performans yaklaşımı
- Hızlı açılış için yerel veritabanı cache kullanır.
- Ağır işlemler mümkün olduğunca arka planda yapılır (sync/search/update).
- Arama, debounce ve tip bazlı paralel sorgu ile çalışır.
- EPG önce cache’den okunur, sonra arka planda yenilenir.

## 9) Sınırlar ve beklentiler
- Metadata kalitesi sağlayıcı verisine bağlıdır.
- Bazı içeriklerde fragman linki bulunmayabilir.
- EPG doluluğu sağlayıcı/XMLTV kalitesine bağlıdır.
- PiP/tam ekran davranışı işletim sistemi ve pencere yöneticisine göre değişebilir.

## 10) Flathub mağaza metni (hazır)

### Kısa açıklama (TR)
Xtream Codes ve M3U listelerini destekleyen; Canlı TV, EPG, Film, Dizi, favoriler ve izlemeye devam özellikleri sunan modern IPTV oynatıcı.

### Uzun açıklama (TR)
LifeOs TV, kendi sağlayıcı içeriğinizi tek bir arayüzde izlemenizi sağlayan çok platformlu bir IPTV oynatıcıdır.

Öne çıkan özellikler:
- Xtream Codes ve M3U playlist desteği.
- EPG overlay ve kanal araması ile Canlı TV deneyimi.
- Zengin detay ekranlarıyla film/dizi gezintisi.
- Dizilerde sezon/bölüm navigasyonu.
- Favoriler, izleme geçmişi ve izlemeye devam et.
- Metadata + kullanıcı davranışına dayalı benzer içerik önerileri.
- OpenSubtitles arama entegrasyonu dahil altyazı araçları.
- Masaüstüne uygun klavye/kumanda kontrolleri ve tam ekran/PiP oynatma.

Yasal not:
LifeOs TV içerik sağlamaz veya barındırmaz. Kullanıcı, kullandığı IPTV kaynaklarının yasallığından sorumludur.
