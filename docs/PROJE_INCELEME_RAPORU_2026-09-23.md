# LifeOS IPTV Player — Ayrıntılı teknik inceleme ve iyileştirme raporu

**Tarih:** 23 Eylül 2026  
**İncelenen sürüm:** yerel `main`, `4b5f714`; uygulama `1.13.2+2083`, DB şeması 23. GitHub `360bd64` yalnızca önceki inceleme belgesini ekliyor; uygulama kodu farkı yok.  
**İnceleme türü:** kaynak ve platform yapılandırması analizi, mevcut testler, izole hata deneyleri, sentetik M3U ölçümü ve Linux release derlemesi.

## Sonuç ve öncelik

Proje geniş bir özellik kümesine sahip, fakat bugün beş platformda “kusursuz çalışıyor” denebilecek durumda değil. En büyük sorun yalnızca görsel performans değil: **hesap/başlık kimliğinin tutarlılığı, senkronizasyonun hata ve iptal modeli, oynatıcı/pencere durum yönetimi ve özelliklerin platformlar arasında eksik uygulanması.**

İlk düzeltme sırası:

1. Hesap geçişi ve yedekte veri kaybını engelle; hesap/profil/içerik kimliğini tutarlı hale getir.
2. Sınırsız timeout tekrarını durdur; senkronun gerçek sonucu, iptali ve ortak kilidini düzelt.
3. Fullscreen/PiP/always-on-top için tek durum makinesi kur; gerçek native olaylarla doğrula.
4. M3U kimlik çakışması, VOD ilerleme kimliği ve Xtream URL/uzantı sorunlarını çöz.
5. iOS izinleri, PiP/Bonjour, Android sistem çubukları ve Apple CI eksiklerini tamamla.
6. Arama indeksini, AI kimlik/görünürlük kurallarını ve arka plan iş bütçesini düzelt.

**Ana bulgu sayısı:** 42 (26 P1, 16 P2). Bunlara ek olarak platform kabul matrisi ve bakım gözlemleri verilmiştir.

**P1:** veri kaybı/yanlış veri, oynatma veya temel akışın kilitlenmesi, korunan profile izinsiz geçiş ya da platformu kullanılamaz hale getiren risk. **P2:** önemli kalite, performans veya ikincil özellik eksikliği. Öncelik, cihazda görülme sıklığı ölçümü değildir.

## Kapsam, kanıt ve sınırlar

Envanter: üretilmiş Dart ve yerelleştirme çıktıları hariç **140 Dart dosyası / 61.226 satır**, **21 test dosyası**. Hesap, katalog/EPG/LAN senkronu, yerel DB, arama/AI, player/PiP, ayarlar/profiller, altyazı/cast, Android/iOS/macOS/Linux/Windows yapılandırması ve CI yürütme yolları incelendi. Üretilmiş dosyalar satır satır bağımsız denetimden geçirilmedi; envanter boyutu her satırın test edildiği anlamına gelmez.

Bu çalışma düzeltme uygulaması değildir. Uygulama kaynak kodu ve kullanıcı verisi değiştirilmedi; rapor ve tanı kanıtları eklendi. Gerçek sağlayıcı hesabına giriş yapılmadı, ücretli AI çağrısı yapılmadı. Native oynatma ve pencere davranışı fiziksel Android/iPhone/Windows/macOS cihazlarında denenmedi. Linux derlemesi başarılıdır; bu sonuç gerçek medya oynatma ve pencere testi yerine geçmez. “Koddan doğrulandı” davranışın kaynağını; “cihazda test gerekli” ise belirti/performansın çalışma zamanında ayrıca ölçülmesi gerektiğini belirtir.

İlk test denemesi `.dart_tool/package_config.json` içindeki artık geçerli olmayan Flutter yolu nedeniyle başarısız oldu; bu uygulamadaki binlerce derleme hatası olarak sayılmadı. `flutter pub get` ile yollar yenilendi. Kurulu **Flutter 3.47.2 / Dart 3.13.2**, SDK pinleri nedeniyle 7 bağımlılığı değiştirdi. Aşağıdaki doğrulamalar bu çözümlemeyle yapıldı; mevcut kilit dosyasının birebir bağımlılık setiyle başarı iddiası yoktur. Çözülmüş kilit kanıtlarda saklandı, kullanıcının önceki `pubspec.lock` ve analiz ayarı geri korundu.

## Çalıştırılan doğrulamalar

| Doğrulama | Sonuç | Ne kanıtlar? |
|---|---|---|
| `flutter test --no-pub --reporter=expanded` | **223/223 geçti**, yaklaşık 23 sn test yürütme | Mevcut testlerin kapsadığı davranış |
| `flutter analyze --no-pub` | **0 error, 6 warning, 26 info** | Statik analiz; 32 bulgu nedeniyle katı komut başarılı exit üretmez |
| `flutter build linux --release --no-pub` | **Başarılı** | Bu Linux ortamında release derlenebilirlik; sqlite C kodunda 2 derleyici uyarısı |
| 6 ek tanı testi | **6/6 geçti** | Mevcut hatalı davranışları yeniden üretti; “ürün düzeldi” testi değildir |
| M3U sentetik benchmark | Aşağıdaki ölçümler | Ağ/SQLite/medya hariç parse+model+ID CPU maliyeti |

Altı tanı: gerçek hash çakışması; tırnaklı virgül isim hatası; M3U/player ID uyuşmazlığı; `#` içeren parola URL’si; iki SyncMetadata kilidinin birlikte alınması; gerçek Xtream istemcisinin iki timeout sonrasında üçüncü istek göndermesi.

| Sentetik satır | Metin boyutu | 3 çalıştırma medyanı | Kimlik çakışması |
|---:|---:|---:|---:|
| 1.000 | 91.478 bayt | 14 ms | 0 |
| 10.000 | 944.678 bayt | 94 ms | 0 |
| 50.000 | 4.856.678 bayt | 455 ms | 2 |
| 100.000 | 9.746.678 bayt | 919 ms | 7 |

Ölçüm bu makinede Dart JIT ile yapıldı, sonuçlar telefon/TV ve Flutter release p95’i değildir. Süreye `parseM3URaw`, `buildParseResult` ve ID üretimi dahil; ağ ve DB hariç. Benchmark süreç RSS’i 100 bin aşamasında yaklaşık 325 MiB idi; JIT, önceki çalıştırmalar ve test girdileri dahil olduğundan bunu uygulamanın gerçek tepe belleği diye yorumlamamak gerekir.

## Özellik envanteri ve değerlendirme

| Alan | Mevcut yapı | Başlıca açık |
|---|---|---|
| Xtream hesap/giriş | Normalize/authenticate, kayıtlı ve varsayılan hesap | Timeout döngüsü, aktif-varsayılan çelişkisi, URI/uzantı |
| M3U | URL indirme, tür/grup ayırımı, hash ID, XMLTV URL | Kimlik çakışması, dizi modeli ve resume, HTTP başlıkları |
| Katalog senkronu | Kategoriler + canlı/film/dizi; 500’lük batch; delta/full | Hata yutma, iptal yok, ortak kilit yok, metadata kaybı |
| Canlı/EPG/catch-up | Xtream + XMLTV, program rehberi, kanal geçişi | Bellek TTL, transaction, saat dilimi/yetenek doğrulaması |
| VOD/dizi | Resume, önceki/sonraki, intro, sezon izlendi, uyku | URL/kimlik, seek yoğunluğu, episode parse, backend farkı |
| Video kalitesi | GPU tespiti, hwdec, buffer, HLS bitrate, fit | Ayarların backend/format yetenekleriyle eşlenmesi |
| Masaüstü pencere | Fullscreen, pin, PiP, sürükle/boyutlandır | Gerçek durum onayı ve PiP restore |
| Cast/DLNA | Keşif, bağlantı, LOAD ve temel kontrol | VOD pozisyon devri, codec/tek bağlantı cihaz matrisi |
| Altyazı/ses | Dil hatırlama, harici arama, SRT→VTT, görünüm | İndirme timeout, hata türü, platform render testi |
| Favori/listem/geçmiş | Profil bazlı repository’ler | Hesap kapsamı ve yedek/cihazlar arası kimlik |
| Profil/ebeveyn | Profil seçici, PIN, isKids, adult kategori filtresi | AI üzerinden PIN atlama; tutarlı erişim politikası |
| Arama | Türkçe normalizasyon, SQL LIKE, fuzzy, AI rerank | İndeks güncelliği, kısmi indeks, boş sorgu yarışı |
| AI öneri | Sana özel, ruh hali, grup, haftalık özet, hero | ID/görünürlük, kalite ölçümü ve cache kapsamı |
| AI metin/sohbet | Konu zenginleştirme, çeviri, recap, oyuncu bilgisi, araçlar | Kaynak/güven, spoiler eval, eylem denetimi, iOS ses |
| Embedding | Katalog üretimi, lokal benzerlik, sohbet retrieval | Tam tarama bellek/CPU, source/model version, task type |
| Cihaz senkronu | mDNS, manuel seçim, otomatik favori/geçmiş | Hesap/profil, şifreleme, silme/listem, Bonjour |
| Yedek/geri yükle | JSON ve dosya seçici | Çok profil, kimlik eşleme, sırlar, iki depo atomikliği |
| Tema/dil/erişilebilirlik | Dark/light/system, 8 dil, D-pad | Sabit Türkçe hata metinleri, tooltip/semantics, büyük font/RTL |
| Paketleme/güncelleme | Linux/Windows/Android CI artifact | Apple işleri yok, Android imza kökü, sürüm sabitleme |

Olumlu temeller: Xtream JSON için background transformer; API cache + istek kuyruğu; Türkçe normalizasyon; profil bazlı repository filtreleri; D-pad odak testleri; player pozisyon UI güncellemelerini sınırlama; donanım hızlandırma kaçış ayarı; mobil fragman varsayılanını azaltma; kullanıcı seçtiği yere yedek dışa aktarma. İyileştirme sırasında bunları korumak gerekir.

## Bulgular

### B01 — Zaman aşımı yeniden denemesi sınırsız zincire dönüşüyor

**P1 · Deneyle doğrulandı**  
**Kanıt:** [lib/data/datasources/remote/xtream_api_service.dart:316](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/datasources/remote/xtream_api_service.dart:316) · [lib/presentation/screens/auth/xtream_login_screen.dart:125](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/auth/xtream_login_screen.dart:125)

Dio hata yakalayıcısı aynı RequestOptions ile dio.fetch çağırıyor; deneme sayacı yok. Yeni zaman aşımı aynı yakalayıcıya yeniden giriyor. Yerel sahte sunucuda ilk iki istek yanıtsız bırakıldı: gerçek uygulama istemcisi yaklaşık 60 saniye sonra üçüncü isteği gönderdi. Sunucu hiç düzelmezse kodda toplam süre sınırı bulunmuyor. Giriş senkronizasyonunda canPop=false olduğundan kullanıcı geri de dönemiyor; tekil API kuyruğu da bu çağrıyı bekleyebiliyor.

**Öneri:** En fazla 1–2 tekrar, toplam işlem süresi bütçesi, CancelToken ve kullanıcıya çalışan iptal düğmesi ekle. İptal/zaman aşımı/kısmi başarı durumlarını ayrı taşı. 429 için Retry-After ve rastgele gecikmeli geri çekilme kullan.

