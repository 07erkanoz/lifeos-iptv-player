# Veri bütünlüğü 2 — hesaplar arası izolasyon

23 Eylül 2026. Önceki [yedekleme ve hesap seçimi paketinin](VERI_BUTUNLUGU_1_2026-09-23.md) devamı. B03 için uygulama ve otomatik testler tamamlandı; gerçek sağlayıcılarla platform kabul denemeleri açık.

## Değişen davranış

A hesabında film 42 favoriye eklenip izlendikten sonra B hesabına geçmek artık A’nın kataloğunu, favorilerini veya geçmişini silmez. B’de aynı 42 numarası bulunsa da kayıtlar bağımsızdır. A’ya dönüldüğünde her profil kendi kayıtlarını görür. Hesap silmek yalnız seçilen hesaba ait satırları temizler; aktif hesap silinirse kalan bir hesap etkinleşir.

18 içerik/kullanıcı/cache tablosuna `account_id` eklendi. Sağlayıcının verdiği doğal anahtarlar hesap kimliğiyle genişletildi; profil kapsamındaki tablolar profil kimliğini de korur. EPG ve AI günlükleri otomatik üretilen global satır kimliklerini korur, sorgular hesapla filtrelenir. Hesap ve profil kayıtları ile yedek kurtarma günlüğü globaldir.

Normal uygulama sorguları sabit hesap kimlikli DB nesnesi kullanır. SELECT, JOIN, UPDATE, DELETE ve toplu yazmalar bu kapsamı uygular. LEFT JOIN filtresi ON koşulundadır; başka hesapta eşleşen metadata bulunması satırın kaybolmasına veya karışmasına yol açmaz. Ham Drift batch yalnız global yedek/registry bağlantısında kullanılır. Hesap değiştiğinde provider yeni nesneyi verir; eski sorgu/arka plan işi kendi hesabında kalır.

## Senkronizasyon, player ve cache

- Devam eden A senkronunun B’ye geçildikten sonra dönen yanıtı A’ya yazılır. Senkron zamanları ve kademeli senkron kilidi hesap bazlıdır; B, A’nın son senkron zamanından etkilenmez.
- Hesap silme ve yedek geri yükleme eski yazıcıları geçersiz kılar. Önceden hazırlanmış DELETE, bekletilmiş batch ve eski nesneden yeni hesap nesnesi türetme de engellenir. Geri yükleme aynı hesap ID’sini korusa bile provider yenilenir.
- Player rota verisi açıldığı hesabı taşır. İzleme konumu/intro deposu, EPG aboneliği ve geçmiş yayın için kullanılan hesap oturum boyunca korunur. URL çözümleyicisi farklı hesaba ait içerikle açılmayı reddeder.
- AI rail ve kişisel kart snapshot anahtarları hesap/profil kapsamına alındı. Katalog, metadata, embedding, arama geçmişi ve AI geri bildirim sorguları hesap filtresinden geçer. AI’nin bütün görünürlük/PIN/tür eşleme sorunlarının çözüldüğü iddia edilmez.
- Hesapla başlayan kategori, katalog, sıralama, favori, geçmiş ve EPG indeksleri eklendi. SQLite sorgu planı testleri katalog/EPG erişiminde ilgili indeksleri doğrular. Büyük kataloglarda uçtan uca süre/bellek ölçümü bu pakette yapılmadı.

## Şema 26 ve yedek v3

`ONEMLI.md` kuralı uyarınca anahtar değişikliği yalnız kolon eklemekle yapılmadı: Drift `TableMigration` kullanılarak transaction içinde oluştur–kopyala–değiştir akışı uygulandı. Gerçek eski tablo yapılarıyla v23, v24 ve v25 geçişleri test edildi. Eksik kolon/yanlış anahtar açılışta denetlendiği için yarım/eski şema tekrar değerlendirilebilir.

Eski global katalog ve kullanıcı satırları o sırada DB’de aktif olan hesaba atanır; birden çok aktif satır varsa en büyük ID seçilir. Aktif hesap yoksa satırlar 0 rezerv kapsamıyla korunur, başka hesaba tahminen bağlanmaz. Eski sürümlerin önceden sildiği veriler geri üretilemez. Yeni yedek hesabı bilinmeyen pozitif ID’li satırları reddeder.

