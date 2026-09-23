# Güncel iş takibi — 23 Eylül 2026

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
| Bildirim izin/receiver, iOS izinleri, Apple CI, Android signing | Kod uygulandı. Gerçek OS teslimi, Apple CI sonucu ve mağaza imzaları ayrıca doğrulanmalı. |

## Henüz tamamlanmayan uygulama işleri

1. **Android TV özellik eşliği:** Cast ve catch-up. Kanal/EPG, kalite ve native altyazı kodu [TV panel paketinde](TV_PLAYER_PANELLER_2026-09-23.md) uygulandı; fiziksel TV kabulü açık.
2. **LAN aktarımı:** doğrulanmış şifreleme, sır paylaşımını açık seçime bağlama ve tüm profil eşleme uç durumları. Rastgele token/PIN süre sınırı uygulandı; HTTP güvenliği kapanmadı.
3. **Platform özellikleri:** iOS gerçek PiP; masaüstünde planlı bildirim; fiziksel cihazdaki teslim/tıklama akışı.
4. **Büyük katalog UI:** gerçek lazy bölüm listesi; tam katalog arama sıralaması; ekran dışı abonelik/animasyon maliyetinin geniş ölçümü; XMLTV streaming parser ve çalışan işçiyi anında iptal.
5. **Cast/DLNA:** DLNA seek/geri dönüş konumu, receiver kabulü ve tek bağlantılı sağlayıcı davranışı. Chromecast konum ve mediaSessionId yolu uygulandı, alıcı cihaz kabulü açık.
6. **AI kalite ölçümü:** Türkçe sorgu veri seti, öneri doğruluğu/maliyet/gecikme, metadata yenilenirken eşzamanlı embedding yazımı için daha güçlü kaynak sürümlemesi.
7. **Eski şema teknik borcu:** tüm eski/sapmış sürümlere geçiş öncesi yedek ve daha geniş fixture matrisi.

## Cihazla doğrulanması gerekenler

- Android telefon ve düşük RAM’li Android TV: kumanda/uzun basma, sidebar↔panel↔grid, ses/altyazı, codec/HDR, arka plan, PiP, kanal değiştirme.
- Linux farklı GPU ve sürücüler: uzun 4K/yüksek bitrate/HLS oynatma, düşen kare, A/V farkı, CPU/GPU/tepe bellek. Native Wayland üstte tutma davranışı.
- Windows, macOS, iPhone: kurulum/açılış, tam ekran/dönüş, izinler, ses/video, bildirim ve ağ kesintisi.
- Gerçek Xtream/M3U hesapları, Cast/DLNA alıcısı ve LAN eş cihazlarıyla kabul.

Kod testi, debug APK veya imzasız Apple CI derlemesi bu cihaz testlerinin yerine geçmez. Güncel otomatik doğrulama [kanıt dosyasında](tv-controls-2026-09-23/validation.json) tutulur.