**Kabul testi:** Sürekli timeout veren sunucuya karşı toplam süre ve istek sayısı sınırlı kalmalı; İptal, kuyruktaki ayrıntı isteğini serbest bırakmalı.

### B02 — Senkronizasyon başarısız olsa da tamamlandı ve güncel sayılabiliyor

**P1 · Koddan doğrulandı**  
**Kanıt:** [lib/data/services/sync_service.dart:104](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/sync_service.dart:104) · [lib/data/services/sync_service.dart:220](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/sync_service.dart:220) · [lib/data/services/sync_service.dart:951](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/sync_service.dart:951)

_syncStreams ve sayım yolları hatayı yutuyor. syncAllWithProgress sonunda isDone=true üretiyor; runTieredSync başarısız bölümden sonra da markTierSynced yazabiliyor. Gerçek tam yenileme TTL değeri 24 saat; bazı yorumlarda 6 saat yazıyor. Böylece ağ/SQL hatası, boş içerik veya eski katalogla birlikte uzun süre gizlenebilir.

**Öneri:** SyncResult içinde aşama bazında başarı, hata, öğe sayısı, süre ve yeniden deneme bilgisi döndür. Başarılı aşamanın zamanını güncelle; kısmi sonuçları başarı gibi sunma. İndirme/doğrulama/uygulama/arama indeksi aşamalarını ayrı raporla.

**Kabul testi:** Film isteği 500, diziler başarılı olan senaryoda sonuç kısmi olmalı; film yenileme zamanı ilerlememeli ve eski sağlam katalog korunmalı.

### B03 — Hesap değiştirmek tüm profillerin favori ve geçmişini siliyor

**P1 · Koddan doğrulandı**  
**Kanıt:** [lib/data/repositories/auth_repository_impl.dart:223](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/repositories/auth_repository_impl.dart:223) · [lib/presentation/screens/settings/settings_screen.dart:530](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/settings/settings_screen.dart:530) · [lib/data/datasources/local/tables.dart:55](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/datasources/local/tables.dart:55)

Hesap değişiminde channels/categories/programs yanında favorites/watchlist/playbackProgress/seriesTracking tabloları tamamen siliniyor. İçerik ve kullanıcı tablolarında accountId yok. Üstelik contentEnrichment, embeddings, AI önbellekleri ve categoryPrefs aynı temizliğe dahil değil: A hesabındaki ID, B hesabında farklı içerikle eşleşebilir. Silme işlemleri tek transaction içinde de değil.

**Öneri:** Account + içerik türü + sağlayıcı ID üzerinden kalıcı içerik kimliği oluştur. Kullanıcı verisini hesap ve profile bağla. Hesap geçişinde silme yerine bağlam değiştir; eski senkronizasyon işlerini iptal et. AI ve kategori tercihlerini de aynı kimlikle kapsamlandır.

**Kabul testi:** A→B→A geçişinde iki hesabın tüm profillerindeki favori, geçmiş ve gizli kategori seçimleri korunmalı; aynı sayısal ID farklı içerikse karışmamalı.

### B04 — Yeni hesap ile varsayılan hesap farklı kalabiliyor

**P1 · Koddan doğrulandı**  
**Kanıt:** [lib/presentation/state/auth_provider.dart:16](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/state/auth_provider.dart:16) · [lib/presentation/screens/auth/xtream_login_screen.dart:65](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/auth/xtream_login_screen.dart:65) · [lib/presentation/screens/auth/m3u_upload_screen.dart:57](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/auth/m3u_upload_screen.dart:57)

currentAccountProvider öncelikle settings.defaultAccountId kullanıyor. Yeni hesap ekleme akışı DB’de yeni hesabı aktif yapıp onun kataloğunu indiriyor, fakat var olan defaultAccountId değerini değiştirmiyor. Önceden A varsayılan seçilmişken B eklenirse ekrandaki B kataloğuna A sunucusunun oynatma bilgileri uygulanabilir.

**Öneri:** Aktif hesap için tek otorite kullan. Yeni hesap eklemenin yalnızca kaydetmek mi, etkinleştirmek mi olduğu açık olsun; etkinleştirme, settings/DB/provider/sync bağlamını birlikte güncellesin.

**Kabul testi:** A varsayılan iken B ekle; katalog, oynatma URL’si ve hesap etiketi aynı hesaba ait olmalı.

### B05 — Yedekleme çoklu profili ve hesap kimliği eşlemesini korumuyor

**P1 · Koddan doğrulandı**  
**Kanıt:** [lib/data/services/backup_service.dart:43](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/backup_service.dart:43) · [lib/data/services/backup_service.dart:169](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/backup_service.dart:169) · [lib/data/services/backup_service.dart:275](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/backup_service.dart:275)

Yedek profiles tablosunu ve favori/geçmiş/listem satırlarının profileId değerlerini dışa aktarmıyor. İçe aktarım bütün satırları varsayılan profile yazar. Aynı içeriğin iki profilde favori olması geri yüklemede benzersiz anahtar çakışmasına yol açabilir. Hesap ID dışa aktarılıyor ama içe aktarımda kullanılmıyor; defaultAccountId ve hesap bazlı EPG ayarları yeniden eşlenmiyor. DB transaction sonrasında SharedPreferences ayrıca yazıldığı için bütün geri yükleme atomik değil.

**Öneri:** Sürümlü yedek şeması, profil ve hesap kimliği eşleme tablosu, import ön doğrulaması ve geri dönüş günlüğü ekle. Eksik tabloları belirt; tercihlerde eski ID’leri dönüştür. Secrets ve cihaz kimliği/trust token’larını varsayılan genel yedekten ayır.

**Kabul testi:** İki hesap, üç profil, aynı içerik favorileri ve EPG URL’leriyle export→temiz kurulum→import round-trip testi; bozuk dosyada mevcut veri tamamen korunmalı.

### B06 — M3U kanal kimliklerinde gerçek çakışma var

**P1 · Deneyle doğrulandı**  
**Kanıt:** [lib/data/services/m3u_parser.dart:19](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/m3u_parser.dart:19) · [lib/data/services/sync_service.dart:379](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/sync_service.dart:379)

URL+isim FNV hash’i 31 bite daraltılıyor ve doğrudan primary key olarak kullanılıyor. https://example.invalid/18310.ts + Channel 18310 ile /33232.ts + Channel 33232 aynı 799436981 değerini üretiyor. Aynı türde insertOrReplace ikinci kanalı birincinin üzerine yazar. 100 bin satırlı sentetik örnekte 7 çakışma ölçüldü. Kod yorumundaki 100 bin için %0,001 iddiası yanlış; düzgün dağılmış 31 bit uzay varsayımında en az bir çakışma olasılığı yaklaşık %90’dır. URL token’ı veya isim değişince kimlik de değişir.

**Öneri:** DB tarafından verilen yerel ID + hesap bazlı doğal kimlik eşleme tablosu kullan. Güçlü hash kullanılsa bile tam anahtar eşitliğiyle çakışmayı kontrol et. tvg-id/provider ID ve isim/URL değişimi için kontrollü eşleme uygula; eski favorileri taşı.

**Kabul testi:** Verilen iki örnek ayrı satır kalmalı; 100 bin içerik importunda satır kaybı olmamalı; URL token’ı ve ad yenilendiğinde geçmiş korunmalı.

### B07 — M3U VOD kaldığın yerden devam kimliğiyle uyuşmuyor

**P1 · Deneyle doğrulandı**  
**Kanıt:** [lib/presentation/screens/player/video_player_screen.dart:1272](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/video_player_screen.dart:1272) · [lib/presentation/screens/player/video_player_screen.dart:1327](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/video_player_screen.dart:1327) · [lib/presentation/screens/player/tv_video_player_screen.dart:238](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/tv_video_player_screen.dart:238)

Oynatıcı içerik kimliğini URL son parçasını int’e çevirerek buluyor. movie.mp4 gibi isimde sonuç null; 123.mp4 olsa bile M3U’nun hash kimliği 123 değildir. İlerleme hiç kaydedilmez veya katalog satırıyla birleşmez. İki oynatıcıda da aynı yaklaşım var.

**Öneri:** Route’a accountId, contentId, contentType ve episodeId taşı; URL’yi yalnızca taşıma adresi olarak kullan. Kaydetme ve geri çağırma aynı PlaybackIdentity üzerinden yürüsün.

**Kabul testi:** Metin dosya adı, sayısal dosya adı, imzalı URL ve uzantısız URL ile M3U VOD aç/kapat/yeniden aç; aynı içerik ve saniyeye dönülmeli.

### B08 — M3U dizi içerikleri için tam oynatma akışı eksik

**P1 · Koddan doğrulandı**  
**Kanıt:** [lib/presentation/screens/series/series_screen.dart:410](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/series/series_screen.dart:410) · [lib/presentation/screens/series/series_screen.dart:446](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/series/series_screen.dart:446)

Parser bir M3U kaydını series olarak sınıflandırabiliyor. Dizi ekranı M3U hesapta boş episodes ve seasons içeren temel bilgi oluşturup dönüyor. Bu akışta kayıtlı doğrudan bölüm URL’sini dizi bölümüne dönüştüren bir model bulunmuyor; kart listelenmesi bölümün oynatılabilir olduğu anlamına gelmiyor.

**Öneri:** M3U dizilerinde SxxExx/season/episode alanlarından seri-sezon-bölüm modeli üret; tanınamayan içerik için doğrudan oynatılabilir tek bölüm sun. Xtream API zorunluluğunu sağlayıcı adaptörünün dışında bırak.

**Kabul testi:** Tek bölümlük M3U, çok sezonlu liste ve belirsiz bölüm isimleri için karttan oynatmaya kadar uçtan uca test.

### B09 — Film oynatma URL’sinde .mkv sabitlenmiş

**P1 · Koddan doğrulandı**  
**Kanıt:** [lib/presentation/screens/movies/movies_screen.dart:330](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/movies/movies_screen.dart:330) · [lib/utils/stream_url_builder.dart:26](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/utils/stream_url_builder.dart:26)

Film ekranı ve ortak URL oluşturucu bütün Xtream filmlerini .mkv ile açıyor. Sağlayıcının container_extension veya direct_source bilgisi kullanılmıyor. Gerçek kaynağı mp4/avi olan ve uzantıyı önemseyen sunucularda oynatma başarısız olur; tekrar deneme aynı yanlış URL’yi açar.

**Öneri:** Tipli Movie/StreamDescriptor modeliyle containerExtension, directSource ve HTTP başlıklarını koru. Öncelik sırası doğrulanmış doğrudan kaynak→sağlayıcı uzantısı→sınırlı kontrollü fallback olsun.

**Kabul testi:** mp4/mkv/avi ve doğrudan kaynak döndüren sahte Xtream sunucusunda doğru adresin istendiğini doğrula.

### B10 — URL birleştirme özel karakterli hesaplarda bozuluyor

**P1 · Deneyle doğrulandı**  
**Kanıt:** [lib/utils/stream_url_builder.dart:20](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/utils/stream_url_builder.dart:20) · [lib/data/datasources/remote/xtream_api_service.dart:47](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/datasources/remote/xtream_api_service.dart:47) · [lib/data/repositories/auth_repository_impl.dart:112](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/repositories/auth_repository_impl.dart:112)

