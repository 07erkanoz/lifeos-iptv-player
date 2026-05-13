# Android TV Focus Refactor — Kalan İşler

> **Durum:** Movies + Series ekranları, AppShell back ladder, TvFocusRegistry ve TvPosterGrid hazır. Tüm bu davranışlar pure-function resolver + widget testleriyle korunuyor (171 test). Aşağıdaki adımlar aynı disiplinle (resolver çıkar → unit test → entegre et → CI) ilerleyecek.

---

## Adım 6 — Live TV: TvIndexedListController + TvEpgGridController

Live TV iki ayrı navigation alanı içeriyor; tek bir grid controller'a sığmaz.

### 6.1 `TvIndexedListController` (kanal listesi — dikey, tek sütun)

**Konum:** `lib/core/tv_focus/tv_indexed_list_controller.dart`

**Sorumluluklar:**
- `Map<int channelId, FocusNode>` ve ordered `List<int>` tutar.
- API:
  - `focusFirst() / focusByChannelId(int) / focusCurrentOrFirst()`
  - `focusIndex(int)` — index→pixel approx scroll + post-frame retry (mevcut TvPosterGridController paterni)
- D-pad math: yalnız up/down. Left/right handler'ları parent'a callback olarak gider (sol→category sidebar, sağ→EPG timeline).

**Test (`test/core/tv_focus/tv_indexed_list_controller_test.dart`):**
- Empty state — focusFirst false döner
- registerItem/unregisterItem identity-checked
- focusByChannelId mounted → senkron, unmounted → async retry path
- lastFocusedChannelId tracking

### 6.2 `TvEpgGridController` (program timeline — iki boyutlu virtualized)

**Konum:** `lib/core/tv_focus/tv_epg_grid_controller.dart`

**Sorumluluklar:**
- Programlar `(channelIndex, programIndex)` tuple ile addresslenir, single streamId değil — bir kanalın o anki/sıradaki programları farklı tuple'lar.
- D-pad semantiği farklı:
  - **Sol/sağ:** AYNI kanalda önceki/sonraki program (zaman ekseni)
  - **Yukarı/aşağı:** AYNI zaman aralığında üst/alt kanalın programı (kanal ekseni)
  - **Sol kenar (zaman ekseni başı):** parent'a callback — focus channel list'e dönsün
  - **Enter:** Şu anki program ise kanalı oynat; gelecekteki program ise hatırlatıcı/info
- Programlar virtualized: viewport dışında olanlar mounted değil. `focusByTuple(c, p)` lazy-mount safe.

**Test:**
- (c=0, p=0) → arrowRight → (c=0, p=1)
- (c=0, p=5) → arrowDown → (c=1, p=5) — aynı zaman aralığında üst kanal
- (c=N, p=0) → arrowLeft → onChannelListLeftEdge callback
- Boundary conditions: son program, ilk kanal, partial rows

### 6.3 LiveTvScreen entegrasyonu

**Mevcut sorunlar** (Explore raporundan):
- [live_tv_screen.dart:1174](lib/presentation/screens/live/live_tv_screen.dart) channel list parent focus alıyor, item'lar explicit index node ile yönetilmiyor.
- EPG programları focusable ama [live_tv_screen.dart:2390](lib/presentation/screens/live/live_tv_screen.dart) sadece OK/Enter yakalıyor; sağ/sol/yukarı/aşağı semantik yok.

**Refactor:**
1. `_channelListFocusNode` (parent focus) — kaldır. Yerine `_channelListController = TvIndexedListController()`.
2. Channel list `ListView.builder` → her item `_TvIndexedListItem` (controller-managed FocusNode, D-pad up/down handle, left → category panel, right → EPG focus).
3. EPG grid → `TvEpgGrid` widget (yeni). 2D scroll + per-cell Focus widget.
4. `TvFocusRegistry.registerBranchPrimary(TvBranchIndex.liveTv, _focusChannelList)`.
5. Back ladder: `liveTvBackResolver` (yeni pure function) → EPG → channelList → categories → sidebar → Dashboard.

### Acceptance kriterleri

