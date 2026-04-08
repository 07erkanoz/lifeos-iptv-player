
# LifeOS IPTV Player
Flutter ve media_kit kütüphanesi üzerine kurulu, minimalist ve performans odaklı bir IPTV oynatıcı. Proje; Windows, Linux ve Android platformlarında, özellikle hantal ve reklam içeren mevcut çözümlere karşı hafif bir alternatif oluşturmayı hedefler.

## Platform Durumu ve Özellikler
 * **Linux & Windows:** Masaüstü ortamlarında stabil çalışma. Yerel pencere yönetimi ve akıcı liste kaydırma deneyimi.

 * **Android Mobil:** Dokunmatik arayüz desteği ve donanım hızlandırmalı video oynatma.
 * **Android TV:** Uygulama platformda derlenip çalışmaktadır, ancak D-Pad (kumanda) navigasyon ve odaklanma (focus) yönetimi henüz tamamlanmamıştır (Çalışmalar devam etmektedir).

## Teknik Stack
 * **Görüntüleme:** Flutter
 * **Video Motoru:** media_kit (Native libmpv backend) sayesinde geniş codec ve format desteği.
 * **Performans:** Devasa M3U listelerini kullanıcı arayüzünü kilitlemeden, lazy-loading prensibiyle işleme.
## Bilinen Sorunlar ve Yol Haritası
 * Android TV için D-Pad navigasyon mantığının kurulması (Katkı bekleniyor).
 * Xtream Codes API entegrasyonu.
 * EPG (Elektronik Program Rehberi) desteği.
## Kurulum ve Çalıştırma
Projeyi yerel ortamınızda çalıştırmak için:
```bash
flutter pub get

# Hedef platformun derleme gereksinimlerini (örn: libmpv) karşıladığınızdan emin olun.
flutter run

```
## Katkıda Bulunma
Özellikle Android TV focus sorunları veya video motoru optimizasyonu konularında katkılarınızı memnuniyetle kabul ederim. Hata bildirimleri veya özellik istekleri için issue açabilirsiniz.

**Lisans:** MIT
###