Kullanıcı adı/şifre düz metin olarak URL yoluna ekleniyor. p#q şifresi deneyi fragment oluşturdu: sunucuya gönderilecek path /movie/user/p olarak kesildi. normalizeUrl bütün alt yolları atıyor; alt dizinde çalışan panel desteği kayboluyor. Her username/password içeren M3U URL’si doğrulama başarısız olsa bile Xtream hesabına dönüştürülüyor.

**Öneri:** Uri(pathSegments: ...) ve queryParameters kullan; normalizeUrl ile sağlayıcı taban yolunu açıkça modelle. M3U→Xtream dönüşümünü yetenek kontrolüne bağla; API desteklenmiyorsa özgün playlist kaynağına geri dön.

**Kabul testi:** #, ?, /, @, Unicode ve boşluk içeren sentetik kimlik bilgileri; alt yol ve IPv6 host; yalnızca M3U sunan get.php bağlantısı.

### B11 — Tam ekran geçişinde istenen durum gerçek pencere durumu sanılıyor

**P1 · Koddan doğrulandı; cihazda tekrar üretim gerekli**  
**Kanıt:** [lib/presentation/screens/player/video_player_screen.dart:2837](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/video_player_screen.dart:2837) · [lib/presentation/screens/player/video_player_screen.dart:1670](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/video_player_screen.dart:1670) · [lib/presentation/screens/player/video_player_screen.dart:389](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/video_player_screen.dart:389)

_setFullscreen çağrı dönüşünde yerel bool’u hedef değere çeviriyor; native enter/leave olayları dinlenmiyor, seri geçiş kilidi yok. macOS eklentisi toggleFullScreen ile asenkron animasyon başlatıyor; Linux GTK isteğinin kabul edilmesi son durum garantisi değil. Dışarıdan pencere tam ekranı değişirse ESC davranışı ve dispose temizliği eski bool’a göre karar verir. Tam ekran çıkamama şikâyetinin güçlü aday nedeni; fiziksel cihazda tek kök neden olarak doğrulanmadı.

**Öneri:** Pencere durumunu tek controller yönetsin: normal/entering/fullscreen/leaving/pip. Native olaylarla onayla, geçişleri sırala, timeout ve geri kazanım koy. ESC, geri, çift tıklama, işletim sistemi düğmesi aynı komut yolunu kullansın.

**Kabul testi:** Her masaüstünde F/ESC/çift tıklama ve OS tam ekranını 100 döngü; geçiş ortasında kapat, minimize et, ekran değiştir. Hiçbir döngü çıkışı kilitlememeli.

### B12 — PiP boyutu ve eski pencere durumunun geri yüklenmesi tutarsız

**P1 · Koddan doğrulandı; pencere yöneticisi testi gerekli**  
**Kanıt:** [lib/main.dart:77](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/main.dart:77) · [lib/presentation/widgets/player/pip_state.dart:112](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/widgets/player/pip_state.dart:112) · [lib/presentation/widgets/player/pip_state.dart:139](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/widgets/player/pip_state.dart:139) · [lib/presentation/screens/player/video_player_screen.dart:2721](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/video_player_screen.dart:2721)

Ana pencere minimum 900×500; PiP 380×230 istiyor, minimum sınırı kaldırmıyor. Sınırı uygulayan sistemlerde mini pencere beklenen boyuta inemez. Yalnızca boyut/konum saklanıyor; maximize/fullscreen ve önceki always-on-top korunmuyor. Geri yükleme her zaman always-on-top=false yazıyor. Ekran çalışma alanı yerine eski pencere koordinatlarından konum hesaplanıyor.

**Öneri:** Geçiş öncesi tüm WindowSnapshot değerlerini sakla; PiP’te minimum boyutu düşür ve restore’da geri koy. Native fullscreen/maximize çıkışını bekle. Monitörün workArea/DPI bilgisini kullan. PiP’e giriş başarısızlığını sessizce başarı olarak bırakma.

**Kabul testi:** Normal/maximize/fullscreen/pinned durumlarından PiP→genişlet/kapata geç; boyut, konum, minimum boyut ve pin önceki haline dönmeli. Çok monitör ve %150/%200 DPI testleri.

### B13 — Sürekli üstte düğmesi gerçek başarıyı doğrulamıyor

**P1 · Koddan doğrulandı; OS davranışı ayrıca ölçülmeli**  
**Kanıt:** [lib/presentation/screens/player/video_player_screen.dart:2861](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/video_player_screen.dart:2861) · [lib/presentation/widgets/player/pip_state.dart:141](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/widgets/player/pip_state.dart:141)

Pin düğmesi yalnızca setAlwaysOnTop exception atarsa gerçek durumu sorguluyor; başarılı çağrıyı pencerenin gerçekten üstte olduğu kabul ediyor. Başlangıç pin durumu da okunmuyor. Kurulu window_manager 0.5.1 Linux kodu GTK keep_above isteği ardından kendi bool’unu döndürüyor; bu değer compositor’un gerçekten uyguladığını kanıtlamaz. PiP geri dönüşü ayrıca pin’i kaldırıyor.

**Öneri:** Pin tercihini merkezi pencere controller’ına taşı; destek/yetersiz destek bilgisini ayır. Pin’in normal pencereler üzerinde kalma anlamını netleştir. Linux X11/Wayland ve macOS Spaces için ayrı kabul testi yap; başarısızlığı UI’da göster.

**Kabul testi:** Pini açıp başka normal uygulamaya odaklan; küçük/tam/PiP döngüsünden sonra tekrar dene. Windows, macOS, Linux X11 ve Wayland sonuçları ayrı kaydedilmeli.

### B14 — Oynatıcı açılışı iptal ve hata yönetimi açısından eksik

**P1 · Koddan doğrulandı**  
**Kanıt:** [lib/presentation/screens/player/video_player_screen.dart:349](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/video_player_screen.dart:349) · [lib/presentation/screens/player/video_player_screen.dart:854](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/video_player_screen.dart:854) · [lib/presentation/screens/player/video_player_screen.dart:985](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/video_player_screen.dart:985)

_initPlayer fire-and-forget çalışıyor; GPU sorgusu ve çok sayıda native await sonrasında mounted/oturum kimliği kontrolü yok. Ekrandan erken çıkışın ardından disposed player üzerinde ayar/open/listener kurulumu denenebilir. Başlatma işlemini kapsayan hata durumu yok ve stream.error aboneliği attachStreamListeners içinde bulunmuyor. Yalnızca buffering 20 saniye sürerse hata paneli açılması bütün arızaları kapsamaz.

**Öneri:** PlaybackSession yaşam döngüsü ve generation token kullan. Her async dönüşte oturumun geçerliliğini kontrol et; init/open/error/stop/dispose işlemlerini sırala. Codec/network/native-property hatalarını sınıflandır; denenmeyen özellik tüm init’i durdurmasın.

**Kabul testi:** Yavaş GPU sorgusu ve yavaş open sırasında hızlı geri/yeniden aç; artık ses, sızan decoder, disposed çağrı ve yakalanmamış Future hatası oluşmamalı.

### B15 — VOD kaydırma sürüklemesi çok sayıda gerçek seek üretiyor

**P2 · Koddan doğrulandı; gecikme ölçümü gerekli**  
**Kanıt:** [lib/presentation/screens/player/video_player_screen.dart:3976](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/video_player_screen.dart:3976) · [lib/presentation/screens/player/video_player_screen.dart:3733](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/video_player_screen.dart:3733) · [lib/presentation/screens/player/video_player_screen.dart:1636](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/video_player_screen.dart:1636)

Slider.onChanged her hareketi player.seek’e gönderiyor. Uzak VOD’da peş peşe HTTP seek, decoder flush ve buffer yenilemesi oluşabilir. D-pad için bulunan 400 ms biriktirme yaklaşımı mouse/touch slider’da yok. ±10 saniye düğmeleri de sınır kontrolü yapmıyor; mobile double-tap yolu ise clamp kullanıyor.

**Öneri:** Sürükleme sırasında yalnızca önizleme pozisyonunu güncelle, onChangeEnd ile tek seek yap. Tüm seek girişlerini ortak clamp/throttle denetleyicisinde topla; canlı/seek edilemez akışta kontrolü kapat.

**Kabul testi:** 2 saniyelik sürüklemede tek son seek; 0 ve süre sonu sınırları; range desteği olmayan sunucuda açık geri bildirim.

### B16 — Android TV oynatıcı özellik ve yaşam döngüsü eşitliği sağlamıyor

**P1 · Koddan doğrulandı**  
**Kanıt:** [lib/presentation/screens/player/tv_video_player_screen.dart:24](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/tv_video_player_screen.dart:24) · [lib/presentation/screens/player/tv_video_player_screen.dart:113](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/tv_video_player_screen.dart:113) · [lib/presentation/screens/player/tv_video_player_screen.dart:238](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/tv_video_player_screen.dart:238)

TV farklı video_player motoruna yönleniyor; ekran açıklaması da EPG/kanal listesi/altyazı/cast katmanlarının sonraki aşama olduğunu söylüyor. Mobile/desktop settings’in hwdec/buffer/kalite uygulama mantığı bu ekranda yok. WidgetsBindingObserver ile arka plan politikası bulunmuyor. _open eski controller dispose’unu await ederken yeniden çağrılırsa sıralama bozulabilir; startAt sonrası play öncesinde de oturum tekrar doğrulanmıyor.

**Öneri:** Ortak PlayerCapabilities ve PlaybackSession sözleşmesi oluştur. TV backend’inin desteklediği ayarları uygula, desteklemediklerini etkin göstermeme. Kanal geçişini son istek kazanır mantığıyla sırala; arka planda ses ve kayıt davranışını açıkça yönet.

**Kabul testi:** Hızlı 20 kanal geçişi, Home/geri, ağ kopması, VOD devam, altyazı ve sonraki bölüm için gerçek düşük donanımlı TV testi.

### B17 — iPhone sesli yapay zekâ izinleri eksik

**P1 · Kod ve resmi platform belgesiyle doğrulandı**  
**Kanıt:** [ios/Runner/Info.plist:1](/home/erkanoz/projeler/iptv/lifeos-iptv-player/ios/Runner/Info.plist:1) · [lib/data/services/voice_chat_service.dart:39](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/voice_chat_service.dart:39)

Servis iOS’ta speech_to_text.initialize çağırıyor, fakat Info.plist içinde NSSpeechRecognitionUsageDescription ve NSMicrophoneUsageDescription yok. Mikrofon/konuşma izni akışı tamamlanmış sayılmaz; native izin erişimi uygulamanın sonlandırılmasına kadar gidebilir. Dart catch native privacy termination için çözüm değildir.

**Öneri:** Yerelleştirilmiş kullanım açıklamalarını ekle; ilk kullanım, reddetme ve Ayarlar’dan tekrar izin verme akışını tamamla. Native paket/izin konfigürasyonunu release hedefinde doğrula.

**Kabul testi:** Temiz iPhone kurulumunda izin ver/reddet/kalıcı reddet/geri aç senaryoları; mikrofon kapalıyken metin sohbeti çalışmaya devam etmeli.

### B18 — iOS PiP uygulanmamış; cihaz senkronu Bonjour bildirimi eksik

**P1 · Koddan doğrulandı**  
**Kanıt:** [ios/Runner/AppDelegate.swift:56](/home/erkanoz/projeler/iptv/lifeos-iptv-player/ios/Runner/AppDelegate.swift:56) · [ios/Runner/Info.plist:80](/home/erkanoz/projeler/iptv/lifeos-iptv-player/ios/Runner/Info.plist:80) · [lib/data/services/lan_sync_service.dart:171](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/lan_sync_service.dart:171)

