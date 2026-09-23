# Katalog senkronizasyonu — süre, hata ve ortak çalışma

23 Eylül 2026. [Hesap izolasyonu paketinin](VERI_BUTUNLUGU_2_2026-09-23.md) devamı. Bu paket B01/B02’nin katalog akışını ve B22’nin ilk giriş/manuel/kademeli yenileme girişlerini ele alır.

## Sonuç

Aynı hesap için giriş ekranı, dashboard yenilemesi, içerik deposu veya otomatik kademeli yenileme eşzamanlı çağrı yaptığında tek katalog işi yürür. Çağıranlar aynı tamamlanma/hata sonucunu bekler; devam eden işlem varken erken başarı dönülmez. Tam yenileme küçük bir kategori/kademeli işlem sırasında istenirse arkasına tek bir tam yenileme konur. Farklı hesaplar birbirinin veritabanı işine katılmaz; mevcut HTTP kuyruğunun sağlayıcı dostu seri erişim politikası korunur.

Senkron hataları artık yutulmaz. Ağ, yanıt doğrulaması, SQL veya iptal hatası çağırana ulaşır; `isDone` ve tam yenileme zamanı yazılmaz. İlk hatada işlem durur: önceki başarılı içerik türleri güncellenmiş olabilir, sonraki türler henüz denenmez. Bu, bütün hesabı tek transaction içinde yeniden yazan bir model değildir.

Başlangıç provider’ındaki gizli tam senkron fallback’i ve Riverpod hata tekrarları kapatıldı. Kullanıcı açıkça tekrar deneyebilir. Dashboard elle yenilemesi artık bitmiş eski Future’ı okumaz; seçilen hesap için yeni tam yenileme başlatır. Hesap sonradan değişse de istenen hesap ID’si korunur.

## Süre ve iptal sınırları

| İş | Sınır |
| --- | --- |
| Xtream GET: ilk deneme + tekrar | En fazla **2 girişim**, gönderim başladıktan sonra toplam **75 saniye** |
| M3U GET: ilk deneme + tekrar | En fazla **2 girişim**, toplam **90 saniye** |
| Aktif katalog senkron işi | Kuyruk beklemesi, indirme ve uygulama dahil **5 dakika** |
| Geçici hata tekrarı öncesi bekleme | **400 ms**, kalan bütçe uygunsa |

Timeout, bağlantı hatası ve 429/500/502/503/504 geçici sayılır. Kimlik doğrulama/kalıcı HTTP hataları ve iptal tekrar edilmez. HTTP süre sınırı veri akışı kesilmeden sürse bile işler; yalnız socket receive timeout’una dayanmaz. Küçük işin arkasına açıkça istenmiş tam yenileme, sıra kendisine geldiğinde kendi 5 dakikalık bütçesini başlatır; çağıranın toplam beklemesi bu iki işi içerebilir. Senkron dışındaki HTTP kuyruğu beklemesi 75 saniye sınırına dahil değildir.

Giriş senkron ekranlarına **İptal** eklendi. Aktif HTTP isteğine Dio CancelToken ile iptal iletilir. Süre dolmuş kuyruk işi sıra kendisine geldiğinde HTTP isteği başlatmaz. `Future.timeout` arka plan kodunu kendiliğinden durdurmadığı için DB yazma sınırında da işlem bütçesi denetlenir. Geç dönen sonuçlar yeni kayıt yazamaz. İptal hesabı silmez; mevcut başarılı kayıtlar korunur.

Dart ana isolate’ını bloke eden ayrıştırma işi timer’ı geciktirebilir. Kontrol geri geldiğinde süre yeniden denetlenir ve geç yazma engellenir; arayüz akıcılığı için büyük M3U/XMLTV işlerini isolate’a taşıma B23 kapsamında hâlâ gereklidir.

## Veri uygulama ve güncellik

