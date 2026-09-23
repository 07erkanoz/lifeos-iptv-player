# Dizi, canlı TV, odak ve arama düzeltmeleri — 23 Eylül 2026

Bu paket önceki veri/senkronizasyon çalışmasını sürdürür. TiViMate kullanım isteği için kumandayla yönlendirme kuralları uygulandı; TiViMate ile gerçek Android TV üzerinde birebir karşılaştırma yapılmadı.

## Dizi oynatma ve geçmiş

- M3U bölümleri hesap/kategori/dizi adına göre, sayfalama yapılmadan önce gruplanıyor. S01E02, 1x02 ve Türkçe sezon/bölüm adları tanınıyor. Tanınmayan adlar bağımsız içerik kalıyor.
- Ortak model Xtream harita/liste yanıtlarını, sayısal/string ID’leri, sezon sırasını ve geçersiz kayıtları normalize ediyor.
- M3U detay ekranı sezon/bölüm listesini doğrudan katalogdan oluşturuyor; URL ve token korunuyor. Kayıtlı konum, sonraki/önceki bölüm ve sezon sınırı geçişi çalışıyor.
- Bölüm ilerlemesi `series`, Xtream dizi özeti `series_parent` olarak ayrıldı. Aynı sayısal dizi/bölüm ID’si birbirinin geçmişini ezmiyor; yazımlar tek transaction içinde. Eski dizi geçmişi yeni özet gelene kadar okunuyor.
- Hesap/profil değişiminde eski detay sonucu uygulanmıyor. Eksik Xtream detayına rastgele başka dizi seçen geri dönüş kaldırıldı.
- Çok bölümlü geçmiş sorguları 500 ID’lik gruplar kullanıyor.

M3U dizi kartının kimliği ilk sıralı bölümden gelir; sağlayıcı bu bölümü siler veya daha erken bölüm eklerse temsilci kart değişebilir. Bölümlerin kalıcı kimliği ve izleme ilerlemesi korunur. Belirsiz adların doğru gruplanması sağlayıcı metadata’sına bağlıdır.

## Kumanda ve odak sözleşmesi

| Konum | İşlem | Sonuç |
|---|---|---|
| Ana menü | Sağ | Etkin sayfanın içeriği veya o sayfada açık detay |
| Film/dizi detay | Player’dan geri | Detayın oynat/devam et düğmesi |
| Film/dizi detay | Geri | Önceki poster ve liste konumu |
| Grid / canlı kanal listesi | Sol veya geri | Kategori panelini aç/odakla |
| Canlı EPG | Geri | Kanal listesi |
| Kategori paneli | Geri | Ana menü |
| Ayarlar bölümü | Sağ | Seçili bölümün kontrolleri |
| Ayarlar kontrolleri | Geri | Aynı bölümün menü öğesi |
| Ayarlar menüsü | Sol | Ana menü |
| Dizi player | Yukarı/aşağı, sağ/sol, OK | Bölüm düğmelerine gir, seç ve çalıştır |

Odak ve geri işlemleri artık sayfa anahtarıyla kayıtlı. IndexedStack içinde görünmeyen bir detay başka sayfanın odağını veya geri tuşunu alamıyor. Detayın arkasındaki grid ve gizlenen player kontrolleri odak dolaşımından çıkarıldı. Kapanış sırasında Riverpod `ref` erişim hatası giderildi. Ayarlar seçili bölümü hatırlıyor; uzun menü etiketleri taşmıyor.

## Canlı TV ve EPG

- “Tümü” listesindeki sessiz 500 kanal sınırı kaldırıldı; görünür satırlar sanal listeyle oluşturuluyor.
- Oynatma URL’si ortak çözümleyiciden geçiyor: Xtream doğrudan kaynak, M3U URL ve hesap doğrulaması korunuyor; eksik M3U URL’si yanlış Xtream URL’sine çevrilmiyor.
- TV player canlı kanal geçmişini kaydediyor; kanal değişiminde eski ilerleme doğru kanala yazılıyor.
- Görünür satır EPG istekleri hesap/kanal bazında birleşiyor. Başarısız istek 30 saniye sonra yeniden denenebilir; süreç boyu kalıcı başarısızlık işareti yok.
- EPG sorgu zamanı 30 saniyede yenileniyor. Tam EPG işi aynı hesap/veritabanı için paylaşılır; üç dakikalık bütçe ve iptal geç yazımları engeller.
- Yalnızca gerçekten yazılmış programlar tam EPG yenileme zamanını günceller. Kısmi kanal yenilemesi bütün rehberi iki saat engellemez. Yenile düğmesi XMLTV önbelleğini de zorla yenileyebilir.

## Arama ve AI erişimi

- Sorgu temizlenince eski normal/AI sonuç ve öneriler geçersiz kalıyor; eski istek yeni isteğin yüklenme durumunu değiştiremiyor.
- AI sıralaması sağlayıcı ID’leri yerine istek içindeki benzersiz aday numaralarını kullanıyor. Film/dizi/canlı ID çakışmaları sonuçları ezmiyor; önbellek anahtarı adayların gerçek içeriğini içeriyor.
- Kısmen doldurulmuş indeks yeni, henüz indekslenmemiş eşleşmeleri tamamen gizlemiyor. Senkron ve detay metadata değişimleri eski arama metnini geçersiz kılıyor.
- AI araçlarının içerik çözümlemesi hesap, tür, kategori gizliliği ve yetişkin filtresinden geçiyor. Türü bilinmeyen, birden fazla içerikle eşleşen ID reddediliyor.
- AI profil değiştirme aynı yerel PIN diyaloğunu kullanıyor. PIN modele gönderilmiyor. Hesap/profil değişiminden sonra önceki AI turunun araçları/sonuçları uygulanmıyor; sohbet geçmişi kapsam değişiminde temizleniyor.

## Doğrulama ve sınırlar

**397 Flutter testi geçti.** Analizde 0 hata, 0 uyarı ve 16 bilgi düzeyi bildirim var. Linux release ve ayrı geçici veri dizininde 12 saniyelik Xvfb açılış kontrolü geçti. Sayısal sonuçlar `navigation-fixes-2026-09-23/validation.json` dosyasında.

100 bin bölüm / bin dizi sentetik testinde ana iş parçacığındaki en uzun zamanlayıcı aralığı 360,081 ms → 48,990 ms; toplam gruplama 349,969 ms → 403,286 ms. İşçi kopyalama maliyeti vardır. Bu değerler çizilmiş kare süreleri veya Android TV cihaz ölçümü değildir. RSS test sürecini ve tutulan girdileri de içerir; bellek tasarrufu iddiası yoktur.

Gerçek Android TV kumandası, sağlayıcı yayını, Cast/DLNA alıcısı, Apple/Windows cihaz testi bu paketle tamamlanmış sayılmaz. Kalan sağlayıcı başlıkları, native TV ses/altyazı kontrolleri, embedding/AI arka plan iş yükü, LAN güvenliği ve platform yayın işleri ana takip belgesinde açık tutulur.
