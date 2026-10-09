# LifeOS TV — Yayın öncesi inceleme

Tarih: 9 Ekim 2026. İncelenen sürüm: **1.13.6+2087**, commit **9df7d033318ab7e7236e6b0f4aa878a4038960a9**. İnceleme Linux bilgisayarında Flutter 3.47.2 / Dart 3.13.2 ile yapıldı. Kaynak kod, yerel paket değişiklikleri, dağıtım ayarları, mevcut testler ve aşağıdaki sentetik kontroller değerlendirildi.

**Değerlendirme: mevcut sürüm bütün hedef platformlarda son kullanıcıya yayınlanmaya hazır olarak onaylanamaz.** Testler geçiyor; buna rağmen bölüm geçişi, Android TV özellik eşitliği, Gemini geçişi, Kürtçe dil altyapısı ve macOS izin/dağıtım ayarlarında somut eksikler var. Mevcut testlerin geçmesi bu kullanıcı akışlarının doğrulandığı anlamına gelmiyor.

Bu çalışma bir inceleme ve çözüm raporudur; üretim kodu veya model ayarları değiştirilmedi. Çalışma başında bulunan 26 dosyadaki satır sonu değişiklikleri korundu. Yeni rapor, kanıt dosyaları ve denetim testleri eklendi. GitHub Actions durumu API ile kontrol edildi: `build.yml` **disabled_manually**. Gerçek Gemini isteği gönderilmedi; kullanıcının anahtarıyla 3.8 erişimi, kota ve yanıt kalitesi henüz ölçülmedi. Anahtar ve imza dosyalarının içerikleri okunmadı veya rapora alınmadı.

## Doğrulama ve sınırlar

| Kontrol | Sonuç | Kanıt |
|---|---|---|
| `flutter analyze lib test tool --no-pub --no-fatal-infos` | Hata/uyarı yok; 73 bilgi seviyesinde bulgu | [analyze.log](/home/erkanoz/projeler/iptv/lifeos-iptv-player/docs/release-audit-2026-10-09/analyze.log) |
| `flutter test --no-pub --reporter=expanded` | **482 test geçti** | [tests.log](/home/erkanoz/projeler/iptv/lifeos-iptv-player/docs/release-audit-2026-10-09/tests.log) |
| Yeni denetim kontrolleri ve iki benchmark | **6 test geçti**; mevcut kusurları tespit eden testlerdir | [probes.log](/home/erkanoz/projeler/iptv/lifeos-iptv-player/docs/release-audit-2026-10-09/probes.log) |
| Sekiz ARB dosyası | Her dilde 510 anahtar; eksik/fazla anahtar ve değişken uyuşmazlığı yok | [l10n-inventory.json](/home/erkanoz/projeler/iptv/lifeos-iptv-player/docs/release-audit-2026-10-09/l10n-inventory.json) |
| Dil delegeleri, ID çakışması, intro sınırları, timeout | Aşağıdaki bulgular çalıştırılarak doğrulandı | [probe-results.json](/home/erkanoz/projeler/iptv/lifeos-iptv-player/docs/release-audit-2026-10-09/probe-results.json) |

Yeni testler `docs/release-audit-2026-10-09/` altında tutuldu. Bazıları hatalı mevcut davranışı doğrular; düzeltme yapılınca ilgili testin beklentisi tersine çevrilip gerçek regresyon testine dönüştürülmelidir. ARB kontrolü çevirilerin dilbilimsel kalitesini kanıtlamaz; İngilizceyle aynı olan marka/teknik terimler otomatik hata sayılmadı.

Bu turda fiziksel Android TV, iPhone, Mac veya Windows bilgisayarında çalıştırma, ekran görüntüsü incelemesi ve codec akıcılığı ölçümü yapılmadı. UI değerlendirmesi kaynak kodu ve mevcut widget/focus testlerine dayanır. Eski Linux görüntüleri veya önceki APK denemeleri yeni sürümün bütün platform onayı olarak kullanılmadı.

## Öncelikli bulgular

P0: yayın hazırlığında hemen ele alınmalı. P1: hedeflenen yayın veya temel akışı engeller. P2: kalite, tutarlılık ve sürdürülebilirlik iyileştirmesi. “Doğrulama açığı” bir özelliğin kesin bozuk olduğu anlamına gelmez.

### F01 — P0: Android imza dosyaları Git tarafından izleniyor

`git ls-files android/keystore android/key.properties` hem `android/key.properties` hem `android/keystore/lifeostv-release.jks` döndürüyor. Release imza yapılandırması [android/app/build.gradle.kts:12](/home/erkanoz/projeler/iptv/lifeos-iptv-player/android/app/build.gradle.kts:12) üzerinden bu dosyayı kullanıyor. Repo özel; anahtarın halka sızdığı söylenemez. Ancak kaynak erişimiyle imza materyalinin aynı yerde bulunması yayın güvenliğinde somut bir açık.

