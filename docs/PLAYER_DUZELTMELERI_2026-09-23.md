# Player düzeltmeleri — birinci paket

Tarih: 23 Eylül 2026

Önceki incelemedeki B11–B15 bulgularının pencere yönetimi, PiP, açılış/kapanış ve hata bildirimi bölümleri için uygulanan değişikliklerdir. Bu paket tüm codec/platform sorunlarının çözüldüğü anlamına gelmez. B15'teki zaman çubuğu seek yoğunluğu ayrı pakette kalmıştır.

## Uygulanan değişiklikler

- Tam ekran, PiP ve üstte tutma aynı pencere denetleyicisinden yönetiliyor. Bir geçiş tamamlanmadan sıradaki geçiş başlamıyor. Native tam ekran olayları düğmenin durumunu güncelliyor; düğmeler karar verirken güncel pencere durumunu okuyor.
- macOS'ta yalnızca `setFullScreen` sonucunu veya pencere bayrağını beklemek yerine `windowDidEnterFullScreen` / `windowDidExitFullScreen` olayları da bekleniyor. Tamamlanmayan geçişler için bekleme sınırlı.
- PiP için minimum boyut 380×230'a indiriliyor; çıkışta uygulamanın 900×500 minimumu geri yükleniyor. Önceki normal pencere geometrisi, maximize/tam ekran ve üstte tutma durumu korunuyor. Pencere boyutlandırma başarısız olursa geri alma deneniyor.
- PiP konumu ekran çalışma alanını kullanan window_manager yardımcısından alınıyor. Bu yardımcı imlecin bulunduğu ekranı seçer; ekran bilgisi alınamıyorsa önceki pencere konumu kullanılır.
- PiP giriş/çıkış işlemleri sıralı; art arda kapat/büyüt tıklamaları kilitli. ESC küçük pencereyi büyütür. PiP oynat/duraklat simgesi gerçek oynatma akışını izler.
- Player kapanınca bekleyen açılışlar geçersiz kılınıyor. Native yapılandırma/açılış ile dispose aynı kaynak üzerinde eşzamanlı çalışmıyor; dispose yalnızca bir kez çağrılıyor. Kurulum sırasında yapılan hızlı kanal değişimlerinde yalnızca en güncel bekleyen yayın açılıyor.
- PiP'ye girişle aynı anda player kapatılması da ele alındı: henüz başlamamış PiP isteği iptal ediliyor, başlamış pencere geçişinin arkasına geri yükleme konuluyor.
- Native oynatma hataları dinleniyor; açılış hataları yakalanıp mevcut hata arayüzünde gösteriliyor. Tekrar deneme ortak açılış akışını kullanıyor; VOD için eldeki oynatma konumu korunuyor. Native hata metni hesap bilgileri içerebileceğinden kullanıcıya ham olarak gösterilmiyor. Otomatik, sınırsız tekrar deneme eklenmedi.
- Ekran kapandıktan sonra bazı devam eden callback ve intro-marker aboneliklerinin kurulması engelleniyor. Eski açılışa ait bekleyen seek/devam et işlemleri yeni açılışa uygulanmıyor.

## Doğrulama

- `flutter test --no-pub`: **239 test geçti**. Bunların 16'sı bu paketle eklendi.
- Değişen uygulama dosyaları ve yeni testler üzerinde `dart analyze`: **sorun yok**.
- Linux release derlemesinin sonucu `player-fixes-2026-09-23/linux-build.log` dosyasındadır.
- Yeni pencere testleri platform kanalını taklit eder. Gecikmeli native durum değişimi, macOS tamamlanma olayının gecikmesi, PiP geri yükleme, boyutlandırma hatasında geri alma ve player kapanışı ile PiP girişinin çakışması kontrol edildi.
- Player oturum testleri kurulum sırasında kapatma, hızlı kanal değiştirme, devam eden open sırasında dispose, başarısız open/kurulum sonrasında yeniden denemeyi kontrol eder. Gerçek decoder/GPU testleri değildir.
- Önceden var olan yerel değişiklikler korunmuştur. `pubspec.lock` önceki inceleme başındaki dosyayla byte düzeyinde aynıdır. Çalıştırmalar mevcut `.dart_tool` bağımlılık çözümünü kullanır; bunun önceki raporda açıklanan SDK uyarlaması devam etmektedir.

## Gerçek cihazda kabul kontrolü

Windows, Linux X11/Wayland ve macOS için:

1. Canlı yayın ve VOD oynatırken tam ekrana gir/çık; hızlı çift tıklama ve ESC ile tekrarla. İşletim sisteminin kendi tam ekran kontrolüyle değiştirdikten sonra uygulama düğmesinin durumunu kontrol et.
2. Normal, maximize ve tam ekran durumlarından PiP'ye geç; büyüt ve kapat. Önceki pencere durumu ile üstte tutma tercihi geri gelmeli; uygulama 380×230 boyutunda kalmamalı.
3. Üstte tutmayı aç, başka uygulamaya odaklan, PiP'ye gir/çık. Linux'ta bu özellik pencere yöneticisi/compositor tarafından desteklenmelidir; eklentinin `isAlwaysOnTop` yanıtı tek başına görsel doğrulama değildir.
4. Yayın yüklenirken player'ı kapat ve hemen başka yayın aç. Eski yayın sonradan başlamamalı, kapanan player'ın sesi sürmemeli.
5. Hızla birden fazla kanal değiştir. Son seçilen kanal açılmalı. Bağlantıyı kesip hata bildirimi ve tekrar denemeyi kontrol et.
6. PiP'ye basar basmaz route'u kapat; küçük pencere veya kapatılmış player'a bağlı overlay kalmamalı.

Android telefon/iPhone için açılış, hızlı kapatma, yeniden açma, arka plana geçiş ve hata bildirimi test edilmelidir. Android'in native PiP geçişi ayrıca gerçek cihazda kontrol edilmelidir.

## Sonraki paket

VOD uzantısı/doğrudan adres, URL kodlama, seek yoğunluğu, M3U içerik kimliği ve ilerleme kaydı; ardından ayrı Android TV ExoPlayer yolu, codec/donanım çözme ve tamponlama, ses/altyazı, Cast ve mobil platform eksikleri. iPhone native PiP bu pakette uygulanmamıştır.