enterPipMode native tarafta false dönüyor ve iOS PiP olayları yayımlanmıyor. Mevcut platform yardımcıları iOS PiP’i sunmuyor; bu bir tamamlanmış özellik değil. Info.plist NSBonjourServices yalnızca _googlecast._tcp bildiriyor; uygulamanın cihaz eşleme servisi _lifeostv-sync._tcp listede yok.

**Öneri:** iOS’a uygun AVPictureInPictureController/video katmanı entegrasyonu tasarla; önce mevcut video backend’iyle desteklenen bağlama yolunu doğrula. Bonjour servis listesine senkron servisini ekle; yerel ağ izin açıklamasını iki kullanım için düzenle.

**Kabul testi:** Gerçek iPhone’da PiP aç/kapat, ekran kilidi/telefon kesintisi ve uygulama arka planı; aynı ağdaki Android/Linux cihazını keşfetme.

### B19 — Android tam ekran politikası SDK sürümüne bağlı olarak etkisizleşiyor

**P1 · Kod ve resmi platform belgesiyle doğrulandı**  
**Kanıt:** [lib/core/system_ui.dart:31](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/core/system_ui.dart:31) · [android/app/build.gradle.kts:39](/home/erkanoz/projeler/iptv/lifeos-iptv-player/android/app/build.gradle.kts:39) · [lib/main.dart:339](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/main.dart:339)

Kod immersiveSticky seçerek çubukların gizleneceğini varsayıyor. targetSdk Flutter’dan alınıyor; incelemede kurulu Flutter hedefi API 36. Flutter belgesi hedef API 36+ için edge-to-edge dışındaki modların çalışmayacağını belirtiyor. Ayrıca uygulama resumed olduğunda oynatıcı açık olsa da uygulama düzeyi fullscreenMode yeniden uygulanıyor; iki farklı UI sahibi var.

**Öneri:** SDK’ye uygun edge-to-edge/insets politikası oluştur. Player ve app chrome sahipliğini merkezi hale getir; SafeArea, çentik ve gesture navigation alanlarını boyuta göre yönet. Flutter/targetSdk sürümünü CI’da sabitle.

**Kabul testi:** API 34/35/36, portrait/landscape, üç düğmeli/gesture navigasyon ve PiP dönüşünde çubuklar ve kontroller doğru yerde kalmalı.

### B20 — AI sohbeti profil PIN kontrolünü atlıyor

**P1 · Koddan doğrulandı**  
**Kanıt:** [lib/presentation/widgets/ai/tonight_chat_sheet.dart:449](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/widgets/ai/tonight_chat_sheet.dart:449) · [lib/presentation/widgets/profile/profile_picker_sheet.dart:59](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/widgets/profile/profile_picker_sheet.dart:59)

Normal profil seçici PIN isterken AI switchProfile aracı doğrudan setActiveProfile çağırıyor. Korunan profile sohbet komutuyla geçilebilir. isKids bilgisi içerik repository’sinin profil bazlı erişim filtresine bağlanmamış; mevcut kategori-adı adult filtresi çocuk profiline özgü yaş sınırı yerine geçmez.

**Öneri:** Profil geçişini ve içerik erişimini UI’dan bağımsız authorization katmanına taşı. AI, normal seçici ve route girişleri aynı PIN/erişim denetimini kullansın. Yaş sınıfı bilinmeyen içeriğin çocuk profilinde politikası açık olsun.

**Kabul testi:** PIN’li profile sohbetten geçiş izin almadan gerçekleşmemeli; aynı içerik arama, öneri, favori ve doğrudan oynatma yollarında tutarlı filtrelenmeli.

### B21 — Tam senkronizasyon ayrıntı metadata’sını siliyor

**P1 · Koddan doğrulandı**  
**Kanıt:** [lib/data/services/sync_service.dart:250](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/sync_service.dart:250) · [lib/data/repositories/content_repository.dart:1202](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/repositories/content_repository.dart:1202) · [lib/data/datasources/local/tables.dart:64](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/datasources/local/tables.dart:64)

ChannelsCompanion.insert + insertOrReplace ile temel alanlar yazılıyor; daha önce ayrıntıdan öğrenilen genre/plot/cast/director/backdrop/trailer/searchText alanları verilmediği için yeni satırda null’a dönebiliyor. Katalog yenilemesi sonrası arama ve öneri kalitesi düşer, ayrıntılar yeniden indirilir. Kategori isHidden da replace ile sıfırlanır; bazı çağıranlar yeniden uygular, bütün giriş noktaları uygulamaz.

**Öneri:** Alan bazlı upsert ve kaynak sahipliği kullan. Değişmeyen satırları hash/versiyon karşılaştırmasıyla atla. Kullanıcı tercihlerini sağlayıcı satırından ayır; arama/embedding invalidation yalnızca ilgili alan değişince çalışsın.

**Kabul testi:** Ayrıntı metadata’sı ve gizli kategori kaydet→full/manual/login sync: veriler korunmalı; değişmeyen katalog DB yazısı üretmemeli.

### B22 — Senkronizasyon kilidi ortak değil

**P1 · Deneyle doğrulandı**  
**Kanıt:** [lib/data/services/sync_metadata.dart:36](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/sync_metadata.dart:36) · [lib/presentation/state/auth_provider.dart:45](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/state/auth_provider.dart:45) · [lib/presentation/state/auth_provider.dart:61](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/state/auth_provider.dart:61)

Mutex SyncMetadata örneğinin bool alanı. İki ayrı SyncMetadata aynı SharedPreferences kullanırken ikisi de kilidi alabiliyor; tanı testi doğruladı. syncAll/syncAllWithProgress/forceSync aynı kilit yolundan geçmiyor. Eski hesabın işi yenisi etkinleşince global tablolara yazabilir.

**Öneri:** Hesap bazlı tek SyncCoordinator, ortak in-flight future ve iptal/generation token kullan. Manuel/otomatik/ilk giriş senkronları aynı coordinator’dan geçsin. Hesap değişiminde eski sonuçlar uygulanmasın.

**Kabul testi:** İlk giriş+manuel yenileme+hesap değişimini örtüştür; her hesap için tek iş, hiçbir eski hesap yazısı ve deterministik sonuç.

### B23 — Büyük M3U/XMLTV ana isolate üzerinde CPU ve bellek yükü oluşturuyor

**P2 · Ölçüm ve kodla doğrulandı**  
**Kanıt:** [lib/data/services/m3u_parser.dart:410](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/m3u_parser.dart:410) · [lib/data/services/sync_service.dart:317](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/sync_service.dart:317) · [lib/data/services/xmltv_parser.dart:120](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/xmltv_parser.dart:120)

M3U bytes→String→parse→sınıflandırma/kimlik döngüsü aynı isolate’ta. XMLTV de bütün DOM’u oluşturuyor; async fonksiyon içinde olması CPU işini arka plana taşımaz. Bu makinede 100 bin satır parse+model+kimlik üretimi medyan 919 ms; ağ/DB dahil değil. TV/telefon değerleri ölçülmedi. Xtream JSON için BackgroundTransformer zaten var ve korunmalı.

**Öneri:** Parser/model dönüşümünü isolate’a taşı, büyük XML’de streaming parser kullan. İndirme/çözülmüş veri boyutuna sınır, aşama ilerlemesi ve iptal koy. Gerekli EPG zaman aralığını erken filtrele; SharedPreferences’i çok megabayt XML deposu olarak kullanma.

**Kabul testi:** 10k/50k/100k fixture’da UI frame süreleri ve tepe bellek ölç; parse sürerken kaydırma/geri/iptal tepki vermeli.

### B24 — Prune ve EPG güncellemesi büyük/veri kesintili senaryolara dayanıklı değil

**P2 · Koddan doğrulandı; büyük DB testi gerekli**  
**Kanıt:** [lib/data/services/sync_service.dart:174](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/sync_service.dart:174) · [lib/data/services/sync_service.dart:405](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/sync_service.dart:405) · [lib/data/services/sync_service.dart:748](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/sync_service.dart:748)

Prune bütün keepIds değerlerini tek NOT IN ifadesine koyuyor; büyük kataloglarda SQL parametre sınırı riski var. Tamamen kaybolan tür boş keep-set nedeniyle temizlenmiyor. EPG’de silme ve yeniden ekleme tek transaction içinde değil; arada hata uygulamayı boş rehberle bırakabilir.

**Öneri:** Staging tabloda generation işaretle ve anti-join ile sil; doğrulanmış boş katalog ile başarısız cevabı ayır. EPG’de kanal veya makul chunk bazında transaction, batch upsert ve görünür pencere indeksi kullan.

**Kabul testi:** 100 bin ID prune, tüm filmleri kaldıran geçerli liste ve EPG insert sırasında hata enjeksiyonu; son sağlam görünüm korunmalı.

### B25 — XMLTV bellek önbelleğinde TTL kontrolü yok

**P1 · Koddan doğrulandı**  
**Kanıt:** [lib/data/services/xmltv_parser.dart:274](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/xmltv_parser.dart:274) · [lib/data/services/xmltv_parser.dart:330](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/xmltv_parser.dart:330)

Aynı URL için _cachedResult varsa doğrudan dönülüyor. Altı saat TTL yalnızca disk cache yolunda kontrol ediliyor. Uygulama uzun süre açık kaldığında URL değişmedikçe veya açık cache temizliği yapılmadıkça eski programlar kullanılabilir; sık senkron çağırmak bunu tek başına düzeltmez.

**Öneri:** Bellek ve disk önbelleğine ortak fetchedAt/expiresAt modeli uygula; manuel yenilemede force seçeneği olsun. Hesap/URL değişiminde doğru kapsamı iptal et.

**Kabul testi:** Sahte saatle 6 saati aş, aynı URL’de programları değiştir; süreç kapanmadan yeni EPG gelmeli.

### B26 — M3U parser bazı yaygın satır biçimlerinde veri kaybediyor

**P2 · Kısmen deneyle doğrulandı**  
**Kanıt:** [lib/data/services/m3u_parser.dart:201](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/m3u_parser.dart:201) · [lib/data/services/m3u_parser.dart:315](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/m3u_parser.dart:315) · [lib/data/services/sync_service.dart:459](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/sync_service.dart:459)

İlk virgülü isim ayıracı sanan regex, group-title="News, Sports",Actual Channel örneğinde adı Sports",Actual Channel olarak üretti. EXTINF sonrasındaki yorum taraması EXTINF sınırını ayrı ele almıyor; #EXTVLCOPT/#KODIPROP başlık bilgileri oynatıcıya taşınmıyor. İlerlemeli ve ilerlemesiz senkronun adsız kanal fallback’leri farklı olduğu için aynı kayıt farklı hash alabilir.

**Öneri:** Tırnakları ve direktif durumunu izleyen parser; ortak normalizeEntry fonksiyonu; referer/user-agent/cookie gibi desteklenen oynatma başlıklarını tipli descriptor’da taşı. Bozuk kaydı raporlayıp bir sonraki EXTINF’te toparlan.

**Kabul testi:** Virgüllü tırnaklı alanlar, URL’siz EXTINF, CRLF/BOM, bağıl URL, HTTP başlıkları ve iki sync yolunda aynı kimlik için fixture testleri.