- Xtream satırları içerik türüne yazılmadan önce doğrulanır. Yanlış şekilli JSON, geçersiz içerik kimliği ve bozuk satır başarılı boş liste sayılmaz.
- Her Xtream türünün upsert/prune işlemi transaction içindedir. İkinci 500’lük grupta SQL hatası çıkarsa ilk grup da geri alınır. M3U kategori/kanal uygulaması tek transaction içindedir.
- Daha önce dolu bir katalog/kategori türüne boş liste gelirse eski kayıtlar korunur ve yenileme başarısız sayılır. Yeni hesapta hiç bulunmayan boş türler kabul edilir. Gerçekten tamamen kaldırılmış bir türü temizleme için doğrulanmış ayrı bir boş-katalog politikası gelecekte eklenebilir.
- Xtream tam yenilemesi detay kaydındaki plot/container gibi listede verilmeyen alanları ve kategori gizliliğini korur. M3U metadata güncellemesi B21’in kalan kapsamıdır.
- Tam Xtream yenilemesi yalnız katalog kademeleri 1/2/3’ü güncel sayar. Dizi bölüm sayısı kontrolü yapılmadan kademe 4 işaretlenmez. Başarısız bölüm yanıtında kademe 4 açık kalır; aynı diziyi izleyen profiller ayrı takip edilir.
- Eski SyncMetadata mutex’i kaldırıldı. Çalışan iş ve bekleyenler tek SyncCoordinator tarafından yönetilir; SyncMetadata yalnız hesap bazlı kalıcı zaman/sayaç tutar.

## Doğrulama

**353 Flutter testi geçti**; önceki 325 teste 28 dayanıklılık/koordinasyon testi eklendi:

- Aynı işte giriş + manuel + otomatik çağrı, paylaşılan ilerleme ve hata; daha küçük işin arkasına tek tam yenileme.
- İki hesabın bağımsız ilerlemesi; iptalin bekleyen tam yenilemeyi de durdurması.
- Kalıcı timeout için tam iki girişim; ikinci girişimde başarı; 401 için tek girişim; takılmış taşımanın deadline/cancel ile durması.
- Kuyrukta süresi dolan isteğin HTTP’ye hiç çıkmaması; JSON hata nesnesinin boş başarıya dönüşmemesi.
- Ağ hatası/bozuk satır/boş eski katalog/ikinci SQL grubu hatasında veri ve güncellik kontrolü.
- M3U tek indirme, transaction rollback ve iptalden sonra geç parse sonucu.
- Dizi kontrolünde hata/iki profil; manuel provider’ın doğru hesap ID’si; başlangıç hatasında fallback/otomatik tekrar olmaması.

`dart analyze lib test tool`: **0 hata, mevcut 6 uyarı ve 17 bilgi**. Bu paket yeni analiz uyarısı bırakmadı. Linux x64 release derlemesi başarılı; ayrı XDG veri/tercih dizinleri ve Xvfb ile 12 saniyelik açılış kontrolü geçti. Şema 26, varsayılan profil ve 18 hesap kapsamlı tablo doğrulandı. Xvfb DRI3/erişilebilirlik uyarıları nedeniyle bu kontrol GPU/VOD performans ölçümü sayılmaz.

Kanıtlar `sync-fixes-2026-09-23/` altındadır. Testler sentetik verilerle yapıldı; gerçek sağlayıcı ve diğer platformlarda uzun süreli cihaz denemesi yapılmadı. Güncel release çalıştırıcısı `tool/run_linux_release.sh`.

## Açık kapsam

EPG/XMLTV indirme-uygulama ve LAN senkronu bu katalog koordinatörünün iş türleri değildir. Bunların hata/iptal, eşleme ve bellek politikaları ayrı kalır. M3U kimlik çakışmaları, büyük katalogda SQLite parametre/bellek sınırları, ayrıştırmayı isolate’a taşıma ve gerçek sağlayıcı performans ölçümleri sonraki pakete aittir. Günlük sayaçların yaklaşık istek muhasebesi bu değişiklikte baştan tasarlanmadı. [Kalan işler](KALAN_ISLER_2026-09-23.md).
