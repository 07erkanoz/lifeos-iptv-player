# Android TV geçmiş EPG ve canlıya dönüş — 23 Eylül 2026

TV player EPG paneli artık geçmiş beş günlük mevcut programları da gösterir. Kullanıcı adı/şifresi olan Xtream hesabında geçmiş program seçimi, aynı player oturumu içinde timeshift akışını açar. Sağlayıcı HTTP başlıkları korunur. Tekrar yayını canlı etiketi taşımaz; konum çubuğu ve sarma kullanılır. Kalite değişimi tekrar yayınının konumunu koruyabilir. Canlı düğmesi, aynı kanalın listeden seçilmesi veya kanal değiştirme canlı akışa döndürür. VOD hesap geçmişine sahte film kaydı eklenmez.

Arşiv akışı hata verdiğinde “yeniden dene” ve “canlı TV” düğmeleri kullanılabilir. Hata ekranındaki ilk odak açıkça retry düğmesine taşınır; aşağı ok/OK ile canlı yayına dönülebilir. Panel kapatma, kalite ve ses seçimlerinden kalan odak, hata düğmelerini engellemez.

Ayrıca kanal listesi verilip `currentChannelIndex` verilmezse başlangıç kanalı `streamId` ile bulunur. Önceden koşulsuz ilk kanal seçiliyor ve izleme geçmişi/EPG yanlış kanala bağlanabiliyordu.

Testler normal timeshift açılışı/canlıya dönüşü, sağlayıcı başlıklarını, canlı etiketini, hata sonrası D-pad dönüşünü ve eksik indeksin kimlikle çözümünü kapsar. Önceki kalite/ses/altyazı/panel/lifecycle testleri de korundu. [Doğrulama](tv-catchup-2026-09-23/validation.json).

Arşiv bulunabilirliği sağlayıcının desteğine ve saklama süresine bağlıdır; hesap türü/kimlik bilgisi kontrolü arşiv garantisi değildir. URL tarihi mevcut ortak Xtream builder'ın yerel saat davranışını kullanır; farklı sunucu saat dilimleri gerçek hesapla doğrulanmalıdır. M3U catch-up şablonları ve Android TV Cast arayüzü bu paketin kapsamında tamamlanmadı. Fiziksel Android TV bağlı olmadığı için gerçek kumanda/codec/HDR kabulü yapılmadı.