### B27 — Arama alanı temizlenince önceki sonuç geri gelebilir

**P2 · Koddan doğrulandı**  
**Kanıt:** [lib/presentation/screens/search/search_screen.dart:187](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/search/search_screen.dart:187) · [lib/presentation/screens/search/search_screen.dart:221](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/search/search_screen.dart:221)

Boş sorgu dalı sonuçları temizleyip return ediyor; _searchRequestId artırılmıyor. Daha önce başlamış DB/AI işi aynı requestId ile tamamlanıp boş arama ekranını eski sonuçlarla doldurabilir. Genel yeni-sorgu koruması var, ancak temizleme bu korumayı atlıyor.

**Öneri:** Her metin değişiminde, temizleme dahil, generation artır; eski HTTP çağrısını mümkünse iptal et. Loading ve öneri durumlarını aynı sorgu kimliğine bağla.

**Kabul testi:** Gecikmeli sorguyu başlat, metni hemen sil, eski yanıtı tamamla: sonuçlar ve spinner boş kalmalı.

### B28 — Arama indeksi eksik ve eski sonuçları kalıcılaştırabiliyor

**P2 · Koddan doğrulandı**  
**Kanıt:** [lib/data/repositories/content_repository.dart:629](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/repositories/content_repository.dart:629) · [lib/data/repositories/content_repository.dart:689](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/repositories/content_repository.dart:689) · [lib/data/repositories/content_repository.dart:1216](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/repositories/content_repository.dart:1216)

Hızlı aramada bir tane indeksli sonuç bulunursa indekslenmemiş eşleşmeler hiç taranmıyor. İndeks yalnızca searchText=null satırları dolduruyor; updateChannelMetadata searchText’i geçersizleştirmiyor. Yeni cast/genre/plot normal aramada görünmeyebilir. Fallback rating sıralı sınırlı dilim taradığı için büyük katalogda aşağıda kalan başlıklar bulunamayabilir. LIKE %token% sıralı bir metin indeksinin avantajını kullanmaz.

**Öneri:** Arama verisini içerik sürümüyle güncelle; geçiş döneminde indeksli ve indekslenmemiş sonuçları birleştir. FTS5/BM25 veya ihtiyaca uygun token indeksini Türkçe normalizasyonla birleştir; exact title→prefix→token→fuzzy sıralaması kur.

**Kabul testi:** Aynı sorgunun indeksli+indekssiz iki eşleşmesi, sonradan eklenen oyuncu adı, Türkçe İ/ı/ş/ğ ve 50 bininci sıradaki düşük puanlı tam başlık bulunmalı.

### B29 — AI arama/eylem yollarında içerik türü ve görünürlük kayboluyor

**P1 · Koddan doğrulandı**  
**Kanıt:** [lib/presentation/screens/search/search_screen.dart:349](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/search/search_screen.dart:349) · [lib/data/services/catalog_enrichment_runner.dart:94](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/catalog_enrichment_runner.dart:94) · [lib/presentation/widgets/ai/tonight_chat_sheet.dart:346](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/widgets/ai/tonight_chat_sheet.dart:346) · [lib/presentation/widgets/ai/ai_similar_section.dart:105](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/widgets/ai/ai_similar_section.dart:105)

Katalog PK’si (streamId,type), fakat AI arama havuzu Map<int,Channel>. Aynı ID’de film ve dizi birbirini ezer. Enrichment asked/typeOf/returned yapıları da yalnızca ID kullanıyor ve dönen type’ın istenen çiftle eşliğini doğrulamıyor. Semantic sohbet ve benzer içerik okumaları kategori join/gizli/adult kontrolünü atlayıp doğrudan channels tablosunu okuyor.

**Öneri:** Bütün aday/yanıt/eylem şemalarında (accountId,type,id) kullan. Sonuçları merkezi görünürlük/ebeveyn filtresinden geçir. AI yanıtını yalnızca gerçekten istenmiş ve halen erişilebilir kimliklere çözümle; bulunmayan öğeye favori ekleme.

**Kabul testi:** Aynı ID’li film+dizi+canlı, gizlenmiş kategori ve erişimi kapatılan içerik; her AI yüzeyinde tür ve görünürlük korunmalı.

### B30 — Semantik arama her sorguda tüm vektörleri yüklüyor

**P2 · Koddan doğrulandı; ölçek ölçümü gerekli**  
**Kanıt:** [lib/data/services/semantic_search_service.dart:30](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/semantic_search_service.dart:30) · [lib/data/repositories/content_embeddings_repository.dart:76](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/repositories/content_embeddings_repository.dart:76) · [lib/presentation/screens/search/search_screen.dart:314](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/search/search_screen.dart:314)

loadAll bütün vektörleri decode ediyor, _rank bütün skorlara O(N log N) sort uyguluyor; CPU kısmı UI isolate’ında. 100 bin × 768 × 4 bayt yalnızca ham vektörler için 307,2 MB; DB blob’ları ve decode kopyaları ek maliyettir. Bu bir bellek hesabıdır, ölçülmüş uygulama RSS’i değildir. Ana arama ekranı semantik servisi kullanmıyor; hizmet sohbet ve benzerlikte kullanılıyor.

**Öneri:** Önce yetkili adayları lexical/tür/yıl filtresiyle daralt; CPU skorlamasını isolate’a taşı. Top-k heap, bölümlü vektör yükleme veya ölçeğe uygun ANN indeksini ölç. Ana aramada lexical+semantic birleşimini mevcut fallback’i koruyarak değerlendir.

**Kabul testi:** 10k/50k/100k vektör için p50/p95 süre, peak RSS, UI frame ve Recall@20 ölçümü; iptal edilen sorgu CPU işini de durdurmalı.

### B31 — Embedding güncelliği ve sorgu/doküman ayrımı eksik

**P2 · Koddan doğrulandı**  
**Kanıt:** [lib/data/repositories/content_embeddings_repository.dart:98](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/repositories/content_embeddings_repository.dart:98) · [lib/data/services/gemini_service.dart:3005](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/gemini_service.dart:3005) · [lib/data/services/semantic_search_service.dart:24](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/semantic_search_service.dart:24)

pendingItems yalnızca embedding’i hiç olmayan kaydı alıyor. Metin, model veya kaynak içerik değişiminde yerel vektörün source hash kontrolü yok; yalnızca global tarif sürümüyle toplu temizleme var. Gemini isteğinde taskType belirtilmiyor. Nokta çarpımı farklı boyutları minimum uzunlukta sessizce karşılaştırıyor. Bozuk embedding cevabında bazı öğeleri atıp listeyi kısaltmak, index ile zip edilen sonuçların yanlış içeriğe yazılmasına da neden olabilir.

**Öneri:** Kaynak hash’i, model, boyut, task type ve versiyon sakla. Arama sorgusuna RETRIEVAL_QUERY, katalog girdisine RETRIEVAL_DOCUMENT stratejisini eval ile doğrula. Boyut/adet/finite değer doğrulaması yap; bozuk batch’i kısmen kaydırarak eşleme.

**Kabul testi:** Metadata değişimi, model/boyut geçişi ve ortasında eksik vektör bulunan cevapta doğru öğeler yeniden üretilmeli; yanlış vektör eşleşmesi olmamalı.

### B32 — AI düşük güvenli tahminleri gerçek metadata gibi kullanıyor

**P2 · Koddan doğrulandı**  
**Kanıt:** [lib/data/services/gemini_service.dart:3053](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/gemini_service.dart:3053) · [lib/data/services/catalog_enrichment_runner.dart:103](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/catalog_enrichment_runner.dart:103) · [lib/data/repositories/content_repository.dart:1324](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/repositories/content_repository.dart:1324)

Prompt belirsiz başlık için en iyi tahmini verip confidence<0.5 istemekte; değer kaydediliyor, fakat _applyEnrichment güven eşiği uygulamadan genre/year’ı kullanıyor. Başarılı batch’in atladığı içeriklere boş tombstone yazılarak gelecekteki pending kuyruğundan çıkarılıyor. Yanlış film eşleme arama ve öneri zincirine yayılabilir.

**Öneri:** Sağlayıcı metadata’sı→doğrulanmış dış kimlik→AI tahmini kaynak hiyerarşisi; güven eşiği ve belirsiz etiketi ekle. Düşük güveni arama sıralamasında azalt, yaş erişim kararı için tek kaynak yapma. Geçici atlanan kayıtları retryAfter ile yeniden dene.

**Kabul testi:** Aynı isimli yeniden çevrimler, Türkçe/orijinal ad, eksik yıl ve uydurma başlıklardan sabit doğruluk kümesi; yanlış kimlik ve yanlış tür oranını ölç.

### B33 — Arka plan AI işinin oynatma başladığında durması garanti değil

**P2 · Koddan doğrulandı**  
**Kanıt:** [lib/main.dart:194](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/main.dart:194) · [lib/main.dart:230](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/main.dart:230) · [lib/data/services/catalog_embedding_runner.dart:38](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/catalog_embedding_runner.dart:38) · [lib/data/services/catalog_enrichment_runner.dart:60](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/catalog_enrichment_runner.dart:60)

Periyodik başlatıcı playbackActive kontrolü yapıyor, fakat başlamış 40 batch’lik döngüler bunu yeniden kontrol etmiyor. İlk gecikmeli başlangıç yolu da oynatma kontrolünü atlıyor. Kullanıcı film açtıktan sonra AI HTTP/DB/vektör işleri devam edebilir. Ayar/provider değişimi eski işi iptal etmiyor.

**Öneri:** Her batch öncesinde playback, foreground, ağ/pil politikası ve hesap generation kontrolü yap. Düşük öncelikli işleri ortak budget/cancellation yöneticisine bağla; yayın sırasında DB yazılarını ölçerek sınırla.

**Kabul testi:** AI işinin ikinci batch’inde 4K VOD başlat; yeni batch durmalı ve oynatma bitince kaldığı yerden devam etmeli.

### B34 — LAN senkronu hesap/profil sınırlarını güvenilir korumuyor

**P1 · Koddan doğrulandı**  
**Kanıt:** [lib/data/services/lan_sync_service.dart:1033](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/lan_sync_service.dart:1033) · [lib/data/services/lan_sync_service.dart:1106](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/lan_sync_service.dart:1106) · [lib/data/services/lan_sync_service.dart:1203](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/lan_sync_service.dart:1203)

Favori/geçmiş payload’ında hesap kimliği yok. Hesap kontrolü enrichment/categoryPrefs için yapılırken favorites/progress için uygulanmıyor. Profil adı kimlik kabul ediliyor; bilinmeyen ad aktif profile düşüyor. Eşleştirilmiş iki cihaz farklı sağlayıcı kullanıyorsa aynı streamId yanlış içeriğe bağlanır. Geçmiş silme için tombstone yok; başka cihaz eski kaydı geri ekleyebilir. Auto snapshot watchlist taşımıyor.

**Öneri:** Kalıcı hesap/profil UUID’si ve içerik kimliği kullan; eşleme yapılmamış profil için kullanıcıya eşleme sonucu göster. Her senkronize varlık için değişiklik sürümü/tombstone; saat sapmasını yöneten çatışma politikası; desteklenen veri türlerini açık sözleşme yap.

**Kabul testi:** Farklı hesaplı eşler, aynı isimli iki profil, profil yeniden adlandırma, çevrimdışı geçmiş silme, saat farkı ve listem değişimi.

