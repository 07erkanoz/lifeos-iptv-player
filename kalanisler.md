# Android TV Focus Refactor — Tamamlanan İşler

> **Durum:** Roadmap'teki tüm adımlar bitti (Adım 1-7 + Follow-up A-D).
> Ana refactor 222 testle korunuyor; her D-pad davranışı resolver +
> widget testleriyle CI'da regression korumalı. Bu doc tamamlanan
> işlerin envanteri ve ileride yeni TV ekranları eklerken referans
> noktası.

---

## Adım 1 — TvFocusRegistry (commit `13ab62f`)

`TvFocusZone` enum + `TvFocusRegistry` (sidebar callback slot, branch-
indexed primary map, overlay-priority slot) + Riverpod
`Provider<TvFocusRegistry>` + 9 unit test.

## Adım 2 — AppShell + AppSidebar registry bağlantısı (commit `ab728c7`)

Sidebar mount/dispose'da registry'ye `requestFocus` kaydı; right-arrow
artık `node.nextFocus()` yerine registry üzerinden branch primary'yi
çağırıyor. AppShell'in back handler'ı registry-aware.

## Adım 3 — TvPosterGridController + TvPosterGrid (commit `ca9fa18`)

Index-based D-pad nav, lazy-mount safe focusByStreamId (scroll →
post-frame retry → fallback first mounted), Scrollable.ensureVisible
on focus. 11 controller unit test + 13 widget test (gerçek D-pad
event'leri).

## Adım 4 — Movies (commit `37e81a3`)

`TvFocusRegistry.registerBranchPrimary(TvBranchIndex.movies, _focusGrid)`,
overlay push/pop for detail, `_PosterCardVisual` salt visual, full grid
+ category + sidebar focus flow. `findAncestorStateOfType` bütün
sayfadan silindi.

## Adım 5 — Series (commit `4e81079`)

Movies pattern'in birebir kopyası; series'e özgü "new episode" badge
`showNewBadge` ile geçiyor.

## Adım 6 — Live TV (commits `b520cac`, `25cab8c`, `0c1437c`)

- **6.1** `TvIndexedListController` + `TvIndexedList` widget + 23 test
  (commit `0a45a7f`)
- **6.2** `liveTvBackResolver` pure function + 10 test (commit `3d46503`)
- **6.3** LiveTvScreen back ladder + branch primary + `_epgFocusScope`
- **6.4** Channel list migration to `TvIndexedList<Channel>` (3
  callsite: All / Favorites / History) + external `scrollController`
  desteği
- **6.5** EPG row D-pad: leftmost program → channel list, up/down →
  komşu kanal, sağ → row içinde sonraki program (default), Enter →
  oynat

Live TV back ladder: EPG → channel list → categories → sidebar →
Dashboard → exit.

## Adım 7 — Dashboard + Search (commits `69a04ef`, `35bddb7`)

- **7.1** PosterCard `onLeftEdge`, ContentList `onCarouselLeftEdge`
  (index 0'a geçer), HeroBanner Play butonu `playFocusNode` + sol ok →
  ana sidebar
- **7.2** Search text-input ↔ grid bridge: `_textFocus.onKeyEvent`
  ile arrowDown intercept → `_firstResultFocus`, ilk non-empty section
  top row için `onTopEdge` → text input

## Subtitle Fixes (commits `17cff22`, `3926a60`, `5bb82e1`)

- Compact PiP trailer + expand-on-tap dialog (commit `17cff22`)
- Subtitle font controls + remember across episodes via
  `findBestSubtitleTrack` (ISO 639-1↔2 map + parenthetical strip +
  cross-field matching) + 14 unit test (commit `3926a60`)
- Settings'ten yapılan değişiklikler player'a anında yansısın
  (media_kit_video 2.0.1'in SubtitleViewState padding cache bug'ı
  için imperative `setSubtitleViewPadding`), controls'a göre subtitle
  yukarı kaysın, CC butonu API key yoksa gözükmesin (commit `5bb82e1`)

## Follow-up'lar

### A — Hover → focus parity (commit `3468e48`)

`PlatformHelper.useHoverEffects` tüm hover-driven widget'larda
gate edildi (PosterCard, _PosterCardVisual movies/series, HeroBanner,
sidebar, _SidebarItem). TV'de mouse-cursor-mode remote'ların focus
state ile yarışmasını engelliyor.

### B — Focus ring polish (commit `e24abf4`)

`PlatformHelper.focusRingWidth` (2px → 3.5px), `focusedScale` (1.08x →
1.12x), `focusRingGlowBlur` (14 → 24), `focusRingGlowAlpha` (0.30 →
0.55) — TV mode'da 3m mesafeden okunabilir focus ring.

### C — Settings branch primary (commit `6704dbe`)

`_firstNavFocus` + `registerBranchPrimary(TvBranchIndex.settings, ...)`.
Sidebar → Settings → right artık ilk nav item'a iniyor.
Branch-primary coverage tamam (5/5 branch).

### D — Trailer dialog 16:9 letterbox test (commit `b804c00`)

`computeExpandedTrailerSize(Size, {scale})` pure function olarak
çıkarıldı + 6 unit test (wide / square / portrait / ultra-wide / custom
scale / aspect-ratio invariant grab-bag). BackdropTrailer'ın
media_kit Player'ı test env'de mount olmadığı için tam dialog widget
test'i mümkün değil; en kırılgan kısım (sizing math) izole edildi.

---

## Test özeti

**222 test, hepsi yeşil.** Dağılım:
- `test/core/tv_focus/` → 80+ test (registry, controllers, widgets,
  resolvers)
- `test/data/services/subtitle_track_matcher_test.dart` → 14 test
- `test/presentation/widgets/layout/app_shell_back_resolver_test.dart`
  → 14 test
- `test/presentation/widgets/content/expanded_trailer_dialog_test.dart`
  → 6 test
- Eski testler (data/utils/domain) → ~80 test

---

## Mimari özet

**Branch-primary coverage (sidebar → right'tan hangi widget'a iniliyor):**

| Branch | Index | Primary target |
|---|---|---|
| Dashboard | 0 | Hero Play button |
| Live TV | 1 | Channel list (TvIndexedListController) |
| Movies | 2 | Grid (TvPosterGridController) |
| Series | 3 | Grid (TvPosterGridController) |
| Settings | 4 | First nav item |

**Back ladder semantiği (her ekranda):**

| Ekran | Back press |
|---|---|
| Movies/Series detay | Detay kapanır |
| Movies/Series grid | Kategori paneli |
| Movies/Series kategori | Ana sidebar (AppShell) |
| Live TV EPG | Kanal listesi |
| Live TV kanal listesi | Kategori paneli |
| Live TV kategori | Ana sidebar (AppShell) |
| Herhangi bir ekran içerik | Ana sidebar (AppShell) |
| Dashboard değil sidebar | Dashboard'a döner |
| Dashboard sidebar | Snackbar → 2sn içinde exit |

**Edge bridge'leri (D-pad sol/yukarı dış zone'a):**

| Konum | Sol ok | Yukarı ok |
|---|---|---|
| Movies/Series grid sol kenar | Kategori paneli | — |
| Dashboard carousel ilk poster | Ana sidebar | — |
| Dashboard hero Play | Ana sidebar | — |
| Search top-row | — | Text input |
| Live TV kanal listesi | Kategori paneli | (default) |
| Live TV EPG leftmost program | Kanal listesi (aynı kanal) | Komşu kanal |

---

## Açık potansiyel iyileştirmeler

Bunlar **acil değil** ama TV UX'i daha da iyileştirebilir:

1. **EPG zaman ekseni navigasyonu** — Şu an EPG'de left/right Flutter
   default traversal kullanıyor (siblings içinde spatial). Çalışıyor
   ama kompleks senaryolarda kayabilir. İleride: TvEpgRowController
   per-row with explicit prev/next index nav.
2. **PiP overlay focus restore** — Detail kapatıldığında PiP'nin
   GestureDetector'ı focus alıyor mu? Test edilebilir bir senaryo.
3. **Detail open + sidebar from elsewhere edge case** — Detail
   açıkken sidebar→right olursa overlay primary fire eder, doğru.
   Test ile pekiştirilebilir.
4. **Settings içindeki dropdown'lar / chip'ler** — Şu an default
   Flutter focus; TV-spesifik özelleştirme gerekmiyor ama isteğe
   bağlı.

---

_Bu doc Adım 7 + Follow-up D bitince güncellendi. Yeni TV ekranları
eklerken: registerBranchPrimary + back resolver + onLeftEdge/onTopEdge
patternlarını takip et; testleri pure function olarak çıkar._
