# LAN, DLNA, XMLTV ve AI kayıt bütünlüğü — 23 Eylül 2026

## LAN aktarımı

API anahtarları ve PIN'ler otomatik senkronizasyon paketine artık eklenmez; eski eş cihazdan gelen Gemini anahtarı da otomatik benimsenmez. Elle aktarımda bunlar ayrı, varsayılan olarak kapalı bir seçimdir. Genel ayar aktarımı yerel API anahtarını, ebeveyn PIN'ini ve ebeveyn kilidinin etkinliğini değiştirmez. Profil PIN'i ancak hem profil hem sır aktarımı seçilirse gönderilir. Hesap oturum bilgileri ayrı hesap kategorisinde kalır. Arayüz yerel bağlantının şifrelenmediğini açıkça belirtir; bu paket TLS sağladığı iddiasında değildir.

Favoriler ve izleme geçmişi kaynak profil adlarıyla eşleştirilir. Birden fazla bilinmeyen profil aktif profile yığılmaz. Belirsiz aktarım reddedilir; hesap/profil/favori/geçmiş veritabanı yazıları transaction içinde geri alınır. Referans taşımayan eski cihazda yalnızca tek kaynak profil varsa aktif profile eşleme korunur.

Gelen eşleme isteği 64 KiB/10 saniye, senkron JSON'u 16 MiB/30 saniye ile sınırlıdır. Parçalı ve sürekli yavaş akan gövdelerde de toplam süre/boyut sınırı uygulanır ve akış iptal edilir. Manuel export ve otomatik sync yanıtları da sınırlı akış okuyucusundan geçer. Manifest/trust yanıtı için daha geniş protokol sertleştirmesi ve doğrulanmış şifreli eşleme hâlâ ayrı iştir.

## DLNA

VOD devri yerel konumu `Seek` / `REL_TIME` ile alıcıya taşır. Canlı yayında sarma gönderilmez. `GetPositionInfo` ile konum iki saniyede bir, çakışan istek açılmadan izlenir; bağlantı kesilmeden son konum alınır ve yerel oynatıcı buradan devam eder. Desteklenmeyen/bozuk konum yanıtı sıfır kabul edilmez. Eski alıcı oturumunun geciken yanıtı yeni oturuma yazamaz. `TRANSITIONING` tek başına oynatmanın başladığı kabul edilmez. Protokol dayanağı: [UPnP AVTransport, Seek ve GetPositionInfo](https://upnp.org/specs/av/UPnP-av-AVTransport-v3-Service.pdf).

SOAP sahte alıcı testleri, devir/sarma argümanlarını, son konumun korunmasını, namespace içeren yanıtı, hatalı/eksik konumu ve geç yanıtı kapsar. Gerçek DLNA/Chromecast alıcısı ve tek bağlantılı sağlayıcı kabulü henüz yapılmadı.

## XMLTV

Tüm feed için DOM kurmak yerine XML olayları sırayla işlenir. Ayrıştırıcı yalnızca geçerli programın alanlarını toplar; entity, iç içe metin, CDATA ve ilk dil davranışı korunur. Hatalı XML kuyruğu kısmi program listesinin yayınlanmasına neden olmaz. Ayrıştırma ayrı isolate'da yapılır; yenileme/cache temizleme eski indirmeyi kapatır ve işçiyi durdurur. Senkron bütçesi iptali de işçiyi sonlandırır.

50.000 programlık eşit çıktı karşılaştırmasında DOM işçisi 798 ms, olay işçisi 471 ms sürdü (yaklaşık %41 daha kısa). Ana timer'ın en uzun aralığı 20,6 → 11,1 ms oldu. [Ölçüm](sync-media-2026-09-23/xmltv-benchmark.json). RSS bütün test sürecini içerir; izole tepe bellek ölçümü değildir. Ağ verisi hâlâ 64 MiB sınırıyla tamponlanır: ağdan veritabanına uçtan uca streaming tamamlanmış sayılmaz.

## AI vektör kaydı

Model yanıtı beklenirken kanal/enrichment metni değişirse eski vektör reddedilir. Model girdisinin tamamı yeniden okunur ve vektör tek SQLite transaction içinde karşılaştırılıp yazılır. Güncelleme commit'ten sonra gelirse mevcut invalidate trigger'ları vektörü siler. Silinen içerik, aynı sayısal ID'yi kullanan başka tür/hesap ve iptal edilmiş iş için regresyonlar eklendi. Bu veri tutarlılığı düzeltmesidir; model önerilerinin insan değerlendirmesindeki kalitesinin ölçüldüğü anlamına gelmez.

Tam test/derleme ve kalan sınırlar [doğrulama dosyasında](sync-media-2026-09-23/validation.json), tüm proje açık işleri [güncel listede](KALAN_ISLER_2026-09-23.md) tutulur.
