# Android Release Signing — LifeOs TV

> **PRIVATE REPO ONLY.** Bu dosya keystore şifresini düz metin olarak içerir.
> Repo'yu **asla public yapma**. Public yaparsan APK'yı taklit eden herkes
> aynı paket adıyla sahte sürüm yayınlayabilir.

## Keystore

| Alan | Değer |
|---|---|
| **Dosya** | `android/keystore/lifeostv-release.jks` |
| **Alias** | `lifeostv` |
| **Şifre** (store + key, aynı) | `dG4cROeXKuCTs4DO@gxvh^#lbv@DpAkf` |
| **Algoritma** | RSA 2048 / SHA384withRSA |
| **Geçerlilik** | 10.000 gün (~27 yıl) — oluşturma: 2026-05-16 |
| **DN** | `CN=LifeOs TV, OU=Mobile, O=LifeOs, L=Istanbul, ST=Istanbul, C=TR` |

### Fingerprint'ler (apksigner verify çıktısı)

```
SHA-256: b4:42:dd:34:35:21:03:f8:64:31:ce:e6:cb:de:34:cf:ba:3d:ca:9a:69:00:e4:e1:22:67:47:5d:a9:a2:44:71
SHA-1:   f7:19:90:13:96:cf:d3:4b:01:0d:f0:57:3b:4f:50:23:58:bf:bc:44
MD5:     42:c8:1c:67:f3:0d:23:06:5f:01:3a:95:f9:d0:44:e9
```

Keystore dosyasının SHA-256'sı (bütünlük kontrolü için):
```
9fa98013c9907b15a4efacca64ebd3877c6fc1a5858bd7946deea1d7c32fc041
```

## Build pipeline

`android/app/build.gradle.kts` → `android/key.properties` varsa otomatik
release signing'e geçer. `key.properties` içeriği:

```
storePassword=<yukarıdaki şifre>
keyPassword=<yukarıdaki şifre>
keyAlias=lifeostv
storeFile=../keystore/lifeostv-release.jks
```

`storeFile` path'i `android/app/` modülüne göre relative — bu yüzden `../`
ile bir üst dizine çıkıp `keystore/` klasörüne giriyor.

## Build komutları

```bash
# Fat APK (arm + arm64 + x64)
flutter build apk --release \
  --target-platform android-arm,android-arm64,android-x64

# Per-ABI split (Play Store'a yüklemek için daha küçük APK'lar)
flutter build apk --release --split-per-abi

# App Bundle (Play Store native format)
flutter build appbundle --release
```

Çıktılar:
- APK: `build/app/outputs/flutter-apk/app-release.apk`
- AAB: `build/app/outputs/bundle/release/app-release.aab`

## İmzayı doğrulamak

```bash
# Android SDK build-tools içindeki apksigner ile
"$ANDROID_HOME/build-tools/<version>/apksigner.bat" verify \
  --verbose --print-certs \
  build/app/outputs/flutter-apk/app-release.apk

# Beklenen: "Verified using v2 scheme (APK Signature Scheme v2): true"
# Certificate DN yukarıdakiyle eşleşmeli.
```

## Yedekleme (ZORUNLU)

Keystore + bu dosyayı en az **2 ayrı yere** yedekle:

1. **Şifre yöneticin** (1Password / Bitwarden / KeePass) — `.jks` dosyasını
   attachment olarak ekle, şifreyi ayrı alan olarak yaz.
2. **Şifreli backup** (iCloud Keychain, Google Drive ile AES-256 zip, vb.)

Keystore kaybolursa:
- Play Store'da bu uygulamayı **bir daha asla güncelleyemezsin**
- Yeni paket adıyla baştan yayınlamak + tüm kullanıcıların manuel yeniden
  yüklemesi gerekir
- Tüm kayıtlı kullanıcı verileri (Play tarafında) sıfırlanır

## Restore (yeni makinede build almak için)

1. Bu repo'yu clone et
2. `key.md`'deki bilgilerle `android/key.properties` zaten var → git'ten geliyor
3. `android/keystore/lifeostv-release.jks` zaten git'te → clone ile geliyor
4. `flutter build apk --release` → imzalı APK direkt çıkar

Yeni bir makinede ek kurulum gerekmez — keystore + key.properties git
geçmişinde tutuluyor (private repo olduğu için).