### B35 — LAN aktarımında anahtarlar şifresiz taşınıyor ve kimlik üretimi kriptografik değil

**P1 · Koddan doğrulandı**  
**Kanıt:** [lib/data/services/lan_sync_service.dart:248](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/lan_sync_service.dart:248) · [lib/data/services/lan_sync_service.dart:321](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/lan_sync_service.dart:321) · [lib/data/services/lan_sync_service.dart:356](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/lan_sync_service.dart:356) · [lib/data/services/lan_sync_service.dart:1072](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/lan_sync_service.dart:1072)

HttpServer.bind ile şifresiz HTTP, bütün IPv4 arayüzleri ve header’da PIN/token kullanılıyor. PIN saatten; güven token’ı saat+pid+sayacın FNV hash’inden türetiliyor. Auto snapshot Gemini API anahtarını da taşıyor; manuel hesap export’u şifre içeriyor. LAN’da olmak aktarımı şifrelemez. Bu değerlendirme kaynak incelemesidir; herhangi bir ağ veya gerçek hesap üzerinde saldırı testi yapılmadı.

**Öneri:** Kriptografik rastgele nonce/token, kısa süreli eşleme, deneme sınırı ve cihazlar arası doğrulanmış şifreli kanal kullan. API anahtarı/hesap şifresi paylaşımını açık seçime bağla; OS secure storage kullan. Yedekten cihaz trust kimliklerini hariç tut.

**Kabul testi:** Sentetik sırlarla ağ yakalama: parola/token/AI anahtarı düz metin görünmemeli; yanlış PIN denemeleri sınırlanmalı; eş iptali eski token’ı geçersizleştirmeli.

### B36 — Cast geçişi VOD pozisyonunu taşımıyor

**P2 · Koddan doğrulandı**  
**Kanıt:** [lib/presentation/screens/player/video_player_screen.dart:2758](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/video_player_screen.dart:2758) · [lib/data/services/cast_service.dart:255](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/cast_service.dart:255) · [lib/presentation/screens/player/video_player_screen.dart:2829](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/video_player_screen.dart:2829)

Yerel video pause ediliyor, Chromecast LOAD mesajına currentTime eklenmiyor; mevcut süre remote’a taşınmıyor. Cast bittiğinde remote pozisyonu yerel player’a aktarılmadan play çağrılıyor. Kullanıcı 20. dakikada devredince başa, geri dönünce eski yerel pozisyona dönebilir. Local pause bağlantıyı kesin kapatmak anlamına da gelmez; tek bağlantılı sağlayıcı testi gerekir.

**Öneri:** CastSession içinde oturum pozisyonu ve oynama durumunu tek otorite yap. LOAD/seek onayı sonrası devret, dönüşte son remote pozisyonunu uygula; hata halinde önceki yerel duruma dön. MIME/codec yetenek eşleşmesini görünür kıl.

**Kabul testi:** 20. dakikada cast→5 dakika izle→yerel devam; süre korunmalı. Remote yükleme hatasında yerel oynatma geri gelmeli; tek bağlantı hesabı aşılmamalı.

### B37 — Hatırlatıcı başarı sinyali gerçek bildirim garantisi değil

**P2 · Kod ve paket talimatıyla doğrulandı**  
**Kanıt:** [lib/data/services/notification_service.dart:55](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/notification_service.dart:55) · [android/app/src/main/AndroidManifest.xml:61](/home/erkanoz/projeler/iptv/lifeos-iptv-player/android/app/src/main/AndroidManifest.xml:61)

requestPermission dönüşü yok sayılıp schedule deneniyor. Proje manifestinde flutter_local_notifications 18.0.1’in planlı bildirim için istediği ScheduledNotificationReceiver ve boot receiver yok. Masaüstü scheduleReminder açıkça false dönüyor; beş platformda eşit özellik iddiası doğru değil.

**Öneri:** İzin reddini ayrı sonuç yap; gerekli receiver yapılandırmasını tamamla. Planlama/teslim/tıklama olaylarını doğrula ve masaüstü için ayrı uygulama veya açık capability sun. Inexact alarm gecikmesini ürün davranışına yansıt.

**Kabul testi:** İzin reddi, uygulama kapanması, cihaz yeniden başlama ve saat dilimi değişimi; gösterilmeyecek bildirime başarılı kuruldu mesajı verilmemeli.

### B38 — Dizi ayrıntısı bozuk bölüm kimliğinde çöker; dar ekran yerleşimi kırılgan

**P2 · Koddan doğrulandı**  
**Kanıt:** [lib/presentation/screens/series/series_screen.dart:2488](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/series/series_screen.dart:2488) · [lib/presentation/screens/series/series_screen.dart:2312](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/series/series_screen.dart:2312) · [lib/presentation/screens/series/series_screen.dart:2353](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/series/series_screen.dart:2353) · [lib/presentation/screens/series/series_screen.dart:2399](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/series/series_screen.dart:2399)

Kart üretiminde int.parse(ep[id]) null/geçersiz veride FormatException üretir; başlık yalnızca title alanından okunur. Sezonlar Wrap ve sağdaki işlemle dar alanı paylaşır. Bölümler SingleChildScrollView içinde topluca oluşturulur; 30 öğelik pencere gerçek lazy liste değildir. Masaüstü fragman 384×216 overlay; platforma göre yerleşim seçimi dar masaüstü ve büyük tableti yeterince ayırmıyor.

**Öneri:** Episode.fromProvider ile güvenli normalizasyon; title/name/info.title/info.name zinciri; LayoutBuilder kırılımları; yatay sezon seçici ve ayrı işlem menüsü; SliverList; fragman için ayrılmış kolon veya kullanıcı isteğiyle açılış.

**Kabul testi:** Null/abc ID, uzun bölüm adı, 1/10/30 sezon, 360×800 telefon, 800×1280 tablet, 900×500 masaüstü ve %200 metin boyutu.

### B39 — Altyazı indirme ve hata sunumu eksik sınırlandırılmış

**P2 · Koddan doğrulandı**  
**Kanıt:** [lib/data/services/opensubtitles_service.dart:271](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/opensubtitles_service.dart:271) · [lib/data/services/opensubtitles_service.dart:297](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/opensubtitles_service.dart:297)

Arama hatası [] ve indirme hatası null olarak dönüyor: kota/izin/ağ hatası ile sonuç yok ayrımı kayboluyor. Dosya indirme için oluşturulan Dio’da timeout ve gövde boyut sınırı yok. Mevcut SRT→VTT ve dil/track eşleme unit testleri iyi bir temel, fakat uçtan uca platform davranışı ölçülmedi.

**Öneri:** Typed SubtitleResult, explicit connect/receive/total timeout, iptal ve dosya boyut sınırı; encoding/format doğrulaması; bölüm+sezon kimliğiyle arama. Subtitle render maliyetini 4K ve büyük fontta ölç.

**Kabul testi:** 429/403, kesik dosya, çok büyük dosya, Türkçe encoding, RTL, harici/dahili track ve tam ekran/PiP geçişinde altyazı konumu.

### B40 — Apple CI yok; Android release imza dosyası yolu uyuşmuyor

**P1 · Koddan doğrulandı**  
**Kanıt:** [.github/workflows/build.yml:1](/home/erkanoz/projeler/iptv/lifeos-iptv-player/.github/workflows/build.yml:1) · [android/app/build.gradle.kts:13](/home/erkanoz/projeler/iptv/lifeos-iptv-player/android/app/build.gradle.kts:13)

Workflow yalnızca Linux/Windows/Android derliyor; README’deki macOS/iOS build iddiası mevcut YAML ile uyuşmuyor. CI key.properties dosyasını repository köküne yazıyor, Gradle rootProject.file(key.properties) ise android kökünde arıyor. Keystore için de köke göre yazılan android/app yolu ile app proje file() çözümü tutarlı değil. Sonuç release’in sessizce debug imzaya düşmesi olabilir. Stable Flutter sürümü sabitlenmemiş.

**Öneri:** Apple runner build+test ekle; iOS cihaz dağıtımına uygun signing ve macOS signing/notarization hattını kur. Android dosya yollarını aynı köke bağla, tag release’te imza yoksa build’i durdur. SDK/lockfile ve derleyici sürümlerini sabitle.

**Kabul testi:** CI’da kullanılan signingConfig ve sertifika fingerprint doğrulaması; beş platform artifact smoke testi; temiz kurulum ve önceki sürüm üstüne veri koruyan güncelleme.

### B41 — Testler kritik ürün akışlarına yeterli güvence vermiyor

**P2 · Koddan doğrulandı**  
**Kanıt:** [test/data/services/m3u_parser_test.dart:1](/home/erkanoz/projeler/iptv/lifeos-iptv-player/test/data/services/m3u_parser_test.dart:1) · [lib/data/datasources/local/database.dart:13](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/datasources/local/database.dart:13) · [lib/presentation/screens/player/video_player_screen.dart:1](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/video_player_screen.dart:1)

21 test dosyasındaki 223 test geçiyor; parser/yardımcı/TV focus testleri ağırlıklı. Gerçek player fullscreen/PiP/always-on-top, hesaplı DB senkronu, çok profilli yedek round-trip, LAN çatışma ve Apple cihaz akışları bu başarı sayısının kapsamına girmiyor. Şema sürümü 23 ve eski kurulumları onaran karmaşık migration yolları var; eski DB fixture’larıyla migration testleri bulunmuyor.

**Öneri:** Unit sayısını artırmak yerine kritik durum makinelerine, provider sözleşmelerine ve veri round-trip/migration testlerine yatırım yap. Gerçek medya ve native pencere testleri ayrı platform işlerinde koşsun. Player 4741, series 4619, Gemini 3132 satır: davranış koruyarak sorumlulukları ayır.

**Kabul testi:** Önce bu rapordaki P1 örneklerine regresyon testi; sonra eski DB v1/v17/v18/v22→v23, yarım migration ve bozuk veri testleri.

### B42 — AI performans/kalite gözlemi bütün çağrıları kapsamıyor

**P2 · Koddan doğrulandı**  
**Kanıt:** [lib/data/services/ai_instrumentation_service.dart:26](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/ai_instrumentation_service.dart:26) · [lib/presentation/screens/search/search_screen.dart:328](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/search/search_screen.dart:328) · [lib/data/services/catalog_embedding_runner.dart:42](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/catalog_embedding_runner.dart:42)

Instrumentation bazı öneri ve sohbet çağrılarını sarıyor; arama parse/suggest/rerank ve embedding/enrichment yolları aynı kapsama sahip değil. Servis çoğu hatayı null’a indirdiği için kota/model erişimi/zaman aşımı ayrımı kayboluyor. Arama AI aşamalarının her birinde 15 saniye timeout olması toplam akış için tek 15 saniye bütçe anlamına gelmiyor; timeout gelecekte tamamlanacak HTTP işini iptal etmiyor.

**Öneri:** Merkezi AI transport: toplam deadline, iptal, concurrency/quota bütçesi, cache kapsamı, hata sınıfı ve token/latency metrikleri. Model değişimini sabit Türkçe sorgu/öneri doğruluk kümesiyle değerlendir; yalnızca daha büyük modele geçerek sorun çözüldü sayma.

