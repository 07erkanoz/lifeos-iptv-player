
# LifeOS IPTV Player
Flutter ve media_kit (libmpv) altyapısı üzerine kurulu, performans odaklı çapraz platform IPTV oynatıcı. Proje, şişirilmiş ve reklam barındıran uygulamalara karşı hafif, hızlı ve yüksek uyumluluk sunan bir alternatif olarak geliştirilmiştir.
## Platform Durumu
 * **Linux & Windows:** Masaüstü ortamlarında stabil çalışma. Yerel pencere yönetimi ve akıcı liste kaydırma deneyimi.
 * **Android Mobil:** Dokunmatik arayüz desteği ve donanım hızlandırmalı video oynatma sorunsuz çalışmaktadır.
 * **Android TV:** Uygulama çalışmaktadır ancak D-Pad (kumanda) navigasyon ve odaklanma (focus) yönetimi şu an için sorunludur.
## Desteklenen Özellikler
 * **Xtream Codes API:** Tam destek. Kullanıcı girişi ve kategori çekme işlemleri sorunsuz çalışmaktadır.
 * **EPG (Elektronik Program Rehberi):** Tam entegre ve aktif olarak çalışmaktadır.
 * **Video Motoru:** media_kit (Native libmpv backend) sayesinde geniş codec ve format desteği, kasmayan canlı yayın deneyimi.
## Bilinen Sorunlar
 * Android TV için D-Pad navigasyon (focus) mantığının henüz sağlıklı çalışmaması. Bu konu üzerinde geliştirmeler devam etmektedir (Veya katkıda bulunmak isteyenler için öncelikli konudur).
## Kurulum ve Çalıştırma
Projeyi yerel ortamınızda derlemek için:
```bash
flutter pub get

# Hedef platformun derleme gereksinimlerini (örn: Linux/Windows için libmpv) karşıladığınızdan emin olun.
flutter run

```
## Katkıda Bulunma
Özellikle Android TV focus sorunları konusunda katkılarınızı veya PR'larınızı memnuniyetle kabul ederim.
**Lisans:** MIT