Yedek v3 her kullanıcı satırının hesap kimliğini taşır. v1/v2 okuma desteği sürer; eski kapsamı olmayan kayıtlar yedekteki aktif sahibine aktarılır. Katalog ve türetilmiş cache yeniden oluşturulur. Önceki paketin tercih kurtarma günlüğü korunur.

## LAN uyumluluğu

İçerik yüküne kaynak hesabı belirten tür/adres/kullanıcı eşleşmesi eklendi; parola bu kimliğin parçası değildir. Elle içe aktarma, yereldeki karşılık gelen hesabı bulur; o sırada ekranda başka hesap açık olması hedefi değiştirmez. Otomatik birleştirme kendi hesabıyla eşleşmeyen yükü uygulamaz. Hesap kimliği taşımayan eski sürümden içerik aktarımı reddedilir; iki cihaz da güncellenmelidir.

Bu değişiklik B34’ün hesap ayrımı kısmını ele alır. Profil adından eşleme, M3U içerik kimliğinin cihazlar arasında kararlılığı ve B35 şifreli/güvenli eşleme protokolü halen açıktır.

## Doğrulama

- **325 Flutter testi geçti**; bu paket 21 hesap kapsamı testi ve 1 yanlış hesapla oynatma testi ekledi.
- A→B→A, iki profil, aynı sağlayıcı ID’si, upsert/batch/update/delete, gerçek repository JOIN’i, sabit stream aboneliği ve reaktif hesap değişimi test edildi.
- Geciken sağlayıcı yanıtı, hesap silme, restore sonrası eski yazıcı/batch reddi ve aynı hesap ID’siyle provider yenilenmesi test edildi.
- v3 çok hesaplı yedek döngüsü, v2 aktarımı, bilinmeyen hesap reddi, v23/v24/v25 şema geçişleri ve önceki paketin rollback/kurtarma testleri geçti.
- Yerel HTTP sunucusuyla LAN eşleşen/eşleşmeyen/kimliği eksik yük senaryoları geçti.
- `dart analyze lib test tool`: **0 hata, mevcut 6 uyarı ve 17 bilgi**. Uyarılar YouTube fragman servisi, dashboard yinelenen importları ve kullanılmayan detay ekranı parametrelerindedir.
- **Linux x64 release derlemesi geçti.** Xvfb altında ayrı XDG veri/tercih dizinleriyle 12 saniyelik açılış kontrolü geçti: uygulama açık kaldı, şema 26, varsayılan profil ve 18 hesap kapsamlı tablo doğrulandı. Sanal ekran DRI3/erişilebilirlik uyarıları verdi; bu kontrol GPU/VOD akıcılığı testi değildir.
- Android, Windows, macOS ve iPhone’da bu paket için gerçek cihaz doğrulaması yapılmadı. Linux’ta gerçek sağlayıcı hesabı ve uzun oynatma denemesi de bu turda yapılmadı.

Kanıt kayıtları: `data-fixes-2-2026-09-23/`. Test verileri sentetiktir; kullanıcının gerçek hesapları/yedekleri otomatik testlere alınmadı.

## Sıradaki işler

1. B01/B02/B22: tüm senkron giriş yollarını tek koordinatörde birleştirme, hata/timeout bütçesi ve başarısız yenilemenin başarılı işaretlenmesini engelleme. Bu paketteki hesap kilidi tüm manuel/otomatik yolları birleştirmiş sayılmaz.
2. B06/B07/B08: M3U içerik kimliği çakışmaları, dizi/bölüm geçmişi ve M3U dizi akışı.
3. B20/B29: AI üzerinden açılan içerikte profil PIN’i, görünürlük ve içerik türü eşlemesi.
4. Gerçek hesaplarla Linux A→B→A, uygulamayı kapatıp açma, yedek geri yükleme ve player açıkken hesap değişimi; ardından diğer platformlar.

Geniş takip listesi: [Kalan işler](KALAN_ISLER_2026-09-23.md).
