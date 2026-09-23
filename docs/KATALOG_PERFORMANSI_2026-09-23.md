# Katalog araması ve bölüm listesi — 23 Eylül 2026

Arama indeksinin olmadığı veya yazım hatalı sorgularda kullanılan 1.000/6.000 kayıt sınırı kaldırıldı. Hesap, gizli kategori ve yetişkin filtresi her sayfada korunur. SQLite indeksli eşleşmeleri süzer; normalizasyon ve yazım hatası eşleştirmesi 256 kayıtlık ayrı işçi işleriyle çalışır. Her iş arasında eski sorgu iptali kontrol edilir. Sonuçlar tüm katalogda tam başlık, başlık başlangıcı, başlıktaki tüm kelimeler, metadata eşleşmesi önceliğiyle sıralanır; puan ve kararlı kimlikler eşitlikleri çözer. `%`/`_` karakterleri SQL wildcard'ına dönüşmez. Kısa kelime ve bölüm/sequel rakamları sorgudan atılmaz.

Ölçüm sırasında mevcut indeks oluşturucunun closure üzerinden repository/veritabanı bağlantısını işçiye taşıdığı ve `NativeFinalizer` gönderim hatası verdiği görüldü. İşçiye yalnızca veri kayıtları gönderilerek düzeltildi. İşçi çalışırken kaynak metadata değişmişse eski indeks yazımı koşullu update ile reddedilir. Bu koruma kanal alanlarını kapsar; bağımsız kategori adı değişiminin tam sürümlemesi ayrı konudur.

Dizi detayındaki büyüyen `SingleChildScrollView` bölüm kartları yerine `SliverList.builder` kullanılır. Görünür alan ve kısa önbellek dışındaki kartlar oluşturulmaz; odaklanan kart görünür alana kaydırılır. 200 bölümlük fixture'da 45 kez aşağı okla 46. bölüme ulaşılıp oynatıcı açıldı, geri dönüşte detayın oynat düğmesine odak döndü. Testte aynı anda 25'ten az bölüm kartı vardı. Telefon/dar pencere boyutları ve önceki sezonlar arası oynatma testi korundu.

## Ölçüm ve sınırlar

[10.000 kayıt ölçümü](catalog-performance-2026-09-23/search-benchmark.json):

| Yol | Toplam süre | En uzun ana timer aralığı |
|---|---:|---:|
| Eşit katalog kapsamıyla ana iş parçacığında fuzzy karşılaştırma | 182 ms | 179 ms |
| İndekssiz tam eşleşme, sayfalı işçi | 604 ms | 26 ms |
| İndekssiz yazım hatası, sayfalı işçi | 1.043 ms | 18 ms |
| İndeksli tam eşleşme | 4,9 ms | 11 ms |

İndekssiz/fuzzy aramada toplam gecikme karşılaştırmadan daha uzundur; amaç tüm katalog kapsamını korurken UI bloke süresini düşürmektir. Eski sınırlı yol fixture'ın sonundaki içeriği hiç bulamıyordu. Ölçüm sentetik Linux host testidir; timer aralığı video kare süresi değildir. Test SQLite'ı aynı isolate'da çalıştırır; üretim bağlantısı işçi kullanır. Fiziksel düşük RAM'li TV kabulü ayrıca gereklidir.

Regresyonlar: 6.000 kayıt ötesi hedef, indeksli/indekssiz birlikte global sıralama, Türkçe harfler, kısa sözcükler/rakamlar, literal wildcard, gizli/yetişkin/hesap kapsamı, eski sorgu iptali, indeks işçisi, oynatma sırasında indeks bekletme ve lazy D-pad akışı. Tam suite/derleme sonuçları [doğrulama dosyasında](catalog-performance-2026-09-23/validation.json).
