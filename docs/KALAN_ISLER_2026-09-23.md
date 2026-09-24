# Güncel iş takibi — 24 Eylül 2026

Bu dosya güncel durumu gösterir; önceki raporların tarihsel açık maddelerini tekrar etmez. **Bütün işlerin tamamlandığı veya tüm platformların kusursuz çalıştığı iddia edilmez.**

## Uygulanan paketler

| Alan | Durum ve kanıt |
|---|---|
| Player oturumu, sarma, tam ekran, üstte tutma, Linux VOD takılması | Uygulandı; [player ve Linux raporları](LINUX_VOD_AKICILIK_DUZELTMESI_2026-09-23.md). Kullanıcı Linux düzeltmesini olumlu doğruladı. |
| Hesap/profil kapsamı, yedek geri yükleme | Şema 26/27, yedek v4, eski yazıcı iptali; [veri bütünlüğü](VERI_BUTUNLUGU_2_2026-09-23.md). |
| Senkron retry, bütçe, iptal, ortak iş, M3U ID ve XMLTV cache | [Senkron](SENKRON_DAYANIKLILIK_2026-09-23.md), [M3U/XMLTV](M3U_XMLTV_DAYANIKLILIK_2026-09-23.md). 100 bin kayıt fixture’ı testli. |
| Dizi/sezon/bölüm ve geçmiş | M3U ortak model, gerçek bölüm URL/ID, profil kapsamı; [dizi/canlı/odak](DIZI_CANLI_TV_ODAK_2026-09-23.md). |
| Odak/D-pad, arama, PIN ve görünürlük | Sayfa kapsamlı kayıt, sidebar/panel/grid geri akışları, player→detay→grid, ayarlar ve temizlenen sorgu testli. Fiziksel kumanda kabulü açık. |
| Sağlayıcı başlıkları, alt dizinli Xtream, M3U dönüşümü | [Yeni paket](SAGLAYICI_AI_TV_2026-09-23.md); şema 28. |
| TV ses seçimi, AI arka plan yükü, embedding, Cast/altyazı sınırları | [Yeni paket](SAGLAYICI_AI_TV_2026-09-23.md); kapsam sınırları raporda. |
| Android TV Cast/DLNA kumanda akışı | Cast odağı, geri dönüş, uzak oynatma durumu ve tek bağlantı öncesi ExoPlayer kapatma uygulandı; [doğrulama](TV_CAST_2026-09-24.md). |
| Bildirim izin/receiver, iOS izinleri, Apple CI, Android signing | Kod uygulandı. Gerçek OS teslimi, Apple CI sonucu ve mağaza imzaları ayrıca doğrulanmalı. |

## Henüz tamamlanmayan uygulama işleri

1. **Android TV özellik eşliği:** M3U catch-up şablonları ve fiziksel kumanda kabulü. Cast arayüzü/odak dönüşü [son pakette](TV_CAST_2026-09-24.md), Xtream geçmiş EPG/canlıya dönüş [catch-up paketinde](TV_CATCHUP_2026-09-23.md), kanal/EPG, kalite ve native altyazı [TV panel paketinde](TV_PLAYER_PANELLER_2026-09-23.md) uygulandı.
2. **LAN aktarımı:** doğrulanmış şifreli eşleme/taşıma ve gerçek eş cihaz kabulü. Sır paylaşımı açık seçime bağlandı, profil birleştirme hatası ve gövde sınırları [son pakette](SENKRON_MEDYA_SON_PAKET_2026-09-23.md) düzeltildi. HTTP hâlâ şifreli değildir.
3. **Platform özellikleri:** iOS gerçek PiP; masaüstünde planlı bildirim; fiziksel cihazdaki teslim/tıklama akışı.
4. **Büyük katalog UI:** ekran dışı abonelik/animasyon maliyetinin geniş ölçümü ve XMLTV ağdan veritabanına uçtan uca streaming. XML olay ayrıştırması ve işçi iptali son pakette uygulandı. Lazy bölüm listesi ve tam katalog arama sıralaması [katalog paketinde](KATALOG_PERFORMANSI_2026-09-23.md) uygulandı.
5. **Cast/DLNA:** gerçek alıcı ve tek bağlantılı sağlayıcı kabulü. TV arayüzünde yerel ExoPlayer uzak LOAD öncesi bırakılıyor; DLNA seek/geri dönüş konumu ile Chromecast konum/mediaSessionId yolları uygulandı. Başlık gerektiren sağlayıcı URL'leri ve codec uyumu gerçek alıcıyla doğrulanmalı.
6. **AI kalite ölçümü:** Türkçe sorgu veri seti, öneri doğruluğu/maliyet/gecikme için canlı model ve insan değerlendirmesi. Eşzamanlı metadata/embedding yarışı transaction içinde kaynak girdisi karşılaştırmasıyla kapatıldı.
7. **Eski şema teknik borcu:** tüm eski/sapmış sürümlere geçiş öncesi yedek ve daha geniş fixture matrisi.

## Cihazla doğrulanması gerekenler

- Android telefon ve düşük RAM’li Android TV: kumanda/uzun basma, sidebar↔panel↔grid, ses/altyazı, codec/HDR, arka plan, PiP, kanal değiştirme.
- Linux farklı GPU ve sürücüler: uzun 4K/yüksek bitrate/HLS oynatma, düşen kare, A/V farkı, CPU/GPU/tepe bellek. Native Wayland üstte tutma davranışı.
- Windows, macOS, iPhone: kurulum/açılış, tam ekran/dönüş, izinler, ses/video, bildirim ve ağ kesintisi.
- Gerçek Xtream/M3U hesapları, Cast/DLNA alıcısı ve LAN eş cihazlarıyla kabul.

Kod testi, debug APK veya imzasız Apple CI derlemesi bu cihaz testlerinin yerine geçmez. Güncel otomatik doğrulama [TV Cast paketinde](TV_CAST_2026-09-24.md) tutulur.
