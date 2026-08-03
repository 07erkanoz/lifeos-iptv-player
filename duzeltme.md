# LifeOS IPTV Player — UI ve Performans İnceleme Raporu

## İnceleme özeti

- GitHub `main` dalı `4b5f714` commit'ine güncellendi.
- 223 otomatik test başarıyla geçti.
- `flutter analyze` derleme hatası üretmedi; ancak 31 uyarı ve bakım bulgusu mevcut.
- Mobil dizi/film detay ekranları ile masaüstü performans sorunları kaynak kod üzerinden incelendi.

## Öncelikli sorunlar

### 1. Bölüm isimleri eksik veya kısa görünüyor

`lib/presentation/screens/series/series_screen.dart` içindeki bölüm dönüştürme kodu yalnızca `ep['title']` alanını okuyor. IPTV sağlayıcıları bölüm adını `name`, `info.name` veya `info.title` alanlarında gönderebildiğinden gerçek bölüm adı kaybolabiliyor ve arayüz `Bölüm N` yedeğine düşüyor.

Bölüm kartında başlık `maxLines: 1` ile sınırlandırılmış. Sabit 120 px bölüm görseli ve diğer kontrollerden sonra mobil ekranda başlık için çok az alan kalıyor; uzun isimler erken kesiliyor.

**Öneri:**

- Repository katmanında `Episode` modeli oluşturulmalı.
- İsim alanları `title → name → info.title → info.name` sırasıyla normalize edilmeli.
- Mobil kartta başlık iki satıra çıkarılmalı.
- Geçersiz bölüm kimlikleri için doğrudan `int.parse` yerine güvenli dönüşüm kullanılmalı.

### 2. Sezon listesi mobilde üst üste ve düzensiz duruyor

Sezon düğmeleri `Wrap` içinde gösteriliyor. Aynı satırın sağında uzun “Sezonu izlendi işaretle” düğmesi yer aldığı için telefon ekranında sezonlara çok dar bir alan kalıyor. Çok sezonlu dizilerde düğmeler birden fazla dar satıra bölünüyor.

**Öneri:**

- Mobilde yatay kaydırılabilir sezon şeridi veya açılır sezon seçici kullanılmalı.
- “Sezonu izlendi işaretle” işlemi ayrı satıra ya da taşma menüsüne alınmalı.
- Masaüstünde çok sezonlu içerikler için tek satırlık yatay liste tercih edilmeli.

### 3. Dizi ve film detay ekranları tutarsız

Film ekranında özel bir mobil detay yerleşimi bulunuyor. Dizi ekranı ise mobilde masaüstü detay gövdesinin önemli bölümünü yeniden kullanıyor. Bu nedenle dizi detayında büyük başlıklar, D-pad odaklı düğmeler ve yoğun bilgi blokları telefonda sıkışıyor.

**Öneri:** Film ve dizi için ortak bir responsive detay iskeleti oluşturulmalı. Poster, başlık, bilgi etiketleri, işlemler ve açıklama aynı tasarım sisteminden gelmeli.

### 4. Responsive karar ekran genişliği yerine platforma bağlı

Yerleşim seçimi büyük ölçüde Android/Windows platform kontrolüyle yapılıyor. Sonuç olarak Android tablet telefon yerleşimini, daraltılmış Windows penceresi ise masaüstü yerleşimini almaya devam ediyor.

**Öneri:** `LayoutBuilder` veya `MediaQuery` ile gerçek genişliğe dayanan kırılımlar kullanılmalı. En azından kompakt, orta ve geniş düzenler tanımlanmalı.

### 5. Bölüm listesi gerçek lazy rendering kullanmıyor

Dizi detayı büyük bir `SingleChildScrollView` içinde. Bölüm kartları `map()` ile topluca oluşturuluyor ve ilk aşamada yalnızca 30 öğelik yapay bir sınır uygulanıyor. “Daha fazla” seçildiğinde bütün detay ağacı yeniden oluşturuluyor.

**Öneri:** Detay ekranı `CustomScrollView`, bölüm listesi ise `SliverList`/`SliverList.builder` ile kurulmalı. Böylece yalnızca görünür bölüm kartları oluşturulur.

### 6. Masaüstü detay fragmanı içeriğin üzerini kapatabiliyor

Film ve dizi fragman oynatıcısı sabit `384 × 216` boyutuyla sağ üste `Positioned` olarak yerleştirilmiş. İçerik gövdesinde bu alan için yer ayrılmadığından küçük masaüstü pencerelerinde başlık, açıklama veya işlem düğmelerinin üzerine binebiliyor.

**Öneri:** Geniş ekranda fragman için ayrılmış sağ kolon kullanılmalı; daha dar ekranlarda oynatıcı içerik akışına alınmalı veya yalnızca kullanıcı isteğiyle açılmalı.

### 7. Masaüstü Flutter performans yükü yüksek

Detay açıldığında otomatik fragman araması, ikinci video oynatıcı/decoder, gerçek zamanlı blur, gölgeler ve poster animasyonları birlikte çalışabiliyor. Bu efektler düşük ve orta seviye Windows GPU'larında kare süresi artışına ve kaydırma takılmalarına neden olabilir.

**Öneri:**

- Otomatik fragman oynatma isteğe bağlı yapılmalı.
- Blur ve yoğun gölgeler düşük performans profilinde kapatılmalı.
- Animasyonlar azaltılmış hareket ve GPU performans ayarına bağlanmalı.
- Gizli/`Offstage` ekranlardaki animasyon ve veri abonelikleri duraklatılmalı.

### 8. Fazla sayıda ekran bellekte canlı tutuluyor

Ana navigasyon `IndexedStack` kullanıyor; ana sayfalar aynı anda bellekte kalıyor. Detay açıldığında alttaki poster ızgarası da `Offstage` olarak yaşamaya devam ediyor. Bu yaklaşım sayfa durumunu korusa da görsel cache, provider abonelikleri ve arka plan rebuild yükünü artırıyor.

**Öneri:** Görünmeyen dallardaki pahalı abonelikler ve animasyonlar duraklatılmalı. Detay sayfaları mümkünse bağımsız route olarak ele alınmalı.

## Önerilen uygulama sırası

1. Bölüm verisini typed model ile normalize etmek.
2. Mobil bölüm kartını iki satırlı başlıkla yeniden tasarlamak.
3. Sezon seçiciyi yatay liste/dropdown yapısına dönüştürmek.
4. Film ve dizi için ortak responsive detay iskeleti oluşturmak.
5. Bölüm listesini `SliverList` ile lazy hale getirmek.
6. Masaüstü fragman yerleşimini düzeltmek ve autoplay yükünü azaltmak.
7. Blur, gölge ve animasyonlar için performans profili eklemek.
8. Görünmeyen ekranların arka plan çalışmalarını duraklatmak.

## Eklenmesi gereken arayüz testleri

- 360 × 800 Android telefon
- 412 × 915 Android telefon
- 800 × 1280 Android tablet
- 900 × 500 minimum masaüstü penceresi
- 1280 × 720 masaüstü penceresi
- Uzun bölüm isimleri ve eksik `title` alanı
- 1, 5, 10 ve daha fazla sezonlu diziler
- Fragman açık/kapalı masaüstü detay düzeni

Bu ölçüler için widget ve golden testleri eklenmeden responsive gerilemelerin tekrar oluşma riski yüksektir.