- TV remote D-pad ile:
  - Kanal listesinden sağ ok → EPG'de o kanalın o anki programına
  - EPG'de yukarı/aşağı → komşu kanalın aynı zaman aralığındaki programına
  - EPG'de sol ok (zaman ekseninin başında) → kanal listesine geri
  - Back → semantik tek seviye out (EPG → kanal listesi → kategori → sidebar → Dashboard)
- `flutter test`'ten geçen >=15 yeni test (channel list ~5, epg grid ~8, back resolver ~4).

---

## Adım 7 — Search + Dashboard horizontal carousel focus

### 7.1 Dashboard: carousel'lerden sol ok → ana sidebar

**Mevcut sorun:**
- Dashboard'da `ContentList` widget'ları yan yana posterler içeriyor. Posterler `PosterCard` (kendi Focus widget'ı) ama sol kenarda hiçbir handler yok.
- Şu an sadece **back tuşu** sidebar'a geçişi sağlıyor (AppShell ladder sayesinde). Bu yeterli ama daha doğal olan **D-pad sol ok**'un da çalışması.

**Refactor:**
1. `PosterCard`'a opsiyonel `onLeftEdge: VoidCallback?` param.
2. `ContentList`'e `onCarouselLeftEdge: VoidCallback?` param — ListView'in `index == 0` poster'ı için handler'ı bubble eder.
3. `HeroBanner`'a aynı kapı (currently focused hero item için sol ok handler).
4. `DashboardScreen` her ContentList ve HeroBanner için `onLeftEdge: _focusMainSidebar` geçirir. `_focusMainSidebar` = `registry.requestMainSidebar()` (mevcut registry kullanarak).
5. `registry.registerBranchPrimary(TvBranchIndex.dashboard, _focusFirstCarousel)` — sidebar sağ ok'tan Dashboard'a girince hero'ya değil ilk carousel'in ilk item'ına gitsin (veya hero'ya, UX kararı).

**Test (`test/core/tv_focus/dashboard_back_resolver_test.dart`?):**
- Dashboard'un back ladder'ı çoğunlukla AppShell'in genel ladder'ından farklı değil. Belki dashboard-spesifik resolver gerekmez. Asıl test ContentList'in left-edge davranışı için widget test.

### 7.2 Search screen

**Mevcut sorun:**
- [search/search_screen.dart](lib/presentation/screens/search/search_screen.dart) basit: TextField + grid result.
- `_textFocus` ve `_gridFocus` ayrı, ama aralarındaki D-pad geçişi şekilsiz.

**Refactor:**
1. Result grid'i `TvPosterGrid<Channel>` kullanacak şekilde refactor (Movies'le aynı path).
2. `_textFocus`'tan arrowDown → grid focusFirst.
3. Grid'in topEdge handler → `_textFocus.requestFocus()`.
4. Branch primary olarak `_textFocus.requestFocus()` — Search Dashboard'dan farklı olarak sidebar'dan girince input'a focus alsın.

### Acceptance kriterleri

- Dashboard: carousel'in ilk poster'ında sol ok → ana sidebar focus alır
- Dashboard: hero banner'ın current item'ında sol ok → ana sidebar
- Search: text input'tan aşağı → grid first poster
- Search: grid first row'dan yukarı → text input
- Yeni test: ContentList widget test, Search bridge widget test

---

## Mimari follow-up'lar (önemli ama bağımsız)

### A. Hover → focus parity (TV mode)

**Sorun:** `PlatformHelper.useDpadNavigation` flag'i tanımlı ama hiçbir yerde kullanılmıyor. TV'de hover state aktif olmamalı — yalnız focus state.

**Plan:**
- `PlatformHelper.useHoverEffects = !isTV` getter ekle.
- `PosterCard`, `_PosterCardVisual` (movies/series), `ContentList` içindeki `MouseRegion`'ları bu flag'le sar.
- TV mode'da `MouseRegion(cursor: SystemMouseCursors.none, onEnter: useHoverEffects ? ... : null)`.

### B. Focus ring polish

