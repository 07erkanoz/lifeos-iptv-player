# 🚨 ÖNEMLİ — Drift Migration Pattern Borç Kaydı

Bu dosya **acil teknik borç** ve **gelecek migration'larda dikkat edilmesi gereken kuralı** içerir.
Başka makineye geçildiğinde / yeni Drift schema versiyonu eklenmeden önce **mutlaka oku**.

---

## ⚠️ Şu Anda Mevcut Risk

`lib/data/datasources/local/database.dart` içindeki **v17 → v18 migration**'ı, Sprint 2a'da
şu şekilde yazılmıştı:

```dart
await m.addColumn(favorites, favorites.profileId);
await m.addColumn(playbackProgress, playbackProgress.profileId);
// ...
```

### Sorun

`Favorites` / `PlaybackProgress` / `Watchlist` / `AiFeedback` / `SeriesTracking` /
`SearchHistory` tablolarının **PRIMARY KEY**'ine `profileId` eklendi:

```dart
@override
Set<Column> get primaryKey => {streamId, streamType, profileId};
```

**Ama SQLite'ta `ALTER TABLE ... ADD COLUMN` ile composite primary key DEĞİŞTİRİLEMEZ.**
Drift'in `m.addColumn` sadece kolonu ekler — primary key yapısı `tables.dart`'taki yeni
tanıma uymaz. Bu durumda:

- Eski tablo eski PK'siyle çalışmaya devam eder
- Drift'in beklediği PK farklı → upsert / conflict resolution davranışı **belirsiz**
- Bazı durumlarda Drift schema'nın "bozuk" gördüğü durum → veritabanı yeniden oluşturulabilir → **VERİ KAYBI**

### Gerçekleşmiş Olay

**2026-05-23**: Kullanıcının telefonunda mevcut `versionCode=2001` (off-fork build) ile
update yapıldığında migration crash etti, kullanıcı login ekranı gördü. Tablolar
duruyordu ama migration "duplicate column" exception fırlatıyordu, app crash'liyordu.

Geçici fix (`3d5357a`): `PRAGMA table_info` ile her kolonu probe ederek atlamak.
**Bu sadece "crash etme" düzeltmesi — asıl PK sorununu çözmüyor.**

---

## 🛠️ Doğru Çözüm: Create-Copy-Drop-Rename Pattern

SQLite'ta primary key değiştirmek için **tek doğru yol**:

```sql
BEGIN TRANSACTION;

-- 1. Yeni şemayla geçici tablo oluştur
CREATE TABLE favorites_new (
  stream_id INTEGER NOT NULL,
  stream_type TEXT NOT NULL,
  name TEXT NOT NULL,
  thumbnail TEXT,
  added_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
  profile_id INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (stream_id, stream_type, profile_id)
);

-- 2. Eski tablodan veriyi yeniye taşı (profile_id = 1 default)
INSERT INTO favorites_new (stream_id, stream_type, name, thumbnail, added_at, profile_id)
SELECT stream_id, stream_type, name, thumbnail, added_at, 1
FROM favorites;

-- 3. Eski tabloyu düşür
DROP TABLE favorites;

-- 4. Yeniyi adlandır
ALTER TABLE favorites_new RENAME TO favorites;

COMMIT;
```

Bu 6 tablo için ayrı ayrı tekrarlanmalı:
- `favorites`
- `playback_progress`
- `watchlist`
- `series_tracking`
- `ai_feedback`
- `search_history`

### Drift'in Önerdiği Yöntem

Drift 2.x'in `Migrator.alterTable` API'si var. Daha tip-güvenli ve test edilebilir:

```dart
await m.alterTable(
  TableMigration(
    favorites,
    newColumns: [favorites.profileId],
    columnTransformer: {
      favorites.profileId: const Constant(1),
    },
  ),
);
```

Bu **otomatik olarak create-copy-drop-rename pattern'ını** uygular. Drift docs:
https://drift.simonbinder.eu/Migrations/api/#complex-migrations

---