**Kabul testi:** Anahtarsız/offline/429/bozuk JSON/uydurma ID/uzun cevap senaryoları; local sonuçlar gecikmemeli, eski sorgu için ücretli iş mümkün olduğunca iptal edilmeli.

## Tam ekran, küçük oynatıcı ve butonlar için önerilen tasarım

Mevcut `Player` nesnesi, video görünümü, route ve masaüstü penceresi ayrı yaşam döngülerine sahip. Bunları aynı bool ile yönetmek yerine üç sorumluluk ayrılmalı:

- **PlaybackSession:** medya kimliği, backend, açılış/iptal/hata, süre, track, ses, hız, resume ve tek decoder sahipliği.
- **WindowController:** normal/maximize/fullscreen/PiP, minimum boyut, monitör, DPI, pin ve native durum onayı.
- **PlayerControls:** aynı komutları dokunma, mouse, klavye ve kumandadan çağıran görünüm; desteklenmeyen komutu etkin göstermez.

Geçiş sırası: isteği kaydet → mevcut geçişi sırala → native komutu gönder → native olayla onayla → UI’ı güncelle. Hata/zaman aşımında son doğrulanmış duruma geri dön. PiP açma/kapatma ve route çıkışı aynı mekanizmadan geçmeli. Video yüzeyi mümkün olduğunca kalmalı; mevcut GlobalKey kullanımı dikkate alınmalı. Sırf root widget yapısı değişiyor diye “video mutlaka yeniden yaratılıyor” sonucu çıkarılmadı; texture attach/detach sayısı ölçülmeli.

ESC sözleşmesi açık olmalı: açık menüyü kapat → fullscreen’den çık → normal player’da tanımlanmış geri davranışı. Mevcut kod normal pencerede ESC’yi PiP’e dönüştürüyor; kullanıcı “oynatıcıdan çıkış” bekliyorsa bu ürün davranışı düzeltilmeli veya ayrı kısayola taşınmalı. Tam ekran çıkış kontrolü hover/odak kaybından bağımsız ulaşılabilir olmalı.

| Kontrol | Beklenen davranış / test |
|---|---|
| Play/pause | Gerçek backend durumunu göster; arka plan ve remote cast durumu ile uyuşsun |
| İleri/geri/slider | Ortak clamp; sürükleme sonu tek seek; bilinmeyen sürede kapalı |
| Önceki/sonraki bölüm | Oturum kimliğini yenile, eski progress’i doğru bölümde kaydet, son bölümde dur |
| Ses/mute | Mute kaldırınca önceki ses düzeyine dön; şu an bazı yollar doğrudan 100’e dönüyor |
| Ses/altyazı seçimi | Yüklenen track listesi değişince doğrula; hatırlanan dil yoksa anlaşılır fallback |
| Hız | Backend’in desteklediği hızları sun; VOD/canlı politikası ve ses senkronunu ölç |
| Kalite | HLS master varyantı varsa gerçek varyant seç; tek .ts veya tek MP4 için sahte kalite seçimi sunma |
| Donanım hızlandırma | MediaCodec/VideoToolbox/D3D11VA/VAAPI/NVDEC veya software durumunu gerçek veriden göster |
| Görüntü sığdırma | contain/cover/fill farkını koru; orientation ve piksel aspect ratio testi |
| Pin/fullscreen/PiP | Tek pencere controller’ı; yetenek ve gerçek durum geri bildirimi |
| Cast | Pozisyon ve oynama durumu devri; başarısız LOAD’da yerel oynatmayı geri al |
| Intro/uyku | Intro süresini bölüme clamp et; bölüm bitişi ve auto-next ile çakışmasın |
| Stats | Codec, çözünürlük, gerçek HW decoder, dropped frames, buffer, bitrate; sır içeren URL gösterme |
| Erişilebilirlik | İkonlara Semantics/Tooltip, odak göstergesi, yeterli touch target, ekran okuyucu |

Kaliteyi artırmak her GPU’da ağır shader açmak değildir. Mevcut Android bilinear/deband kapalı politikası hız lehine bir tercih. “Dengeli / düşük güç / yüksek kalite” profilleri cihaz ölçümüyle seçilmeli. 4K HDR→SDR ton eşleme, 10-bit içerik, interlaced canlı yayın ve altyazı ölçekleme ayrı örneklerle karşılaştırılmalı. Decode edilen çözünürlük ile Flutter texture çözünürlüğü ve panel çözünürlüğü ayrı raporlanmalı. Bir .m3u8 adresi tek başına adaptif çoklu kalite garantisi vermez.

## Senkronizasyon süresi ve performans planı

Tek bir “senkron süresi” yeterli ölçü değil. Şu zamanlar ayrı tutulmalı: kuyrukta bekleme, DNS/TLS/TTFB, indirme baytı ve süresi, decode/parse, normalizasyon, DB uygulama, prune, EPG eşleme ve indeks hazır olma.

Xtream tam içerik akışı normalde 3 kategori + 3 içerik çağrısı yapıyor; EPG/izlenen dizilerin ayrıntıları ayrıca istek üretir. API kuyruğu tek istekli ve minimum başlangıç aralığı 200 ms. Bu seçim sağlayıcı dostu olmak için makul, ancak başarısız bir işin kuyruğu sonsuza kadar tutması kabul edilemez. “Daha hızlı” için doğrudan sınırsız paralellik açılmamalı; sağlayıcının bağlantı limiti ile medya ve yönetim API bağlantıları birlikte ölçülmeli.

Mevcut yenileme eşikleri: kategori **30 dakika**, delta **2 saat**, tam katalog **24 saat**, izlenen dizi **1 saat**. Bunlar `isTierDue` kararlarıdır; her aralıkta otomatik çalışan zamanlayıcı oldukları varsayılmamalı. Başlatma/resume/manuel tetikleme ayrıca tasarlanmalı. LAN otomatik pası uygulama açıkken yaklaşık **5 dakikada bir**; AI pası **180 saniyede bir** dürtülüyor. Bu aralıklar farklı işleri yönetiyor.

Önerilen senkron akışı:

1. Hesap/oturum generation’ı ve tek ortak işi belirle.
2. Sağlayıcı yeteneklerini ve yeni verinin yapısını doğrula.
3. Parse/model dönüşümünü UI dışına taşı; iptali destekle.
4. Staging/generation ile değişen satırları uygula, sağlam eski veriyi koru.
5. Kaldırılan içerikleri doğrulanmış kapsamda temizle; favori/geçmiş kayıtlarını yetim bırakmak yerine erişilemez olarak işaretle.
6. Başarılı kapsamların zamanını kaydet; arama indeksi ve embedding’i ilgili alan değişimiyle yenile.
7. EPG ve AI gibi ikinci işleri düşük öncelikle, oynatmayı etkilemeden yürüt.

| Alan | İlk kabul hedefi — ölçülmüş mevcut değer değildir |
|---|---|
| UI girdi tepkisi | p95 <100 ms; uzun parse/sync sırasında kullanıcı iptal edebilmeli |
| 60 Hz görünür kaydırma | Frame bütçesi 16,7 ms; uzun bloklar trace ile giderilmeli |
| Yerel arama, 50 bin kayıt | p95 <150 ms; AI sonucu bekletmemeli |
| Sağlıklı kontrollü ağda ilk video | 1080p fixture p95 <2,5 sn; sağlayıcı TTFB ayrıca kaydedilmeli |
| Fullscreen/PiP | 100 ardışık döngüde kilitlenme/çıkamama 0; decoder sayısı artmamalı |
| VOD seek, kontrollü fixture | Sürükleme bitişinden sonra p95 <1,5 sn; tek commit |
| Değişmeyen katalog yenilemesi | Gereksiz channel rewrite 0; metadata kaybı 0 |
| Senkron iptali | UI sonucu <250 ms; ağ/DB işi güvenli sınırda sonlanmalı |
| Medya dayanıklılığı | 2 saat oynatma + 100 kanal/route geçişi; süreğen bellek artışı olmamalı |
| Veri bütünlüğü | Hesap/profil geçişi, yedek ve migration testlerinde kayıp 0 |

Ağ hızına göre senkron süresini şimdiden tek saniye değeriyle taahhüt etmek doğru olmaz. Örneğin 10 MB verinin 20 Mbit/s bağlantıda teorik aktarımı yaklaşık 4 saniyedir; DNS/TLS, sunucu beklemesi, parse ve SQLite buna eklenir. Asıl kabul karşılaştırması aynı fixture, cihaz, bağlantı ve cache durumunda önce/sonra p50/p95 ile yapılmalı.

## Yapay zekâ ve arama kalitesi için geliştirme planı

Model değiştirmeden önce doğru aday ve kimlik üretimi düzeltilmeli. Önerilen akış: Türkçe normalizasyon → exact/prefix/FTS adayları → metadata filtreleri → semantik adaylar → görünürlük/hesap/profil filtresi → birleşim/rerank → kısa gerekçe. Her öğe `(account, type, id)` ile doğrulanmalı; modelin sunduğu açıklama katalogda bulunmayan içerik yaratmamalı.

En az 200 sorguluk sabit değerlendirme seti hazırlanmalı: 50 tam/eksik başlık, 30 Türkçe yazım/diakritik, 30 oyuncu/yönetmen, 30 tür/yıl/süre, 30 tematik istek, 15 çok dilli ad, 15 olumsuz/katalog dışı istek. Örnekler: “ışıklar sönünce”, “matthew uzay filmi”, “90 dakikadan kısa gerilim”, “çocuklarla izlenecek ama korkutucu olmasın”, “Kore dizileri”, “bu oyuncunun diğer filmleri”. Süre metadata’sı eksikse kesin süre iddiası üretilmemeli.

Ölçümler: Exact-match@1, Recall@20, nDCG@10, yanlış hesap/tür oranı, gizli içerik sızıntısı, olmayan ID oranı, öneri çeşitliliği, tekrar oranı, p95 gecikme ve çağrı/token bütçesi. İlk katı koşullar: olmayan ID, gizli içerik ve yanlış hesap **0**; tam başlık ilk sırada; AI kapalıyken temel arama aynı kalitede çalışmalı. Alaka hedefleri insan etiketli veri seti üzerinde mevcut sürümle karşılaştırılarak belirlenmeli.

Diğer AI özellikleri için ayrıca:

- **Sana özel/ruh hali/grup:** aktif profil ve grup kimliği cache anahtarında yer almalı; negatif geri bildirim, izlenmiş içerik, çeşitlilik ve güncellik birlikte değerlendirilmeli.
- **Haftalık özet/hero:** yeni içerik sinyali gerçek katalog added/updated verisinden gelmeli; mevcut olmayan başlık önerilmemeli.
- **Konu tamamlama/çeviri/oyuncu bilgisi:** kaynak metin, tahmin ve doğrulanmış metadata ayrılmalı; Türkçe çeviride özel adlar korunmalı.
- **Bölüm recap:** izleme sınırı makineyle taşınmalı; sonraki bölüm spoiler’ı için adversarial test seti kullanılmalı. Prompt’ta “spoiler verme” yazması tek başına garanti değildir.
- **Araç kullanan sohbet:** profil değiştirme, oynatma, favori ve hatırlatıcı işlemleri aynı domain yetki/kimlik kontrolünden geçmeli; model serbest metni doğrudan DB eylemi olmamalı.
- **Ses:** izin reddi ve STT bulunamaması metin sohbetini bozmamalı; kullanıcı uygulamadan çıkınca STT/TTS bırakılmalı; konuşma dili uygulama diliyle tutarlı olmalı.
- **Maliyet/önbellek:** dil+profil+hesap+katalog sürümü+prompt/model versiyonu anahtarı; in-flight dedup, günlük bütçe ve anlaşılır quota mesajı kullanılmalı.

