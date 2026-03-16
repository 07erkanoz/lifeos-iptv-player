# LifeOs TV - Flathub Packaging Guide (EN + TR)

## English

## Purpose of this folder
This directory contains everything needed to prepare a Flathub submission for LifeOs TV.

Included files:
- `io.github.erkanoz.LifeOsTV.yml`: Flatpak manifest template.
- `io.github.erkanoz.LifeOsTV.desktop`: Desktop launcher metadata.
- `io.github.erkanoz.LifeOsTV.metainfo.xml`: AppStream metadata (store listing).
- `APP_DESCRIPTION_TR_EN.md`: Full product description + usage guide in English and Turkish.
- `FLATHUB_PR_TR_EN.md`: Copy-paste PR title/body template for Flathub submission.

## What is already prepared
- App ID / desktop ID / metainfo ID alignment.
- Runtime + SDK + Flutter SDK extension declarations.
- Linux Flutter build install paths under `/app`.
- Icon/desktop/metainfo installation in standard Flatpak locations.
- Source is pinned to an immutable git commit (Flathub-friendly).

## Local validation workflow

### 1) Install tools/runtime
```bash
flatpak install flathub \
  org.flatpak.Builder \
  org.freedesktop.Sdk//24.08 \
  org.freedesktop.Platform//24.08 \
  org.freedesktop.Sdk.Extension.flutter//24.08
```

### 2) Build and install locally
```bash
flatpak-builder --user --install --force-clean \
  --install-deps-from=flathub \
  build-dir packaging/flatpak/io.github.erkanoz.LifeOsTV.yml
```

### 3) Run app
```bash
flatpak run io.github.erkanoz.LifeOsTV
```

### 4) Lint checks
```bash
flatpak run --command=flatpak-builder-lint org.flatpak.Builder \
  manifest packaging/flatpak/io.github.erkanoz.LifeOsTV.yml

flatpak run --command=flatpak-builder-lint org.flatpak.Builder \
  appstream packaging/flatpak/io.github.erkanoz.LifeOsTV.metainfo.xml
```

## Submission checklist (Flathub)
1. Fork `flathub/flathub`.
2. Create app directory with these files.
3. Update `commit:` in manifest to the exact release commit you want to publish.
4. Open PR against Flathub's `new-pr` target.
5. Address review feedback (permissions, metadata clarity, reproducibility).

## Metadata/content notes
- Keep legal text explicit: app is a media player and does not provide content.
- Use `APP_DESCRIPTION_TR_EN.md` as your source for long/short listing copy.
- Use `FLATHUB_PR_TR_EN.md` for ready PR title/description text.
- Keep EN and TR messaging aligned with real app behavior.

---

## Türkçe

## Bu klasörün amacı
Bu dizin, LifeOs TV için Flathub gönderimini hazırlamakta gereken temel dosyaları içerir.

İçerik:
- `io.github.erkanoz.LifeOsTV.yml`: Flatpak manifest şablonu.
- `io.github.erkanoz.LifeOsTV.desktop`: Masaüstü başlatıcı metadata.
- `io.github.erkanoz.LifeOsTV.metainfo.xml`: AppStream metadata (mağaza metni).
- `APP_DESCRIPTION_TR_EN.md`: İngilizce + Türkçe detaylı ürün ve kullanım anlatımı.
- `FLATHUB_PR_TR_EN.md`: Flathub gönderimi için hazır PR başlık/açıklama metni.

## Hazır olanlar
- App ID / desktop ID / metainfo ID uyumu.
- Runtime + SDK + Flutter SDK extension tanımları.
- Linux Flutter build çıktısının `/app` altına kurulumu.
- Icon/desktop/metainfo dosyalarının standart Flatpak dizinlerine kurulumu.
- Kaynak immutable commit'e pinlenmiş durumda (Flathub uyumlu).

## Lokal doğrulama akışı

### 1) Araç/runtime kurulumu
```bash
flatpak install flathub \
  org.flatpak.Builder \
  org.freedesktop.Sdk//24.08 \
  org.freedesktop.Platform//24.08 \
  org.freedesktop.Sdk.Extension.flutter//24.08
```

### 2) Lokal build + kurulum
```bash
flatpak-builder --user --install --force-clean \
  --install-deps-from=flathub \
  build-dir packaging/flatpak/io.github.erkanoz.LifeOsTV.yml
```

### 3) Uygulamayı çalıştır
```bash
flatpak run io.github.erkanoz.LifeOsTV
```

### 4) Lint kontrolleri
```bash
flatpak run --command=flatpak-builder-lint org.flatpak.Builder \
  manifest packaging/flatpak/io.github.erkanoz.LifeOsTV.yml

flatpak run --command=flatpak-builder-lint org.flatpak.Builder \
  appstream packaging/flatpak/io.github.erkanoz.LifeOsTV.metainfo.xml
```

## Flathub gönderim kontrol listesi
1. `flathub/flathub` reposunu forkla.
2. Uygulama klasörünü açıp bu dosyaları ekle.
3. Manifest içindeki `commit:` alanını yayınlayacağın kesin release commit'i ile güncelle.
4. Flathub `new-pr` hedefine PR aç.
5. Review geri bildirimlerini (izinler, metadata netliği, reproducible build) düzelt.

## Metadata/içerik notları
- Yasal metni net tut: uygulama oynatıcıdır, içerik sağlamaz.
- Uzun/kısa mağaza metinleri için `APP_DESCRIPTION_TR_EN.md` dosyasını kaynak al.
- Hazır PR metni için `FLATHUB_PR_TR_EN.md` dosyasını kullan.
- EN ve TR açıklamaların uygulamadaki gerçek davranışla birebir uyumlu olmasına dikkat et.