**Sorun:** Posterlerde 2px primary border yetersiz olabilir; 3m'den okumakta zorlanılır.

**Plan:**
- TV mode'da border genişliği 3px + outer glow shadow ekle.
- Hover ring'i shape için aynı stile uydur (TV/desktop ayrımı).

### C. Settings ekranı

**Sorun:** Settings sekmesinin focus chain'i hiç yok. Sidebar'dan girince ilk item focus almıyor.

**Plan:**
- SettingsScreen'e basit: `registry.registerBranchPrimary(TvBranchIndex.settings, () => _firstItemFocusNode.requestFocus())`.

### D. Detay sayfasında çift dialog

**Şu anda:** Movies/Series detail'inde "Fragmanı Büyüt" dialog'u kapanınca detail'in play butonuna focus dönüyor. Test ediyor olmalıyız — `expandedTrailerDialog`'un focus'u geri verdiğine dair widget test yok.

**Plan:**
- `expanded_trailer_dialog_test.dart` widget test: dialog aç, kapat, focus play butonunda mı kontrol et.

---

## Test stratejisi (tüm adımlar için)

Her yeni adımda **iki katman** test:

1. **Pure resolver** (eğer ladder/decision logic varsa) — `lib/core/tv_focus/*_resolver.dart` + `test/core/tv_focus/*_resolver_test.dart`. Hızlı, side-effect-free, edge case'ler kapsar.

2. **Widget test** (gerçek davranış) — `test/core/tv_focus/*_widget_test.dart`. `WidgetTester.sendKeyEvent` ile gerçek D-pad event'ları, `_focusedItemId()` helper (debugLabel parsing) ile focus konumu assertion.

CI hedefi: her commit'te tüm tv_focus testleri yeşil. Bir test kırıldığında bug TV'ye ulaşmadan yakalanır.

---

## Tahmin

| Adım | LOC | Test sayısı | Süre |
|---|---|---|---|
| 6.1 TvIndexedListController | ~200 | 8-10 | 1-2 sa |
| 6.2 TvEpgGridController | ~300 | 12-15 | 2-3 sa |
| 6.3 LiveTvScreen entegrasyon | ~400 değişiklik | resolver: 5-7 | 2-3 sa |
| 7.1 Dashboard left-edge | ~150 | widget test: 4-5 | 1 sa |
| 7.2 Search refactor | ~200 | 5-6 | 1 sa |
| A. Hover gating | ~50 (dağınık) | — | 30 dk |
| B. Focus ring | ~30 | — | 20 dk |
| C. Settings focus | ~30 | 1 | 20 dk |
| D. Trailer dialog test | ~80 | 2-3 | 30 dk |
| **Toplam** | **~1450** | **~45 yeni test** | **9-12 sa** |

---

## Önemli notlar

- **Architecture invariant:** Her ekran kendi back ladder'ını AppShell'den **bağımsız** çözer, AppShell yalnız "screen claim etmediyse" devreye girer. Bu, Movies/Series için zaten korunuyor (`GridScreenBackAction.handToShell` enum'ı). Live TV ve Search aynı pattern'ı izlemeli.
- **Registry priority:** `overlayPrimary > branchPrimary > sidebar focus`. Detail açıkken sidebar sağ ok'u detail'e gitmeli, grid'e değil. Bu mevcut testlerle kapsanıyor.
- **CRLF gürültüsü:** Bu repo'da bazı dosyalar CRLF satır sonu kullanıyor (Windows'tan). `git status` modified gösterir ama gerçek değişiklik yok. Commit'lerken sadece elle eklediğin dosyaları stage et, `git add .` kullanma.
- **Test koşumu:** `flutter test test/core/tv_focus/` — sadece TV focus subset. Tam koşu: `flutter test` (~3 sa hızında, 171 test).

---

_Bu doc Adım 5 sonunda yazıldı. Adım 6+ başlamadan önce: önce Movies'te TV'de Back testi → kategori paneline gidiyor mu, ana sidebar mı, exit dance mı? Eğer beklenmedik davranış varsa AppShell veya GridScreen resolver'a düzeltme — düzeltme test'le ekle._