## 📋 Yapılacaklar (Sıralı)

### Acil (Bir sonraki Drift schema değişikliğinden ÖNCE)

1. **v18 migration'ı yeniden yaz** — `alterTable` + `TableMigration` ile create-copy-drop-rename
2. **Test**: birden fazla user_version durumu (16, 17, half-applied, v18 zaten) üzerinde manuel test
3. **Eski idempotent probe fix'i kaldır** veya `from < 18` dalında ayrıca tut
4. **Schema doğrulama**: `schemaTest` / Drift'in `Schema Migration Verification` pattern'ı

### Önleyici

5. **Yeni schema kuralı**: Her composite-PK değişikliği `TableMigration` kullanmalı, **asla** sadece `addColumn`
6. **CI test ekle**: her schema versiyonundan diğerine migration testi otomatik koşmalı
7. **Backup auto-trigger**: schema upgrade'i öncesi otomatik internal snapshot (kullanıcı yedeği değil — recovery için bir kopya)

### Faz 2 Spesifik

8. **Profile cleanup**: Mevcut `profileId` default=1 olan rows için doğrulama. Boş profile_id olan satır kalmamalı

---

## 🔍 Neden Bu Sefer "Veri Kayıp" Sanıldı

Telefondaki off-fork build (`versionCode=2001`) muhtemelen başka bir patch ile schema'yı
manuel olarak v18 seviyesine getirmiş, ama Drift'in `user_version` PRAGMA'sı senkron değildi.
Bu durumda:

1. Yeni APK Drift v18 schema'sı bekledi
2. PRAGMA `user_version < 18` rapor etti
3. `onUpgrade(< 18)` tetiklendi → `ADD COLUMN profile_id` → **duplicate column** exception
4. App crash → kullanıcı login ekranı gördü → "veriler gitti" zannetti
5. **Aslında tablolar duruyordu**, idempotent probe fix'iyle (`3d5357a`) erişilebilir hale geldi

---

## 🧠 Bu Olaydan Çıkardığım Dersler

1. **Drift schema değişikliklerinde `addColumn` yetersizdir** — composite PK + complex schema için `TableMigration` zorunlu
2. **Migration code path'leri farklı user_version başlangıçlarında çalıştırılmalı** (test matrisi: 16, 17, half-applied v18, clean v18)
3. **Sandbox storage'a yedek almak yetmez** — kullanıcının erişebileceği klasöre yazılmalı (v1.1.1 fix bunu yaptı)
4. **Auth landing screen'inde restore button zorunlu** — kullanıcının "ben her şeyi kaybettim" durumundan çıkış yolu olmalı (v1.1.1 fix bunu yaptı)
5. **Release build debuggable=false** — `adb run-as` ile veri kurtarma yok. Backup mekanizmasının ÖNCEDEN çalışması şart

---

## 📝 İlgili Commit Tarihçesi

| Commit | Açıklama |
|---|---|
| `b66c7ef` | Sprint 2a — buggy `addColumn` migration (v17→v18) |
| `aaec5e4` | Sprint 2b — repository'ler profile_id ile filtrele |
| `881650d` | Sprint 2c — profile picker + PIN |
| `1864a25` | Sprint 2d — group mood mode |
| `b573ecc` | v1.1.1 — landing screen restore button + file picker SAF export |
| `3d5357a` | **v1.1.2 — idempotent migration probe** (geçici fix, ASIL SORUN HALA VAR) |

---

## 🚦 Status

**Şu an**: Crash önleniyor (idempotent probe), kullanıcı verisine erişebiliyor.
**Risk**: Bir sonraki composite PK değişikliği veya schema v19+ aynı tuzağa düşebilir.
**Acil yapılacak**: `TableMigration` ile v18'i yeniden yaz (bir sonraki schema değişikliğinden önce).

**Bu işin sahibi**: Drift schema'ya dokunan herkes bu dosyayı okumalı.

---

*Son güncelleme: 2026-05-23 — v1.1.2+2012 release sonrası*