Gemini’nin resmi dokümanı embedding sorguları ve belgeleri için ayrı görev türleri sunuyor; seçim doğruluk setiyle doğrulanmalı. [Gemini embeddings belgesi](https://ai.google.dev/gemini-api/docs/embeddings).

## Platform kabul matrisi

| Platform | En az denenmesi gereken kombinasyonlar | Bu incelemede durum |
|---|---|---|
| Android telefon/tablet | API 34/35/36, düşük RAM, Adreno/Mali, 360/412 dp, tablet, portrait/landscape, PiP, kilit/arama kesintisi | Kod ve manifest incelendi; fiziksel cihaz testi yapılmadı |
| Android TV | Düşük güçlü kutu + Google/Android TV, kumanda, uzun basma, kanal fırtınası, backend yetenekleri | Ayrı oynatıcı ve focus testleri incelendi; cihaz testi gerekli |
| Linux | X11 + Wayland, GNOME/KDE, Intel/AMD/NVIDIA, VAAPI/NVDEC/software, çok monitör | Release build başarılı; native pencere/medya ölçülmedi |
| Windows | Normal/fullscreen/PiP/pin, %100/150/200 DPI, iki monitör, D3D11VA/software, ses cihazı değişimi | Kaynak/runner/CI incelendi; build ve cihaz testi bu ortamda yapılmadı |
| macOS | Apple Silicon; destek kararı varsa Intel; Spaces/fullscreen, sandbox release, dosya seçici | Entitlement/runner incelendi; Apple CI eksik, native doğrulama gerekli |
| iPhone/iPad | Fiziksel cihaz, çentik/SafeArea, ağ/mikrofon izinleri, arka plan/PiP, AirPlay ses rotası, iPad çoklu pencere | Yapılandırma eksikleri bulundu; derleme/cihaz testi yapılmadı |

Her platformda ortak medya fixture’ları: H.264/AAC MP4, H.265 8/10-bit MKV, yüksek bitrate 4K, HLS tek/master playlist, MPEG-TS canlı, çoklu ses, dahili SRT/ASS/PGS ve harici UTF-8 altyazı. Bunlar otomatik “desteklenir” iddiası değil, destek haritası çıkarmak için test girdileridir. Sağlayıcı varyasyonları: yönlendirme, HTTPS/HTTP, token süresi, User-Agent/Referer, özel karakterli kimlik, bağlantı limiti, eksik/hatalı metadata.

Ağ matrisi: offline başlangıç, 100–500 ms gecikme, düşük bant genişliği, 30 sn kesinti, 401/403/404/429/5xx, sonsuz timeout, kesilmiş liste ve oynatma ortasında Wi-Fi→mobil veri. Kaydedilecekler: ilk frame, buffering toplamı, dropped frames, A/V sapması, CPU/GPU, RSS, enerji/ısı ve bağlantı sayısı.

## Ek bakım ve doğrulama konuları

- **EPG/catch-up saat dilimi:** epoch yolu sağlam bir temel; tarih metni ve timeshift URL’si cihazın yerel saatine dayanıyor. Sağlayıcının timezone/catch-up destek süresini ayrıca modellemek gerekir. Saat farkı ve yaz saati geçişi testi yapılmalı. [URL oluşturucu](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/utils/stream_url_builder.dart:63).
- **Bölüm ve seri kimliği:** parent seri ile episode aynı `type=series` ilerleme tablosuna yazılıyor; sağlayıcı ID alanları çakışırsa farklı varlıklar birleşebilir. Episode progress ayrı kimlik taşımalı. [İlerleme kaydı](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/screens/player/video_player_screen.dart:1347).
- **DB ilişkileri ve indeksler:** Channels/Categories bileşik PK kullanırken bazı declared foreign key’ler tek kolona referans veriyor. Foreign-key enforcement kararı ve migration testi gerekir; yalnızca PRAGMA açmak mevcut şemada yeterli olmayabilir. Kritik sorgular EXPLAIN QUERY PLAN ile ölçülerek `(type,categoryId)`, `(channelId,start,stop)` ve profil/zaman indeksleri değerlendirilmelidir. [Tablolar](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/datasources/local/tables.dart:45).
- **Fragman/background görünüm:** IndexedStack/Offstage tek başına native oynatıcıyı veya stream aboneliğini durdurmaz. Route görünürlüğüne göre trailer player ve pahalı aboneliklerin pause/dispose davranışı ölçülmeli. TV’de detay fragmanı ayrıca kapatılmış; eski rapordaki bütün varsayımlar aynen taşınmadı. [Router](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/config/router.dart:129), [fragman](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/presentation/widgets/content/backdrop_trailer.dart:149).
- **YouTube hata zinciri:** `return _extractStreamUrlImpl(videoId)` try içinden await edilmeden döndürülüyor; dış Future hatası bu catch’e yakalanmaz. Analiz aracı da uyarıyor. [Kaynak](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/youtube_trailer_service.dart:173).
- **Yerelleştirme/erişilebilirlik:** TV hata mesajları ve bazı gesture metinleri Türkçe sabit; 8 ARB dosyası bulunması bütün dinamik metinlerin çevrildiğini kanıtlamaz. RTL, sistem dili, büyük font, ekran okuyucu ve kumandayla tüm ayarların erişilebilirliği test edilmeli.
- **Ayar sözleşmesi:** `autoSubs`, `epgPastDays`, ebeveyn alanları gibi modelde bulunan her alan için “UI’da sunuluyor mu, kalıcı saklanıyor mu, hangi backend’de uygulanıyor?” tablosu çıkarılmalı. Özellikle `epgPastDays` yerine XMLTV yolunda sabit 6 saat geçmiş kesimi kullanılıyor. [Ayar modeli](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/domain/models/app_settings.dart:10), [EPG filtresi](/home/erkanoz/projeler/iptv/lifeos-iptv-player/lib/data/services/sync_service.dart:721).

## Uygulama sırası ve bitiş ölçütü

| İş paketi | Bulgular | Tamamlanma koşulu |
|---|---|---|
| 1. Veri bütünlüğü | B03–08, B20–22, B34 | Hesap/profil ayrımı ve round-trip/migration testleri; veri silmeden geçiş |
| 2. Ağ ve senkron dayanıklılığı | B01–02, B10, B22–26 | Bounded retry, iptal, gerçek sonuç, atomik katalog/EPG, büyük fixture |
| 3. Playback/pencere | B09, B11–16, B36 | Tek oturum/state machine; 100 pencere/kanal döngüsü; seek ve cast ölçümü |
| 4. Platform tamamlanması | B17–19, B35, B37, B40 | İzinler, PiP/Bonjour, güvenli sync, doğru signing, Apple CI |
| 5. Arama/AI | B27–33, B42 | Kimlik/görünürlük 0 hata, yerel arama SLA, eval ve çağrı bütçeleri |
| 6. UX/kalite | B38–39, ek bakım | Ekran matrisi, tüm butonlar, altyazı, RTL/erişilebilirlik ve uzun oynatma |

Bu paketler için takvim veya “şu kadar günde kusursuz” taahhüdü verilmedi: gerçek cihaz sonuçları, veri taşıma tasarımı ve sağlayıcı davranışları iş miktarını belirleyecek. Değişiklikler küçük ve doğrulanabilir aşamalarda uygulanmalı; özellikle kimlik şeması değişikliği öncesinde geri dönüşlü migration ve yedek testi şarttır.

Yayın kararı için: bütün P1 maddeleri kapanmış veya açıkça destek dışı ürün sınırıyla giderilmiş olmalı; beş platform smoke/entegrasyon matrisi başarılı olmalı; eski kurulum verisi korunmalı; hata/performans raporları gerçek ölçümlerle doldurulmalı. Birim testlerin geçmesi tek başına bu koşulları karşılamıyor.

## Resmi belgeler ve yeniden çalıştırılabilir kanıtlar

B13’teki Linux değerlendirmesinde GTK belgesi, keep-above isteğinin pencere yöneticisi tarafından uygulanacağının varsayılamayacağını ve window-state-event ile izlenmesini açıklar. [GTK keep-above](https://docs.gtk.org/gtk3/method.Window.set_keep_above.html).

B17–18 için izin ve servis tanımları: [Apple mikrofon açıklaması](https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription), [Apple konuşma tanıma açıklaması](https://developer.apple.com/documentation/bundleresources/information-property-list/nsspeechrecognitionusagedescription), [Apple Bonjour servis listesi](https://developer.apple.com/documentation/bundleresources/information-property-list/nsbonjourservices).

B19 için target API 35/36 davranışı: [Flutter setEnabledSystemUIMode](https://api.flutter.dev/flutter/services/SystemChrome/setEnabledSystemUIMode.html). Yerel Flutter SDK’sının hedefi ayrıca kaynak kodundan API 36 olarak doğrulandı; gelecekte SDK değiştiğinde yeniden kontrol edilmeli.

- [Mevcut 223 test çıktısı](/home/erkanoz/projeler/iptv/lifeos-iptv-player/docs/audit-2026-09-23/tests.log)
- [Statik analiz çıktısı](/home/erkanoz/projeler/iptv/lifeos-iptv-player/docs/audit-2026-09-23/analyze.log)
- [Linux release derleme çıktısı](/home/erkanoz/projeler/iptv/lifeos-iptv-player/docs/audit-2026-09-23/linux-build.log)
- [Altı tanı deneyinin kodu](/home/erkanoz/projeler/iptv/lifeos-iptv-player/docs/audit-2026-09-23/audit_probes_test.dart) ve [sonuçları](/home/erkanoz/projeler/iptv/lifeos-iptv-player/docs/audit-2026-09-23/probes.log)
- [Sentetik M3U ölçüm kodu](/home/erkanoz/projeler/iptv/lifeos-iptv-player/docs/audit-2026-09-23/m3u_benchmark.dart) ve [ham ölçümler](/home/erkanoz/projeler/iptv/lifeos-iptv-player/docs/audit-2026-09-23/benchmark.log)
- [Doğrulamada çözümlenen bağımlılık kilidi](/home/erkanoz/projeler/iptv/lifeos-iptv-player/docs/audit-2026-09-23/validation-pubspec.lock)
- [Kaynak envanteri](/home/erkanoz/projeler/iptv/lifeos-iptv-player/docs/audit-2026-09-23/source-inventory.txt)

Tanı kodu mevcut kusurların varlığını bekleyerek geçer; normal regresyon test takımına bu haliyle eklenmemelidir. Düzeltmeden sonra beklentiler istenen doğru davranışa çevrilmelidir. Repo kökünden, uygun Flutter/bağımlılık ortamında:

```bash
flutter test --no-pub --reporter=expanded docs/audit-2026-09-23/audit_probes_test.dart
dart --packages=.dart_tool/package_config.json docs/audit-2026-09-23/m3u_benchmark.dart
```

Tanı HTTP sunucusu yalnızca `127.0.0.1` üzerinde sentetik kullanıcı bilgisiyle çalışır. Timeout deneyi yaklaşık 60 saniye sürer. Gerçek yayın veya kullanıcı hesabı gerektirmez.
