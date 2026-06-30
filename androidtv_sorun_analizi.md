# 📺 Android TV — Kapsamlı Sorun Analizi

> ## ✅ UYGULAMA DURUMU (2026-06-30)
> Aşağıdaki düzeltmelerin tamamı uygulandı; **`flutter analyze` 0 hata**, **223 test geçti**.
> - **RC-A** görsel decode: 31 `CachedNetworkImage`'a `memCacheWidth` + TV image-cache bütçesi (`main.dart`)
> - **Arama**: S-1 (poster decode), S-2 (`searchChannelsByType` ORDER BY+LIMIT 6000), S-4 (spinner titremesi)
> - **RC-B**: player overlay ok-tuşu kapısı + EPG (F-2) ve kanal-listesi (F-3) overlay'leri D-pad ile gezilebilir
> - **Perf**: P-2 (TV'de idle gölge yok), P-3 (TV'de scale snap — PosterCard+grid), P-4 (hero crossfade+decode), F-8 (hero focus'ta auto-slide duraklat)
> - **D-pad focus**: F-1 (EPG onRightEdge ×3), F-4 (deferred-focus controller + `_focusContent`), F-6 (player auto-hide focus dönüşü)
> - **Kategori sidebar**: C-1 (collapse-on-blur ×3 ekran) + C-2 (Live select-collapse) — hepsi `isTV`-kapılı
> - **Boşluklar**: GAP-1 (Ayarlar nav→içerik köprüsü), GAP-2 (player Slider TV traversal'dan çıkarıldı), GAP-3 (AI rail'leri TV'de kapalı)
> - **Cast**: LOAD-hata tespiti + 8 dilde "format desteklenmiyor" SnackBar'ı (`CastState.loadError`)
>
> **Ertelenenler (gerekçeli):**
> - **Cast tam ses çözümü** → AC-3/E-AC-3/DTS'yi AAC'ye çeviren yerel transcode proxy (FFmpeg) ayrı/büyük bir özellik. Şu an kullanıcı sessiz video yerine açıklayıcı mesaj alıyor.
> - **F-5** dashboard rail focus controller → tüm platformlarda paylaşılan PosterCard'ı etkilediği ve çökme/donma olmadığı (sadece determinizm) için regresyon riskine karşı ertelendi.
> - **S-3** enrichment SQL-join → düşük öncelik, schema migration gerektirir.
> - Kalan 5 `flutter analyze` uyarısı (dashboard duplicate import, kullanılmayan private parametre) **önceden mevcut**, bu çalışmayla ilgisiz.

---


> Çok-ajanlı derin inceleme (33 ajan, çapraz-doğrulamalı). Her bulgu bağımsız bir
> "çürütücü" ajan tarafından gerçek kod okunarak doğrulandı. Bulgular: 13 tam
> doğrulandı, 11 kısmen (genelde şiddet/çerçeve düzeltmesiyle), **0 çürütüldü**.
> Tarih: 2026-06-30. HEAD: `a5c1309`.

İncelenen 5 alan:
1. D-pad focus yönetimi
2. Aramada çökme & donma
3. Poster/animasyon performansı
4. Kategori sidebar'ın kapanmaması
5. Mobilden TV'ye cast'te ses gitmemesi

---

## 🔴 0. ÇAPRAZ-KESEN İKİ KÖK NEDEN (önce bunlar)

Birçok ayrı şikayet aslında **iki** temel hatadan kaynaklanıyor. Bunları tek
noktadan düzeltmek, çok sayıda semptomu aynı anda kapatır.

### RC-A — Görsel decode'u sınırlanmamış + global image cache TV'de küçültülmemiş (ÇÖKME sınıfı)
- `lib/main.dart:58-60`: `imageCache..maximumSize=150 ..maximumSizeBytes=60MB`
  **tüm platformlar için aynı** — `isTV` dalı yok. Zayıf bir Android TV'de (çoğu
  zaman 1–1.5 GB uygulama heap'i) bu agresif.
- Kod tabanında **~30 `CachedNetworkImage`** çağrısı var; `memCacheWidth` yalnızca
  grid posterlerinde mevcut (`poster_card.dart:243`, `movies_screen.dart:2455`,
  `series_screen.dart:3995` = `320`). Geri kalanı kaynağı **tam çözünürlükte**
  decode ediyor → heap şişiyor → OOM çökme.
- TV'de hâlâ tam-res decode eden, denetlenen örnekler:
  `live_tv_screen.dart:1996` (kanal logosu), `movies_screen.dart:1033` &
  `series_screen.dart:1803` (detay posteri).
- Denetlenmeyen ama TV'de render olan ek örnekler (kritik kuyruk):
  `video_player_screen.dart:3319/3508/4046`, `epg_overlay.dart:224`,
  `channel_list_overlay.dart:500`, `live_now_on_air_rail.dart:213`,
  `personalized_picks_rail.dart:282`, `mood_selector.dart:363`,
  `program_guide.dart:37`, ve `movies_screen.dart:738/884/971/1336/1879`,
  `series_screen.dart:1355/1590/1697/2788/2895`.

**Düzeltme:** Her `CachedNetworkImage`'a render kutusuna göre `memCacheWidth`
ekle (veya ortak bir sarmalayıcı widget yap) **ve** `main.dart:58-60`'taki cache
bütçesini `isTV`'de düşür. Tek mekanik değişiklik, en yüksek kaldıraç.

### RC-B — Player overlay'lerinde ok tuşu sızıntısı (üst seviye kök neden)
- `video_player_screen.dart` `_handleKey (1626-1764)` yalnızca **Back/Escape**'i
  overlay durumuna göre kapatıyor; **ok tuşları için** `if (_showChannelList ||
  _showEpgGuide || _showSubtitleSearch) return handled` **kapısı yok**.
- Sonuç: herhangi bir overlay ok tuşunu `ignored` döndürünce, oklar overlay'in
  arkasındaki **seek (1695-1701) / ses / kanal değiştirme (1703-1726)** koduna
  düşüyor. Yani EPG açıkken D-pad yukarı/aşağı arkadaki kanalı değiştiriyor.
- Bu, ayrı sanılan 3 bulgunun (EPG overlay, kanal listesi overlay,
  **+ denetlenmeyen** `subtitle_search_overlay.dart`) tek ortak nedeni.

**Düzeltme:** Tek noktada ebeveynde okları herhangi-bir-overlay-açıkken yut +
her overlay listesini gerçekten odaklanabilir yap (aşağıda focus-2/3'e bak).

---

## 🟥 1. ARAMA — Çökme & Donma  (EN YÜKSEK ÖNCELİK)

### S-1 [KRİTİK] Arama sonuçları 180+ posteri `memCacheWidth` olmadan, sanal-olmayan grid'de render ediyor → TV heap'inde OOM çökme
- `_SearchResultCard` posteri tam-res decode ediyor: `search_screen.dart:1026`
  `CachedNetworkImage(... )` — **`memCacheWidth` yok** (standart 320 her yerde var,
  burada yok — `a5c1309`'un grid için çözdüğü çökmenin aynısı, arama atlanmış).
- Sonuçlar tembel değil, **hepsi birden** kuruluyor: `search_screen.dart:828`
  `ListView` içinde `shrinkWrap:true` + `NeverScrollableScrollPhysics`
  (`:590-591`) grid'ler → her tür için 60 = **180 kart** (`:218-220`) anında
  decode. AI yolunda `searchChannelsByIntent(limit:200)` (`:321`) ile daha da
  fazlası.
- **Düzeltme:** (a) `search_screen.dart:1026`'ya `memCacheWidth:320` (tek satır,
  risksiz, koşulsuz); (b) sonuçları tek bir kaydırılabilir `CustomScrollView`/
  `SliverGrid`'e çevir ki yalnızca ekrandaki posterler decode olsun — **ama** TV
  focus köprülerini koru (`_firstResultFocus`, `onTopEdge`, `:582-614`); (c) ucuz
  ara çözüm: tür başına limiti TV'de 60→24.

### S-2 [KRİTİK] `searchChannelsByType` tüm kataloğu SQL LIMIT'siz çekip ana isolate'te senkron filtreliyor → saniyelerce donma (ANR)
- `content_repository.dart:595-605`: sorgu `type`+gizli+yetişkin filtreleriyle
  ama **`.limit()` yok**; `limit` parametresi yalnızca materialize'den **sonra**
  listeyi kırpıyor. (`a5c1309` grid'lere paging ekledi, aramayı bilinçli olarak
  "unbounded" bıraktı.)
- Her satır için `_buildHaystack` (7 alan birleştir) + `SearchNormalizer.normalise`
  (karakter-karakter `split('')` döngüsü, `search_normalizer.dart:74-80`); strict
  pas boş dönerse **O(satır×kelime×uzunluk) Levenshtein fuzzy** pası
  (`content_repository.dart:630-637`). Üç tür (film/dizi/canlı) **paralel** çalışıyor
  (`search_screen.dart:217-221`).
- ⚠️ Doğrulama düzeltmesi: SQL `.get()` aslında drift_flutter'ın **arka plan
  isolate**'inde koşuyor (UI'yı kilitleyen o değil). Donmanın gerçek kaynağı:
  sınırsız satır sayısının **ana isolate'teki Dart son-işleme**'ye (haystack +
  fuzzy) beslenmesi. En kötü durum: yazım hatalı / sonuçsuz sorgu (fuzzy pas).
- **Düzeltme (sıralı):** (a) `searchChannelsByType`'a `ORDER BY rating DESC` +
  cömert `.limit()` (örn. 5000) — **çıplak LIMIT'i sırasız koyma**, eşleşme
  kaybettirir; (b) en sağlam: eşleşmeyi SQL'e taşı (sync zamanında önceden
  normalize edilmiş arama kolonu / FTS5 — schema migration gerekir, şu an v22);
  (c) fuzzy pası bir aday-üst sınırının arkasına al; (d) haystack/fuzzy işini
  `compute()`/Isolate'e taşı.

### S-3 [düşük→orta] Her aramada tüm enrichment tablosu taranıyor (ikincil maliyet)
- `content_repository.dart:613` `_loadEnrichmentMap()` tüm `content_enrichment`'ı
  SELECT edip map kuruyor; 20s TTL-cache'li (`:1190-1203`) → bir arama
  patlamasında yalnızca ilk çağrı öder.
- ⚠️ Düzeltme uyarısı: "TV'de enrichment boş, atla" **YANLIŞ** olur — enrichment
  satırları LAN-sync ile telefondan TV'ye geliyor (`lan_sync_service.dart:503,
  916-926`), tür/yıl aramaları ("korku") buna bağlı. **Doğru düzeltme:**
  enrichment'i SQL join'e kat (grid'lerin `18c6e1d`'de yaptığı gibi), `isTV`'de
  atlama.

### S-4 [düşük] Spinner her tuşta titriyor + süpersedlenen sorgu yine de tam donmayı koşuyor
- `search_screen.dart:205` her tuşta senkron `_isSearching=true` → tam-ekran
  spinner mevcut grid'i siliyor; TV'de tuşlar arası 400ms+ olduğu için
  spinner→sonuç→spinner döngüsü görünür. `requestId` kontrolü (`:222`) ağır işten
  **sonra** olduğu için süpersedlenen sorgu yine de donmayı tamamlıyor.
- (Not: iddia edilen "loading state desync" yok — `_debounce?.cancel()` tek timer
  garanti ediyor.)
- **Düzeltme:** S-2 düzeldiğinde büyük ölçüde çözülür; ayrıca sonuç ekrandayken
  tam-ekran spinner gösterme (önceki grid'i koru), ve repo döngüsüne requestId
  iptal kontrolü ekle.

---

## 🟧 2. POSTER & ANIMASYON PERFORMANSI

> Not: PosterCard zaten epey TV-optimize (TV'de `memCacheWidth:320`, trailer
> kapalı, düz shimmer, statik shadow listesi, RepaintBoundary). Asıl kazançlar
> dashboard hücresi + hero + global decode (RC-A) tarafında.

### P-1 [yüksek→orta] Dashboard TV'de tüm ~6 carousel'i ağır `PosterCard` ile kuruyor (grid'in hafif yolunu kullanmıyor)
- `dashboard_screen.dart:472/511/535/550/566/582` → `ContentList` →
  `content_list.dart:98` `PosterCard`. Grid ekranları `_PosterCardVisual` +
  `TvPosterGrid` kullanıyor; dashboard TV-lite refactor'da atlanmış. Aynı anda
  ~30-45 canlı PosterCard.
- ⚠️ Düzeltme uyarısı: `_PosterCardVisual`'ı doğrudan ContentList'e koymak
  **YÜKSEK risk** — farklı focus sahiplik modeli (PosterCard kendi Focus'unu ve
  sol-kenar→sidebar devrini yönetir). **Doğru yol:** PosterCard'ın ağır
  dekorasyonlarını `isTV`'de yerinde kapat (P-2/P-3), hücre değiştirme.

### P-2 [yüksek] PosterCard her kartta (boştayken bile) drop-shadow çiziyor, TV kapısı yok
- `poster_card.dart:226` `boxShadow: isActive ? _activeShadows : _idleShadows` —
  `isTV` dalı yok. `_idleShadows` (blur 8) her odaklanmamış kartta. Karşılaştır:
  `movies_screen.dart:2435` boştayken `[]` çiziyor.
- **Düzeltme:** `poster_card.dart:226` → TV'de boş kartlarda shadow yok (veya tüm
  platformlarda idle shadow'u kaldır — kenarlık zaten var). Risksiz, sadece boya.

### P-3 [orta] PosterCard kart başına AnimationController + AnimatedContainer; focus → setState + ensureVisible
- İki paralel animasyon sistemi: implicit `AnimatedContainer` (`:213`, 180ms,
  border+shadow) + explicit `_scaleController` (`:454`, scale+lift). Her focus
  olayında ek olarak `Scrollable.ensureVisible` (`:392`, 200ms) — dashboard'da iç
  yatay liste + dış dikey kaydırıcı = iki eşzamanlı scroll animasyonu.
- **Düzeltme:** İkisini tek kaynağa indir (border/shadow'u mevcut
  `_scaleController`'dan türet); TV'de scale'i snap yapmayı düşün (focus ring
  zaten birincil işaret). ensureVisible'ı **kaldırma** (D-pad auto-scroll için
  gerekli).

### P-4 [orta] HeroBanner TV'de 800ms AnimatedSwitcher crossfade + 12s auto-slide (TV kapısı yok)
- `hero_banner.dart:216` 12s `Timer.periodic` → `setState(_currentIndex)`;
  backdrop `AnimatedSwitcher(800ms)` (`:492`) iki adet 1280px backdrop'u
  crossfade ediyor (`:822`). Yalnızca trailer TV'de kapalı (`:280`).
- ⚠️ Düzeltme uyarısı: "TV'de auto-slide'ı kapat (D-pad sürsün)" **TEHLİKELİ** —
  hero index'ini değiştirecek D-pad yolu **yok**; timer'ı kapatmak hero'yu item
  0'da dondurur. **Güvenli:** TV'de crossfade'i anlık/ucuz yap + `memCacheWidth`'i
  1280'in altına düşür. Timer'ı bırak.

### P-5 [orta] Birkaç TV görseli tam-res decode ediyor → bkz. **RC-A** (S-1 ile aynı kök).
### P-6 [düşük] `_PosterCardVisual` focus parıltısı TV'de daha büyük (24px blur). Tek kart, tek seferlik blur — minör. İstenirse `focusRingGlowBlur`'u TV'de düşür.
### P-7 [düşük] `SkeletonLoader` sonsuz `.repeat()` shimmer içeriyor **ama ölü kod** (hiçbir ekran kullanmıyor). Sil veya kullanılırsa TV'de `.repeat()`'i kapat.
### P-8 [düşük] PosterCard gradient + katmanlar — RepaintBoundary sayesinde cache'leniyor, gerçek maliyet düşük. Önceliklendirme.

---

## 🟨 3. D-PAD FOCUS YÖNETİMİ

> Not: Merkezi bir D-pad anahtarı yok — `useDpadNavigation` getter'ı tanımlı ama
> **hiç okunmuyor** (ölü kod, `platform_helper.dart:34`). Focus, Flutter varsayılan
> traversal + dağınık `onKeyEvent`/`autofocus`'a dayanıyor. Bu, aşağıdaki birçok
> boşluğun zeminini oluşturuyor.

### F-1 [yüksek] Canlı TV'de EPG zaman çizelgesi D-pad ile **erişilemez** (`onRightEdge` bağlı değil)
- `TvIndexedList` `onRightEdge`'i destekliyor ve `_onKey` her zaman `handled`
  döndürüyor (`tv_indexed_list.dart:232-235`), ama canlı TV listesi yalnızca
  `onLeftEdge` bağlı bırakmış — Sağ tuşu yutuluyor, EPG'ye ileri giriş yolu yok.
- ⚠️ **3 örnek** var, 2 değil: `live_tv_screen.dart:1362`, `:1475`, **`:1631`**
  (izleme geçmişi). Ayrıca `_EpgTimelineGrid` stateless, kanal-hedefli focus API'si
  **yok** → minimal düzeltme `_epgFocusScope.requestFocus()` (hizasız iner),
  düzgün düzeltme grid'e focus API'si ekler (Stateful'a çevir).

### F-2 [yüksek] Player EPG overlay program listesi + catch-up karoları remote ile tamamen erişilemez
- `epg_overlay.dart:102-115` `_handleKey` yalnızca Escape/Back/G; program listesi
  düz `ListView`, catch-up karoları yalnızca `InkWell(onTap)` (`:459-472`), focus
  node yok. → D-pad yukarı/aşağı listede hareket etmiyor.
- ⚠️ Daha kötüsü (RC-B): oklar `ignored` döndüğü için **arkadaki kanalı
  değiştiriyor**. **Düzeltme:** listeyi `TvIndexedList`'e çevir + RC-B kapısını ekle.

### F-3 [orta] Player kanal-listesi overlay'i: arama alanı D-pad ile erişilemez; liste uçlarında çıkış yok
- `channel_list_overlay.dart:143` yalnızca `_searchFocusNode.hasFocus`'ta okları
  bırakıyor ama hiçbir tuş yolu arama alanına focus **vermiyor** (`requestFocus()`
  hiç çağrılmıyor). Uçlarda ok = ölü basış (`:147-171`). Kategori sekmeleri de
  erişilemez (gerçek focus node değil).
- **Düzeltme:** İlk kanaldan yukarı → `_searchFocusNode.requestFocus()`; arama
  alanından aşağı → listeye dön (143 kapısını yalnızca metin tuşlarını yutacak
  şekilde daralt).

### F-4 [orta] Canlı TV kanal listesi yavaş async yüklemede focus'u kaybediyor (deferred-focus boşluğu)
- `TvIndexedListController`'da **pending-focus mekanizması yok**: boş listede
  `focusFirst` `false` dönüp hiçbir şey kurmuyor; `attach()`/`registerItem()` niyeti
  tekrar oynatmıyor (`tv_indexed_list_controller.dart:87-90, 63-71`) — oysa
  `TvPosterGridController`'da var (`_pendingFocusFirst`). Ayrıca `_focusContent`
  controller'ı baypas edip çıplak wrapper'a `requestFocus` + `focusInDirection`
  yapıyor; cell yoksa focus boş wrapper'a (unmounted node'a) düşüp kayboluyor.
- **Düzeltme:** Poster grid'in pending-focus desenini `TvIndexedListController`'a
  port et; `_focusContent`'i `focusCurrentOrFirst()` çağıracak şekilde değiştir.

### F-5 [orta] Dashboard rail'lerinin focus controller'ı yok — dikey geçiş ve scroll-into-view güvenilmez
- Rail'ler düz yatay `ListView` + `SingleChildScrollView` (`dashboard_screen.dart:352`,
  `content_list.dart:91-114`), `TvPosterGrid`/controller yok. PosterCard yukarı/aşağı
  oklarını `ignored` döndürüyor → dikey geçiş Flutter geometri-traversal'ına kalıyor;
  async veri gelince odaklı node dispose olup focus eskiyebiliyor.
- ⚠️ Düzeltme uyarısı: "ensureVisible'lar yarışıyor" çerçevesi yanlış — tek
  `ensureVisible` tüm scrollable'ları tek pasta ayarlar. Gerçek kusur:
  **deterministik olmayan yönsel traversal**. **Düzeltme:** PosterCard'a
  yukarı/aşağı ok yakalat (komşu rail'in aynı sütununa focus taşı, TvPosterGrid'in
  `focusIndex` yaklaşımı gibi).

### F-6 [orta] Player kontrolleri auto-hide olunca görünmez focus ring gizli butonda kalıyor
- 5s sonra `_resetHideTimer` yalnızca `_showControls=false` + fade; alt bar ağaçta
  kalıyor (FadeTransition+IgnorePointer), odak gizli butonda. `_controlsHaveFocus`
  true kalıyor ama `if (_controlsHaveFocus && _showControls)` artık eşleşmiyor
  (`video_player_screen.dart:1689`) → oklar seek/ses yapıyor; OK gizli butonun
  aksiyonunu tetikliyor. Remote "çalışmıyor" hissi.
- **Düzeltme:** Auto-hide'da (`:1567`) ve toggle-hide'da (`:1543`)
  `_controlsHaveFocus` ise `_focusNode.requestFocus()` ile odağı video yüzeyine
  döndür. Risksiz, mevcut desen.

### F-7 [düşük] ContentList carousel'lerinde yukarı/aşağı kenar yok — üst rail'den hero'ya geçiş deterministik değil (sert tuzak değil; hero zaten erişilebilir). İstenirse `onTopEdge`→hero köprüsü ekle (`search_screen.dart:612` deseni).
### F-8 [düşük] Hero 12s auto-slide odaklı kullanıcının altında içeriği değiştiriyor → "Play'e bastım başka şey açıldı". TV'de `_trailerExpanded` koruması ölü kod olduğundan **yarış sık**. Düzeltme: hero kontrolü odaktayken timer'ı no-op yap.

---

## 🟩 4. KATEGORİ SIDEBAR KAPANMIYOR

> Kök fark: **Ana sidebar focus-driven** kapanıyor
> (`sidebar.dart:75` `addListener` → `_shouldBeExpanded=hasFocus` → 300ms gecikmeli
> `_scheduleCollapse`). **Kategori sidebar** ise yalnızca explicit `_categoriesCollapsed`
> bool'u ile, sadece kategori **seçilince** (Movies/Series) kapanıyor — focus
> panelden çıkınca kapatan **listener yok**.

### C-1 [yüksek] Kategori panelinde collapse-on-blur listener yok (eksik olan ana tetikleyici)
- Üç ekran da `_categorySidebarScope`'u tanımlıyor ve back-resolver'da `.hasFocus`
  okuyor (`movies:142, series:169, live:253`) ama **`_categorySidebarScope.addListener`
  hiçbir yerde yok** (grep = 0). Panel yalnızca explicit aksiyonla kapanıyor.
- ⚠️ Kapsam: Movies/Series'te boşluk yalnızca **seçmeden D-pad Sağ ile grid'e
  geçme** durumunda (seçince zaten kapanıyor, `movies:335`). Live TV'de panel hiç
  kapanmıyor (kasıtlı tasarım, ayrı ele al).
- **Düzeltme:** Ana sidebar'ı aynala — initState'te `addListener`, blur'da 300ms
  debounce'lı collapse (`!hasFocus && !_categoriesCollapsed`), detail açıkken atla,
  dispose'da removeListener + timer cancel. ⚠️ Naif listener **Sol-çıkışta da**
  (ana sidebar'a giderken) kapatır — bu istenmeyebilir; Sağ-çıkış ile Sol-çıkışı
  ayırt edemez.

### C-2 [yüksek] Canlı TV `_selectCategory` paneli hiç kapatmıyor (Movies/Series `0fe40c2` ile tutarsızlık)
- Movies/Series: `_selectCategory` içinde `if (!isMobilePlatform) _categoriesCollapsed
  = true` + grid'e focus (`movies:333-341`). Live TV: yalnızca `_selectedCategoryId`
  + SharedPreferences yazımı, collapse/focus-devri **yok** (`live:358-367`).
- ⚠️ Kısmen kasıtlı: `live:354-357`'de "sidebar açık kalır, kullanıcı toggle ile
  kapatır" yorumu var + her kategori öğesinde `onRightPressed:_focusContent`. Yani
  **ürün kararı**: Live TV'yi Movies/Series'e uydur mu, yoksa farkı belgele mi?
- **Düzeltme (uydurma istenirse):** `live:359`'a `_categoriesCollapsed=true` +
  `_focusContent()` devri (mevcut `_toggleCategorySidebar` deseni güvenli).

### C-3 [orta] D-pad Sağ paneli kapatmıyor ama yorum "kapatır" diyor (üç ekran da)
- Kategori öğesinin arrowRight handler'ı yalnızca `onRightPressed`'i çağırıyor
  (`_focusGrid`/`_focusContent`), hiçbiri `_categoriesCollapsed`'a dokunmuyor —
  ama yorum `// D-pad Right → collapse sidebar and go to content` diyor
  (`movies:1937`).
- **Düzeltme:** C-1 (collapse-on-blur) uygulanırsa otomatik çözülür ve yorum
  doğru olur. Tercih edilen yol bu (tek collapse mekanizması).

### C-4 [düşük] Canlı TV back-resolver hâlâ-açık panele giriyor (C-2'nin alt-semptomu, ayrı hata değil). Resolver'a dokunma; C-1/C-2 düzelince kendiliğinden düzgünleşir.

---

## 🟦 5. CAST — Mobilden TV'ye paylaşımda ses gitmiyor

> Ayrı odaklı ajanın doğrulaması.

### Mekanizma: Ekran yansıtma DEĞİL, **stream-handoff casting**
- `android/`'de hiç `MediaProjection`/ekran yakalama yok (grep = "no matches").
- İki yol: **Chromecast** (`cast_service.dart:198` Default Media Receiver
  `CC1AD845`, `:265` `LOAD contentId:url`) ve **DLNA** (`dlna_service.dart:335`
  `SetAVTransportURI`). İkisi de **ham IPTV URL'ini** TV'ye veriyor; TV kendi
  decoder'ıyla oynatıyor (`DLNA.ORG_CI=0` = transcode yok, `:568`).
- URL `_currentUrl` = telefonun mpv ile açtığı URL (`video_player_screen.dart:2728/2741`).

### Kök nedenler (olasılık sırasına göre)
1. **[baskın] Ses kodeği cast hedefinde çözülemiyor.** IPTV/Xtream yayınları
   sıklıkla **AC-3 / E-AC-3 / MP2 / DTS** ses taşır. Chromecast Default Media
   Receiver yalnızca AAC/MP3/Vorbis/Opus/FLAC çözer (AC-3/E-AC-3 yalnızca Dolby
   lisanslı cihazda HDMI pass-through). Video (H.264) çözülür, ses susar.
   Telefonda mpv hepsini yazılımla çözdüğü için **telefonda ses gelir**.
2. **Chromecast MKV'yi hiç desteklemiyor.** Film/dizi URL'leri `.mkv`
   (`stream_url_builder.dart:30/39`); `_guessContentType` `video/x-matroska`
   döndürüyor (`cast_service.dart:288`) — Default Media Receiver MKV container'ı
   desteklemiyor → tanımsız davranış, sıklıkla video-only.
3. **DLNA pass-through, müzakere yok** (`CI=0`); renderer'ın ses decoder'ı
   embedded kodeği çözemezse sessiz.
4. **Cast LOAD-hata geri bildirimi yok** — `_handleMessage (:347-369)` yalnızca
   `MEDIA_STATUS`/`CLOSE` okuyor, `LOAD_FAILED`/`idleReason:ERROR`'u görmüyor →
   kullanıcı sessiz videoyla baş başa.

### Düzeltme seçenekleri (etki/eforla)
1. **[doğru ama ağır] Yerel transcode/remux proxy:** telefonda küçük HTTP sunucu,
   `ffmpeg -c:v copy -c:a aac` ile sesi AAC'ye çevirip MP4/HLS'e remux et, proxy
   URL'ini `loadMedia`'ya ver. Her alıcıda ses + MKV sorununu da çözer. (FFmpeg
   bundling, CPU/pil maliyeti.)
2. **Cast yolunda HLS/AAC varyantı tercih et:** Xtream'de mevcutsa canlıda `.m3u8`
   zorla (Cast HLS destekler), VOD'da `.mkv` yerine HLS dene. Sağlayıcıya bağlı.
3. **Chromecast'e MKV gönderme:** `.mkv` algıla → DLNA'ya yönlendir veya
   "Bu format Chromecast'e gönderilemiyor" göster.
4. **Cast LOAD-hata yönetimi ekle** (`cast_service.dart:347`) → kullanıcıya
   "ses kodeği desteklenmiyor" mesajı (DLNA zaten `_verifyPlaying` ile yapıyor).
5. **Hızlı kazanç:** `_guessContentType`'ı düzelt + DLNA'yı codec-toleranslı LG/
   Samsung için Chromecast'e tercih et.

---

## ➕ DENETİMİN KAÇIRDIĞI YENİ BOŞLUKLAR

- **GAP-1 [yüksek] Ayarlar ekranı:** sol nav'dan sağ içeriğe D-pad köprüsü yok
  (`settings_screen.dart:312-320` yalnızca select/enter); birçok satır `Focus`
  sarmalı olmayan `InkWell`/`ListTile` (`:491, 1055, 1705, 2474, 2486`) → D-pad ile
  erişilemez. İçerik değişiminde odak dispose olup kayboluyor.
- **GAP-2 [yüksek] Player alt-bar `Slider`:** `_buildVodProgressBar` ham Material
  `Slider` (`:3928`) butonların arasında; odaklanınca sol/sağ oklarını scrub için
  yutuyor → kullanıcı diğer butonlara geçemiyor, dikey kaçış yok.
- **GAP-3 [orta] AI dashboard rail'leri TV-lite kapalı değil:** `DashboardGreeting`,
  `WeeklyDigestBanner`, `PersonalizedPicksRail`, `MoodSelector` koşulsuz render
  (`dashboard_screen.dart:409/489/495/500`); yalnızca chat FAB `isTV` kontrol ediyor.
  → `if (!isTV)` ile sar.
- **GAP-4 [düşük]** `profile_picker_sheet.dart` yapısal olarak sağlam (tuzak yok),
  uzun listede kaydırma test edilmeli.
- **GAP-5 [düşük]** `pip_overlay.dart` tuş yönetimi yok ama desktop-gated; TV'de
  tetiklenmediği teyit edildi.

---

## 🗺️ ÖNERİLEN DÜZELTME SIRASI

1. **RC-A (çökme sınıfı, en yüksek kaldıraç):** her `CachedNetworkImage`'a
   `memCacheWidth` + `main.dart:58-60` cache bütçesini `isTV`'de düşür. Arama
   OOM'unu ve player/dashboard logo birikim çökmelerini kapatır.
2. **Arama donması (S-2):** `searchChannelsByType`'a `ORDER BY`+`.limit()` +
   haystack/fuzzy işini ana isolate'ten çıkar.
3. **RC-B (player overlay ok sızıntısı):** `_handleKey`'de okları açık-overlay'de
   yut + EPG/kanal/altyazı listelerini odaklanabilir yap. Üç "hayalet
   seek/kanal" semptomunu birden çözer.
4. **GAP-1 + GAP-2:** ayarlar nav→içerik köprüsü + odaklanamayan satırları `Focus`'a
   sar + Slider traversal tuzağı.
5. **Poster perf konsolidasyonu + GAP-3:** tek TV-lite PosterCard (idle shadow yok,
   tek animasyon, gated glow) + AI rail'lerini `if (!isTV)`.
6. **D-pad focus (F-1 üç örnek dâhil, F-4 deferred-focus, F-8 hero):** çökme/donma
   sonrası.
7. **Kategori sidebar (C-1/C-2):** ürün/tutarlılık kararı (Live TV'yi uydur veya
   farkı belgele). En düşük aciliyet — rahatsızlık, çökme değil.

**İmplementasyondan önce hâlâ açılması gerekenler:** `lib/config/router.dart`
(TV'de takılan sayfa geçiş süresi var mı?) ve player ses/altyazı **track** seçici
sheet'leri (`video_player_screen.dart:~2031, ~2239`) — uzun listeler TV'de.