**Çözüm:** imza materyalini güvenli depoya/CI secret'larına taşı; izlenen kopyaları ve erişim kapsamını incele; Git geçmişi temizliği ve gerekiyorsa anahtar değişimini mevcut kurulumların güncelleme zincirini koruyacak planla yap. İçerik/parola rapora veya loga eklenmemeli. **Kabul:** temiz checkout imza materyali içermez, yetkili release işi doğru sertifikayla imzalar, mevcut APK üzerine güncelleme çalışır. Bu rapor sırasında dosya silinmedi veya anahtar değiştirilmedi.

### F02 — P1: Platform dağıtımı tamamlanmamış ve CI kapalı

[.github/workflows/build.yml:135](/home/erkanoz/projeler/iptv/lifeos-iptv-player/.github/workflows/build.yml:135) Windows için ZIP üretiyor; kurulum/güncelleme ve imza akışı yok. Android işi APK üretiyor, Play AAB üretmiyor. Apple işi macOS derlemesi ve `ios --no-codesign` kontrolü yapıyor; Apple artifact yüklemesi, imzalı IPA/TestFlight ve macOS dağıtım paketi/notarization işi yok. İş akışı ayrıca manuel devre dışı. Flutter `stable` kanalı sabit bir sürüme bağlanmamış.

