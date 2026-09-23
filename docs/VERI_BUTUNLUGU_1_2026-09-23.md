# Veri bütünlüğü — yedekleme ve hesap seçimi

> Bu belge ilk paketin tarihsel kaydıdır. B03 ve hesap kapsamlı v3 yedek için [2. paket raporuna](VERI_BUTUNLUGU_2_2026-09-23.md) bakın.

## Bu pakette yapılanlar

**B04 — aktif hesap otoritesi:** `currentAccountProvider` artık veritabanındaki aktif hesabı kullanır. Önceden A varsayılan iken B eklemek, B kataloğunu A kimlik bilgileriyle oynatmaya yol açabiliyordu. Ayarlardaki hesap işareti de aynı aktif kaydı gösterir. Giriş ekranından seçim DB aktivasyonunu yapar; geçersiz hesap ID’siyle aktivasyon mevcut hesabı kapatmaz. Katalog/veri izolasyonunun tamamı aşağıdaki B03 kapsamında açık kalır.

**B05 — yedek formatı v2:** Hesap ve profil kimlikleri korunur. Tam geri yükleme ilgili tabloları değiştirdiği için ID’ler doğrudan geri yazılır; böylece `default_account_id`, aktif profil ve hesap bazlı EPG URL’leri doğru hesap/profilde kalır. Profiller, PIN/avatar bilgileri, favoriler, izleme listesi, izleme konumu, dizi takibi, intro işaretleri, AI geri bildirimi, arama geçmişi, kategori tercihleri ve silme kayıtları yedeklenir.

Bozuk/eksik tablolar, yinelenen anahtarlar, bilinmeyen profil referansları, desteklenmeyen sürüm, yanlış alan türleri ve negatif süreler yazma başlamadan reddedilir. Eski v1 yedekler desteklenir; eski formatta bulunmayan profil bilgileri geri üretilemez ve mevcut satırlar varsayılan profile alınır. Eski yedekte kaybolmuş bilgi bu değişiklikle kurtarılmış sayılmaz.

Katalog, EPG ve türetilmiş AI cache’leri yeniden üretileceği için geri yüklemede eski kayıtlar temizlenir; senkron zamanları sıfırlanır. Cihaz eşleme kimliği/güven anahtarları ve harici API anahtarları dışa aktarılmaz veya başka cihazdan içe alınmaz. Mevcut cihazdaki bu ayarlar korunur. Hesap giriş bilgileri ve profil PIN’leri, hesapların geri yüklenebilmesi için dosyada bulunmaya devam eder.

## Yarım kalan geri yüklemenin kurtarılması

DB şeması 25 yalnızca `backup_restore_journal` tablosunu ekler; mevcut tabloların anahtarları değişmez.

1. Mevcut tercihlerin kurtarma kaydı DB’ye kalıcı yazılır.
2. Tek DB transaction içinde veri geri yüklenir, tercihler yazılır ve kurtarma kaydı silinir.
3. Tercih veya SQL hatasında transaction geri alınır, eski tercihler kurtarma kaydından geri yazılır.
4. İşlem commit olmadan kapanırsa SQLite DB değişikliklerini geri alır. Sonraki açılış, uygulama provider’larını ve arka plan işlerini başlatmadan önce eski tercihleri kurtarır. Kurtarma yazımı da başarısız olursa kayıt silinmez; yeniden deneme ekranı açılır.

## Doğrulama

- Toplam **303 Flutter testi geçti**: önceki 279 teste 24 yeni test eklendi.
- İki hesap/üç profil, aynı film için üç ayrı favori ve izleme konumu, PIN/avatar, EPG URL’leri ve diğer kullanıcı tabloları round-trip testi.
- v1 uyumluluğu, bozuk yedeklerin mevcut veriyi koruması, SQL hatasında rollback, tercih yazma/geri alma hatası ve dosya DB yeniden açıldıktan sonra kurtarma testleri.
- Eski varsayılan A varken yeni Xtream/M3U B hesabının seçilmesi ve geçersiz hesap aktivasyonu testleri.
- v24 → v25 (kurtarma tablosu yok/önceden var) geçişleri ve v23 → güncel şema testleri.
- Yeni servisler/testler ve başlangıç kodunun hedefli analizi temiz. Tam analizde 0 hata; eski 6 uyarı/21 bilgiye ek olarak bir testte bildirilen süslü parantez uyarısı sonradan düzeltildi ve hedefli analiz temiz geçti.
- Linux release derlemesi başarılı. Bu turda çalışan kullanıcı uygulaması yeniden başlatılmadı ve gerçek kullanıcı yedeği içe aktarılmadı. Testler geçici/sentetik veritabanlarında çalıştı.

Kayıtlar: `data-fixes-2026-09-23/`. Testlerde ayrı geçici veritabanları açıldığı için Drift debug çıktısında birden fazla DB örneği uyarısı görülebilir; bunlar aynı dosyaya eşzamanlı erişmez.

## Henüz kapanmayan işler

**B03 açık:** Favori/geçmiş/katalog tablolarında hesap kimliği bulunmadığından hesap geçişindeki veri silme sorunu bu pakette çözülmüş sayılmaz. Sadece silmeyi kaldırmak hesapların aynı sağlayıcı ID’lerini birbirine karıştırır. Sonraki değişiklik; hesap kimlikli anahtarlar, güvenli tablo taşıması, bütün sorguların aynı hesap kapsamını kullanması ve eski arka plan işlerinin yeni hesaba sonuç yazmasını engelleyen koordinasyon olmalıdır. Bu yedekleme paketi söz konusu taşıma için koruma sağlar.

M3U kimlik çakışması, AI/PIN kapsamı, senkronizasyon koordinasyonu ve diğer platformlarda gerçek cihaz denemeleri de açık. Aktif arka plan işlerinin restore/hesap değişimi ile ortak koordinasyonu ayrı B22 çalışmasına dahildir; bu testler sağlayıcıya bağlı devam eden canlı senkron senaryosunu doğrulamaz.