**Çözüm:** CI'ı kontrollü etkinleştir; Flutter sürümünü sabitle; macOS/iOS imzalı dağıtım hattı, Android AAB ve seçilen Windows dağıtım biçimini oluştur. İmzalama ve Apple kimlikleri dış yapılandırma gerektirir. macOS yayın adımları için [Flutter'ın resmi dağıtım rehberi](https://docs.flutter.dev/deployment/macos) esas alınmalı. **Kabul:** temiz runner'lardan bütün hedefler derlenir; gerçek kullanıcı paketleri kurulup güncellenir; test işi başarısızken yayın çıkmaz.

### F03 — P1: Gemini 3.8 geçişi tek bir model adını değiştirerek yapılamaz

[lib/data/services/ai_model_policy.dart:13](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/ai_model_policy.dart:13) parser/greeting/episodeSummary/catalogEnrichment için **gemini-2.5-flash-lite**; diğer metin görevleri için **gemini-2.5-flash**; embedding için **gemini-embedding-001** seçiyor. Fakat [lib/data/services/gemini_service.dart:27](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/gemini_service.dart:27) çoğu görevi ayrı bir sabit üzerinden 2.5 Flash'a gönderiyor. `searchRerank`, `dashboardRanking`, `longText`, `chat` politikasını değiştirmek gerçek endpoint'i değiştirmeyebilir; telemetry de politikayı gerçek kullanılan model sanıyor.

Google'ın 9 Ekim'de kontrol edilen belgelerinde **gemini-3.8-flash** kararlı model olarak mevcut. Düşünme seviyeleri low/medium/high; minimal desteklenmiyor. [Resmi model sayfası](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash). Mevcut istekler `temperature` ve pek çok yerde `thinkingBudget: 0` gönderiyor. 3.8 geçiş rehberi eski örnekleme alanlarını kaldırmayı ve düşünme seviyesine geçmeyi söylüyor. [Resmi geçiş rehberi](https://ai.google.dev/gemini-api/docs/latest-model).

**Çözüm:** tüm metin görevlerini kullanıcının istediği **3.8 Flash** üzerinden gerçek bir ortak istemciye bağla; görev/model/üretim ayarını ve kaydedilen modeli aynı konfigürasyondan üret. Basit JSON işleri low, karmaşık sohbet medium ile başlayıp ölç. `generateContent` ile `Interactions` sözleşmelerini ayrı tut; alan adlarını birbirine karıştırma. Embedding metin üretiminden ayrı kalmalı. **Kabul:** sahte HTTP taşıyıcısı ile her özelliğin endpoint/payload'ı doğrulanır; ardından gerçek anahtarla küçük smoke/eval seti çalışır; kota/401/400/429/503 ve kesik JSON doğru raporlanır.

### F04 — P1: Agent araç sözleşmesi ve sohbet durumu yeni modele hazırlanmalı

[lib/data/services/gemini_service.dart:627](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/gemini_service.dart:627) araç yanıtını yalnızca name/response ile oluşturuyor; çağrı kimliği taşımıyor. Resmi 3.8 rehberi `generateContent` FunctionResponse için çağrı kimliği ve isim istiyor. Tek bir agent döngüsü içinde modelin `parts` verisi korunuyor; fakat sonraki kullanıcı mesajında geçmiş yalnızca metinden yeniden kuruluyor. Araç ve düşünme metaverisi kullanıcı turları arasında kayboluyor. [Geçiş rehberi](https://ai.google.dev/gemini-api/docs/latest-model), [düşünme ve imza davranışı](https://ai.google.dev/gemini-api/docs/thinking?linkId=14119577).

Birçok tek çağrı ayrıştırıcısı `parts.first['text']` okuyor ([lib/data/services/gemini_service.dart:124](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/gemini_service.dart:124)): düşünce/metaveri içeren ilk parça, boş aday, safety/finishReason ve token sınırı tek bir yanıt sözleşmesiyle ele alınmıyor. Agent altı turu tüketince boş sonucu normal dönüş olarak veriyor.

**Çözüm:** API'ye özgü çağrı kimliği eşlemesi, düşünce olmayan metinlerin birleşimi, finishReason ayrımı ve araç geçmişini taşıyan sohbet modeli. Interactions kullanımı bir seçenek; zorunlu olarak bütün uygulamayı taşımak gerekmiyor. **Kabul:** iki kullanıcı turu, birden çok araç çağrısı, thought parçası, truncation ve tur sınırı fixture'ları doğru ve görünür sonuç verir.

### F05 — P1: Dizide bölüm geçişi gerçekten player route'unu kapatıyor

[lib/presentation/screens/series/series_screen.dart:840](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/series/series_screen.dart:840) ve önceki bölüm callback'i `context.pop()` → 250 ms bekle → `_playEpisode(...)` yapıyor. Kullanıcının gördüğü kapanma/yeniden açılma bu akışın doğrudan sonucu; genel bir codec varsayımı değil. Yeni route yeni oynatıcı oturumu açıyor.

Ek yarış: [lib/presentation/screens/series/series_screen.dart:752](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/series/series_screen.dart:752) kilidi önceki `context.push` dönüşü ve sonrasında yapılan ilerleme sorgusu bitene kadar açık. 250 ms sonra başlayan çağrı kilit yüzünden düşebilir. TV tarafında [lib/presentation/screens/player/tv_video_player_screen.dart:915](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/tv_video_player_screen.dart:915) `_switchingEpisode` değerini sıfırlamıyor; VoidCallback ile async geçişin sonucu/hatası beklenemiyor.

**Çözüm:** tek route içinde türü belirli bölüm listesi ve `Future` döndüren geçiş işlemi. Önce mevcut bölüm ilerlemesini kaydet; URL/başlık/header/intro/track tercihlerini yeni bölüme geçir; mevcut backend'de yeni kaynağı aç. TV decoder değişimi gerekiyorsa eski controller'ı güvenle bırak ama sayfayı kapatma. İstek nesli, timeout ve `finally` kilit sıfırlaması kullan. **Kabul:** ardışık next/prev, sezon sınırı, bozuk bölüm, hızlı tekrar basma ve otomatik geçişte detay sayfası görünmez; tam ekran ve focus korunur; eski bölüm yeni ID altında kaydedilmez.

### F06 — P1: Android TV'de intro ve otomatik sonraki bölüm eşitliği yok

Router [lib/config/router.dart:88](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/config/router.dart:88) TV için ayrı ExoPlayer ekranını açıyor. Masaüstü route'una geçirilen `introDefaultSeconds` TV'ye geçirilmiyor. TV ekranında intro marker/skip butonu ve completion/`autoNextEpisode` işlemi bulunmuyor; [lib/presentation/screens/player/tv_video_player_screen.dart:550](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/tv_video_player_screen.dart:550) oynatma değer dinleyicisi bunları ele almıyor. Masaüstünde completion ile otomatik bölüm geçişi var ([lib/presentation/screens/player/video_player_screen.dart:1081](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/video_player_screen.dart:1081)).

**Çözüm:** aynı bölüm/intro durum modelini iki backend kullanmalı. Kumandadan intro butonuna erişim, completion yalnızca bir kere çalıştırma ve hata durumunda başka bölüme geçebilme birlikte uygulanmalı. **Kabul:** aynı dizi Android TV ve masaüstünde aynı intro/auto-next ayarına uyar; remote Cast/DLNA davranışı da ayrıca tanımlanır.

### F07 — P1: Film detayında eski API yanıtı yeni filmi ezebilir

[lib/presentation/screens/movies/movies_screen.dart:279](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/movies/movies_screen.dart:279) içinde `getVODInfo` beklenirken sadece `mounted` kontrol ediliyor. A filmi açılıp yanıt gelmeden B filmi açılırsa A'nın geç yanıtı B ekranına yazılabilir. Arka plan yenilemesi stream ID kontrol ediyor ama ilk yükleme bunu yapmıyor; hesap değişiminde sadece ID kontrolü de yeterli olmaz.

**Çözüm:** dizi detayındaki gibi istek nesli + account/type/ID eşlemesi; detay kapatılınca önceki istekleri geçersiz kıl. **Kabul:** ters sırada yanıtlanan A/B fixture'ında B'nin metadata, fragman ve oynatma kaynağı korunur; kapanmış detay yeniden değişmez.

### F08 — P1: Kürtçe ARB var; Flutter'ın temel locale delegeleri yok

[lib/main.dart:462](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/main.dart:462) `ku` ilan ediyor. Denetim testinde AppLocalizations ku için true; GlobalMaterial, GlobalCupertino ve GlobalWidgets ku için **false** döndü. Dolayısıyla 510 Kürtçe metnin bulunması Material/Cupertino/Widgets yerelleştirme ihtiyaçlarını karşılamıyor. Bu dilde bileşenler eksik localization ile kalabilir; yalnız ARB saymak yeterli değil.

**Çözüm:** ku için uygun tarih/sayı/semantics/text direction davranışını da sağlayan delegeler veya uygulama metni ku kalırken framework için açıkça belirlenen bir fallback oluştur. **Kabul:** ku ile Scaffold, TextField, dialog, DatePicker, menü ve player açılır; framework localization eksikliği yoktur. Fallback sessizce uygulamanın tamamını İngilizceye çevirmemeli.

### F09 — P1: macOS sandbox dosya yetkisi eksik

[macos/Runner/Release.entitlements:1](/home/erkanoz/projeler/iptv/lifeos-iptv-player/macos/Runner/Release.entitlements:1) ve DebugProfile entitlements user-selected file izni içermiyor. Kullanılan file_picker 8.3.7 dosya seçimi için bu izni gerektiriyor; backup export/import ve yerel M3U seçimi bu yola bağlı ([lib/data/services/backup_service.dart:138](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/backup_service.dart:138)). [Plugin changelog](https://github.com/vicajilau/flutter_file_picker/blob/main/packages/file_picker/CHANGELOG.md), [Apple dosya yetkisi](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.files.user-selected.read-write?changes=_9).

**Çözüm:** ihtiyaç kapsamına uygun read-write entitlement ve paket içindeki gerçek dosya erişimini doğrula. **Kabul:** imzalı sandbox release'de belge seçme, backup kaydetme/geri yükleme ve kullanıcı iptali çalışır. Linux'ta çalışan file picker macOS onayı sayılmaz.

### F10 — P1: macOS yerel ağ izni tanımı eksik

[macos/Runner/Info.plist:1](/home/erkanoz/projeler/iptv/lifeos-iptv-player/macos/Runner/Info.plist:1) yerel ağ açıklaması içermiyor. iOS plist'inde açıklama/Bonjour bildirimleri var. LAN sync/Cast/DLNA kullanan Mac sürümü için yerel ağ izin akışı ve imzalı uygulama kimliği ele alınmalı. Apple, yerel ağ erişiminde kullanım açıklamasını ve macOS'ta kararlı imza kimliğini anlatıyor. [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy?changes=_9%2C_9).

**Çözüm/kabul:** hedef macOS sürümlerinde ilk izin, reddetme, sonradan izin verme ve uygulama güncellemesi test edilmeli; Bonjour bildirimleri gerçekten kullanılan servislere göre düzenlenmeli. Burada her HTTP medya URL'sinin ATS nedeniyle bozuk olduğu iddia edilmiyor; Dio/libmpv ile native ağ yolları ayrı değerlendirilmelidir.

### F11 — P1: AI timeout alttaki araç işini durdurmuyor

[lib/data/services/ai_instrumentation_service.dart:51](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/ai_instrumentation_service.dart:51) sadece Future sonucunun beklenmesini sonlandırıyor. Denetim testi timeout sonucu null döndükten sonra alttaki işlemin tamamlandığını doğruladı. Chat [lib/presentation/widgets/ai/tonight_chat_sheet.dart:156](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/widgets/ai/tonight_chat_sheet.dart:156) sadece mounted/account/profile kontrol ediyor; turn ID veya iptal durumu yok. 60 saniye timeout sonrasında aynı sayfa ve hesap açıkken agent geç gelen favori/hatırlatma işlemlerine devam edebilir; aynı anda fallback cevap da çalışabilir.

**Çözüm:** bütün turn için CancellationToken/CancelToken + turn generation; timeout, yeni mesaj, kapanma ve hesap/profil değişiminde iptal et. Mutasyon öncesi ve await sonrası geçerliliği kontrol et. **Kabul:** timeout olmuş/eski turn hiçbir araç mutasyonu veya navigasyon yapmaz; tek kullanıcı mesajı için tek sonuç üretilir.

### F12 — P1: LAN eşleşmesi var ama aktarım şifreli değil

[lib/data/services/lan_sync_service.dart:31](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/lan_sync_service.dart:31) kodun kendisi HTTP aktarımın token ve seçilen hesap kimlik bilgilerini LAN'da açık taşıdığını belirtiyor. PIN kapısı/rastgele token ve secret'ların ayrı seçilmesi iyi korumalar; bunlar taşıma şifrelemesi değildir.

**Çözüm:** kimliği doğrulanan, eşleştirmeden türetilen anahtarla şifreli taşıma veya sertifika pinning kullanan TLS tasarımı; kaydedilen cihaz kimliği ve replay koruması. **Kabul:** ağ fixture'ında PIN, token, hesap parolası ve API anahtarı paket içeriğinde düz metin görünmez; sahte eş cihaz reddedilir. Mevcut LAN pairing testleri bu güvenceyi vermiyor.

### F13 — P2: “İntroyu Atla” içerik tanımıyor; ilk 90 saniyeyi atlıyor

[lib/presentation/screens/player/video_player_screen.dart:633](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/video_player_screen.dart:633) kayıt yokken ilk `introDefaultSeconds` boyunca butonu gösteriyor; varsayılan 90 saniye. [lib/presentation/screens/player/video_player_screen.dart:596](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/video_player_screen.dart:596) bu sabit zamana seek yapıyor. Görüntü/ses analizi, bölüm karşılaştırması veya güven skoru yok. Cold open, önceki bölüm özeti ve intro olmayan ilk bölümde gerçek sahne atlanabilir. Marker henüz yüklenmeden sabit öneri de gösterilebiliyor.

**Çözüm:** doğrulanmamış durumda “akıllı intro” iddiası kaldırılmalı; buton ya gizlenmeli ya açıkça manuel “90 saniye ileri” olarak sunulmalı. Marker loading/unknown/verified durumları ayrılmalı. Önce güvenilir manuel işaretleme ve backend eşitliği; ardından sınırları belirli yerel ses/görüntü fingerprint eşleşmesiyle gerçek tespit. Gemini'ye yalnız başlık vererek timestamp tahmin ettirmek güvenilir bir intro çözümü olmaz.

**Kabul:** intro olmayan, cold open'lı, recap'li ve farklı kurguya sahip örneklerde yanlış sahne atlama yok; kullanıcının yaptığı düzeltme kalıcı; geri seek ve marker yüklenmesi tutarlı.

### F14 — P2: Intro marker kapsamı ve doğrulaması yetersiz

[lib/data/datasources/local/tables.dart:474](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/datasources/local/tables.dart:474) yalnız `(seriesId, accountId)` ile tek aralık saklıyor. Sezon, bölüm, medya sürümü, source/confidence yok. Hesap kapsamı korunmuş; sorun aynı dizinin tüm bölümlerine aynı zaman aralığı uygulanması. [lib/data/repositories/intro_marker_repository.dart:45](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/repositories/intro_marker_repository.dart:45) negatif/ters aralığı kabul ediyor; denetimde -1000 / -5000 kaydedildi. UI doğruluyor fakat repository bütün yazım yollarını korumuyor.

**Çözüm:** bölüm override → sezon → doğrulanmış seri eşleşmesi önceliği; source/confidence ve içerik kimliği; repository'de `0 ≤ start < end ≤ duration` sınırı; eski kayıtları güvenilirliği bilinmeyen legacy olarak taşı. **Kabul:** sezon/cut farkı yanlış skip'e yol açmaz; bozuk import/marker depoya giremez; mevcut backup kaydı kaybolmaz.

### F15 — P2: Intro öğrenimi diğer cihaza senkronlanmıyor

Backup introMarkers tablosunu içeriyor ([lib/data/services/backup_service.dart:67](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/backup_service.dart:67)). Fakat [lib/data/services/lan_sync_service.dart:40](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/lan_sync_service.dart:40) ve snapshot/merge yolları intro marker taşımıyor; sadece genel skip ayarını taşıyor. Masaüstünde işaretlenen intro eşleştirilmiş cihazda öğrenilmiş sayılmıyor.

**Çözüm:** hesap/içerik/sezon/bölüm kimliği ve güncelleme zamanı içeren ayrı marker senkron sözleşmesi; silme/tombstone ve güven çakışması politikası. **Kabul:** A'da öğren, B'de kullan; A'da düzelt/sil, B'ye yansır; başka hesabın sayısal ID'sine uygulanmaz.

### F16 — P2: Sistem dili AI ve arayüz arasında tutarsız

[lib/presentation/state/personalized_picks_provider.dart:328](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/state/personalized_picks_provider.dart:328), hero/mood/digest ve [lib/presentation/widgets/ai/tonight_chat_sheet.dart:236](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/widgets/ai/tonight_chat_sheet.dart:236) sistem için Türkçe seçiyor. [lib/presentation/screens/search/search_screen.dart:511](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/search/search_screen.dart:511) ise gerçek Localizations locale'ini kullanıyor. İngilizce sistemde UI/search İngilizce, sohbet/öneri Türkçe olabiliyor. Backup save dialog başlığı Türkçe; player'daki DLNA hata ve OpenSubtitles anahtar mesajı da ARB dışında ([lib/presentation/screens/player/video_player_screen.dart:2874](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/video_player_screen.dart:2874), [lib/data/services/backup_service.dart:152](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/backup_service.dart:152)).

**Çözüm:** UI için çözülmüş locale'i tek provider'da belirle; tüm AI isteklerine ve ilgili cache anahtarlarına aynı locale'i ver; görünür sabit metinleri ARB'ye taşı. Arayüz dili, içerik dili, ses dili ve altyazı tercihi ayrı kullanıcı ayarları kalmalı; zorla aynı yapılmamalı. **Kabul:** sekiz dilde sistem/manuel seçim, desteklenmeyen sistem locale'i, dil değişiminde cache/AI yanıtı ve RTL testi. Tam metin çeviri kalitesi native speaker değerlendirmesi gerektirir.

### F17 — P2: Sistem teması açık temaya dönüşüyor

[lib/main.dart:473](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/main.dart:473) sadece dark için dark, kalan tüm değerler için light veriyor. `AppThemeMode.system` işletim sistemi değişimini izlemiyor. **Çözüm:** system/light/dark üç değerli eşleme. **Kabul:** cihaz teması değişince system uygulama teması güncellenir; manuel seçim korunur.

### F18 — P2: AI istemcisi gereksiz yeniden kuruluyor; hata/log verisi fazla genel

[lib/data/services/gemini_service.dart:3178](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/gemini_service.dart:3178) tüm ayarları izleyip yeni GeminiService/Dio kuruyor. Ses/altyazı/tema gibi ilgisiz ayar değişikliği session cache'lerini kaybettirebilir; Dio için dispose/close bağlantısı yok. Gemini metodları çoğu hatayı null'a çeviriyor; instrumentation `empty_response` ile kota/kimlik/payload hatasını ayıramıyor. Bazı loglar response body veya raw JSON içeriyor; API anahtarı query parametresinde ve bazı exception logları tam nesneyi yazıyor. Bu raporda gerçek anahtarın loga sızdığı gözlemlenmedi.

**Çözüm:** sadece key/config seçimlerini izle, istemciyi yaşam döngüsünde kapat; ortak türü belirli hata ve kullanım metrikleri döndür; anahtarı header'da taşı ve log redaction uygula. Debug/release loglarının ayrı politikası olsun. **Kabul:** ilgisiz ayar değişimi cache/istekleri bozmaz; 401/429/timeout/schema farklı görünür; loglar key/prompt/hesap sırrı içermez.

### F19 — P2: AI önerilerinde içerik türü eksik; bazı geçerli sonuçlar düşüyor

Arama küratörü request-local ID ve `(type, streamId)` kullanarak bu sorunu çözmüş ([lib/presentation/screens/search/search_screen.dart:454](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/search/search_screen.dart:454)). Ancak [lib/data/models/tonight_recommendation.dart:10](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/models/tonight_recommendation.dart:10) sadece sayısal streamId saklıyor. Chat önerileri [lib/presentation/widgets/ai/tonight_chat_sheet.dart:326](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/widgets/ai/tonight_chat_sheet.dart:326) içinden türsüz `getVisibleChannel` ile çözülüyor. Repository belirsiz ID'yi güvenli biçimde reddediyor; denetim aynı ID'li film/dizide null döndüğünü doğruladı. Yani doğru AI önerisi kart olarak görünmeyebilir; mevcut koruma yanlış filmi açma riskini azaltıyor.

**Çözüm:** bütün öneri ve feedback modellerinde türü belirli ContentKey veya request-local ID çözümleme; schema→cache→kart→play zinciri aynı kimliği kullanmalı. **Kabul:** aynı ID'li film/dizi/canlı ve farklı hesap fixture'larında doğru kart/tür görünür; gizlenmiş içerik geri sızmaz.

### F20 — P2: Dashboard “yeni içerik” havuzu ilk 2000 satıra bağlı

[lib/presentation/state/hero_billboard_provider.dart:186](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/state/hero_billboard_provider.dart:186) VOD havuzunu orderBy olmadan limit2000 ile alıp yalnız bu kesiti Dart'ta added tarihine göre sıralıyor. Büyük katalogda gerçekten en yeni içerik bu 2000 satır dışında kalabilir. Text timestamp SQL'de sayıya çevrilerek sıralanabilir; mevcut yorumdaki “SQL'de sıralayamayız” gerekçesi yeterli değil.

**Çözüm:** sıralamayı ve sınırı SQL'de doğru sırada uygula; normalize edilmiş added epoch sütunu/index'i gerekiyorsa migration ile ekle; recency/diversity havuzunu ölç. **Kabul:** 5000+ satırlık fixture'ın sonunda eklenen en yeni içerik havuza girer; gizli/yetişkin/disliked filtreleri korunur.

## “Akıllı intro” için uygulanabilir tasarım

1. İlk paket: bölüm geçişini tek player session'a taşı; TV ve masaüstüne ortak intro/completion controller koy. Manuel başlangıç/bitiş işaretlemesini kumandadan da erişilebilir yap. Hedef timestamp'i medya süresine göre doğrula.
2. Veri modeli: hesap ve türü belirli dizi kimliği + sezon + bölüm/medya kimliği + start/end + source + confidence + revision. Sezon/seri şablonunu ancak tekrar eden eşleşme varsa kullan. Manuel işaret otomatik tahminden üstün olmalı.
3. Yerel analiz: komşu bölümlerden başlangıçta sınırlı örnek al; tekrarlayan ses/görüntü imzası ve cold open farkını değerlendir. Analiz oynatıcı UI/decoder işini engellememeli; background runner oynatma sırasında durmalı. Codec çeşitliliği ve içerik erişimi ayrıca ölçülmeli.
4. AI desteği: zaman damgalı kanıt ve aday aralıklar üzerine 3.8 Flash yorumlaması ancak doğrulanmış eval faydası varsa eklenmeli. Başlıktan üretilecek süre tahmini doğrulanmış marker yerine geçmemeli. Medya gönderimi, maliyet ve içerik izinleri ürün kararı gerektirir.
5. Kalite kapısı: etiketli cold open/recap/değişen intro/intro olmayan örnekler; false-positive oranı, sınır sapması, öğrenme gecikmesi ve CPU/RAM maliyeti. Önerilen ilk hedef: sahne atlayan false-positive yok; güven düşükse buton yok. Bu bir ölçülmüş sonuç değil, yayın kabul hedefidir.

## Yapay zekâyı daha kaliteli kullanma planı

| Görev | Başlangıç yapılandırması | Kalite ve süre kontrolü |
|---|---|---|
| Intent/suggestion/kısa metadata | 3.8 Flash low, dar schema | JSON doğruluğu, dil doğruluğu, iptal, küçük token bütçesi |
| Arama sıralama / dashboard | 3.8 Flash low veya ölçüme göre medium | Yerel retrieval → çeşitlendirilmiş aday → rerank; gerçek ContentKey doğrulaması |
| Chat / araçlı yardım | 3.8 Flash medium | Türü belirli araçlar, deadline, turn cancellation, kimlik eşlemesi ve yan etkilerin doğrulanması |
| Plot / recap | 3.8 Flash ölçüme göre low/medium | Kaynak açıklama esas alınır; eksik bilgi icat edilmez; spoiler sınırı ve hedef dil test edilir |
| Semantik embedding | Ayrı embedding modeli | Mevcut normalize edilmiş 768 boyutlu indeks; model/recipe değişirse kontrollü yeniden indeksleme |

Model sürümü tek başına kalite ölçümü değildir. Türkçe/İngilizce/Arapça/Kürtçe ve diğer diller için sabit eval seti gerekir: tam başlık, typo, tür/oyuncu, eş anlamlı tema, bulunmayan içerik, çakışan ID, çocuk/gizli kategori ve bozuk metadata. Aramada precision@k/recall@k, yanlış içerik açma, yanıt dili, latency p50/p95 ve çağrı başına token ölçülmeli. Bu incelemede canlı model çıktısı puanlanmadı.

AI araması [lib/presentation/screens/search/search_screen.dart:358](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/search/search_screen.dart:358) intent ve curator için ayrı 15 saniye bekliyor; toplam süre DB işlemleriyle 30 saniyeyi aşabilir. Debounce ve stale-result kontrolleri mevcut; gerçek HTTP iptali ve tek uçtan uca deadline eksik. Yerel sonuçlar hemen kalmalı; AI iyileştirmesi süre aşınca sessizce bitmeli. Ek araç aramalarını sırayla DB'de çözmek yerine batch lookup yapmak da ölçülmeli.

## Ölçülen performans

Tek Linux test koşusundaki sentetik sonuçlar aşağıdadır; p95 veya fiziksel cihaz/video frame ölçümü değildir. SQLite fixture bellekte/test isolate'ında; uygulama DB'si worker kullanır. RSS bütün test sürecini içerir ve player RAM ölçümü sayılmaz.

| Senaryo | Toplam süre | Test isolate timer'ındaki en büyük boşluk |
|---|---:|---:|
| 10k katalog, tam ana isolate fuzzy tarama karşılaştırması | 207,0 ms | 203,2 ms |
| 10k katalog, indeks yok, tam başlık | 613,5 ms | 25,9 ms |
| 10k katalog, indeks yok, typo | 1100,3 ms | 37,0 ms |
| 10k katalog, indeksli başlık | **4,8 ms** | 11,1 ms |
| 10k × 768 embedding, tüm vektörleri ana isolate'ta sıralama | 132,1 ms | 133,4 ms |
| 10k × 768 embedding, sayfalı worker sıralama | 135,4 ms | **11,9 ms** |

[Arama ölçümü](/home/erkanoz/projeler/iptv/lifeos-iptv-player/docs/release-audit-2026-10-09/search-benchmark.json), [embedding ölçümü](/home/erkanoz/projeler/iptv/lifeos-iptv-player/docs/release-audit-2026-10-09/embedding-benchmark.json). Mevcut worker yaklaşımı ana iş parçacığına yükü azaltıyor; ham arama süresinin her durumda daha kısa olduğu iddia edilemez. İndeks hazır olma süresi ve indekssiz ilk kurulum/typo deneyimi özellikle düşük güçlü TV'de ölçülmeli.

Olumlu mevcut korumalar: hesap/profil kapsamlı ilerleme, typed arama kimliği, gizli/yetişkin filtreleri, marker backup desteği, seek controller, TV error/timeout ve stream generation kontrolleri, focus registry ve bounded grid. Katalog enrichment/embedding runner'ları oynatma aktifken duruyor; her ayar değişikliğinde ağır AI çalışıyor gibi genel bir iddia doğru olmaz.

## Platform ve özellik kapsamı

| Alan | İncelemede görülen durum | Yayın öncesi ek kanıt |
|---|---|---|
| Linux player | media_kit + yerel grafik düzeltmeleri; testler geçti | X11/Wayland, mini/tam ekran döngüsü, 30/60 fps, donanım decode, çoklu monitör |
| Windows | kaynak/native plugin ve ZIP işi var | Gerçek Windows derlemesi, codec/texture/window resize, kurulum/imza, DPI125/150/200, sleep/resume |
| macOS | kaynak ve unsigned build kontrol işi var; F09/F10 eksik | Apple Silicon/Intel hedef seçimi, signed sandbox release, fullscreen/Spaces, LAN/file picker, dağıtım doğrulaması |
| iPhone/iPad | iOS plist izinleri var; unsigned CI kontrolü | Gerçek cihaz, notch/rotation, background audio, file picker, Cast/LAN, düşük bellek, signed archive |
| Android telefon | media_kit yolu | Surface/rotation, background, ses odağı, multi-window, eski/yeni cihaz codec matrisi |
| Android TV | video_player/ExoPlayer; ses/altyazı/EPG/pause panel kodu mevcut | F05/F06, bütün route ilk odakları, bozuk kanal sonrası zap, 720p/1080p/4K mantıksal ölçüler |
| Xtream/M3U/XMLTV | parser, ID, catchup, sync ve büyük liste testleri var | Gerçek sağlayıcı fixtures, HLS/TS redirects/header/token, kötü cevap, reconnect, sync sırasında oynatma |
| Fragman | uygulama içi player, request/timeout/error/retry kodu var | Gerçek YouTube extraction değişimleri, sesli stream, bölge engeli, iptal ve yeniden deneme; servis bağımlılığı sürüyor |
| Ses/altyazı | tercih eşleştirici ve TV native track erişimi var | Çoklu ses/forced/SDH, dil kodu/etiket farkı, bölüm değiştirme; codec ve embedded/external farklı yolları |
| AI platform eşitliği | geminiServiceProvider Android TV'de tamamen null; voice sadece mobile; reminder sadece Android/iOS | Performans gerekçesiyle verilen bu kararlar ürün vaadinde açık olmalı; desktop reminder aracı sunulmamalı veya backend eklenmeli |
| Çoklu dil | ARB anahtarları eşit; F08/F16 kusurları var | RTL fiziksel yönler vs mantıksal panel yönleri, uzun Almanca/Rusça metin, Arapça font/semantics, %150/200 text scale |

Canlı kanal için “stream yüklenmedi” tek başına codec teşhisi değildir. HTTP status/redirect/TLS/header, manifest/segment erişimi, demuxer, decoder ve render hataları ayrı sınıflandırılmalı. Kullanıcının Nat Geo Wild örneği için bu turda gerçek stream/cihaz logu yok; yeni bir codec hatası kanıtlanmış sayılmadı. Sağlayıcı parolalarını ve token'ları redakte eden tanı paneli yararlı olur.

UI/focus kabul senaryosu: ana menü→Filmler/Diziler→Tümü→ilk grid hücresi→detay→Oynat/Devam Et→player→detay→grid→kategori→ana menü; aynı akış arama sonucundan ve canlı kanal/EPG panelinden de tekrarlanmalı. Bozuk içerik, dialog kapatma, hesap/profil/dil değişimi ve liste yenilenmesi sırasında ilk odak görünür ve etkin bir hedefte kalmalı. Sağ/sol seek ile focus traversal birlikte tetiklenmemeli. Mevcut ayrı controller testleri bu tam route zincirini tek başına kanıtlamıyor.

## Uygulama sırası ve yayın kapısı

1. F01 imza materyali ve F02 dağıtım hattı; her platform için test edilebilir güvenli paket oluştur.
2. F05/F06 bölüm/session ve TV eşitliği; F07 detay yarışını düzelt. Bu paketle player/focus tam akış testi yap.
3. F13/F14 doğrulanmış intro modeli ve TV kumanda arayüzü; F15 marker senkronizasyonu.
4. F03/F04/F11/F18/F19 Gemini 3.8 ortak istemci, araç sözleşmesi, iptal ve doğru içerik kimliği; eval ile kaliteyi ölç.
5. F08/F16/F17 locale/tema tutarlılığı; F09/F10 Apple izinleri; F12 şifreli eş cihaz aktarımı; F20 recency havuzu.
6. Gerçek platform matrisi tamamlanır: temiz kurulum, mevcut kullanıcıdan güncelleme, backup/restore, çoklu hesap/profil, kötü ağ ve uzun oynatma. Açık P0/P1 ve doğrulanmamış dağıtım hedefi varken tüm platformlar hazır ilan edilmez.

Önerilen performans kabul hedefleri ölçülmüş garanti değildir: indeksli yerel arama p95≤100 ms; ilk görünür odak ilk kullanılabilir frame'de; 60 Hz UI frame p95≤16,7 ms / 30 Hz TV≤33,3 ms; bölüm geçişinde route kapanması yok; geçişin network/decoder süreleri ayrı ölçülür. 30–60 dakika VOD/canlı oynatma ile dropped-frame, A/V sync, CPU/GPU/RSS, kanal değiştirme ve küçük/tam ekran döngüleri cihaz bazında kaydedilmeli.

Tekrarlama komutu:

```sh
flutter test --no-pub --reporter=expanded docs/release-audit-2026-10-09/audit_probe_test.dart docs/release-audit-2026-10-09/catalog_benchmark_test.dart docs/release-audit-2026-10-09/embedding_benchmark_test.dart
```
